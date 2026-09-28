// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

/// A conservative source guard, supplemented by executable lifecycle tests.
/// Unrecognized ownership patterns fail closed instead of receiving loop credit.
enum RepositoryTapTeardownTests {
    static func run(_ suite: TestSuite, sources: [String: String]) {
        scannerRegressions(suite)
        let owners = sources.filter { code($0.value).contains("CGEvent.tapCreate") }
        let failures = owners.sorted { $0.key < $1.key }.compactMap { path, source in
            violation(source).map { "\(path): \($0)" }
        }
        suite.expect(!owners.isEmpty && failures.isEmpty,
                     "every event tap owner invalidates all owned ports on teardown, across \(owners.count) owners: \(failures)")
    }

    static func violation(_ source: String) -> String? {
        let source = code(source)
        let creations = count("CGEvent.tapCreate", in: source)
        guard creations > 0 else { return nil }
        let collections = captures(#"\bvar\s+(\w+)\s*:\s*\[\s*\(CFMachPort,\s*CFRunLoopSource\)\s*\]"#, in: source)
        if !collections.isEmpty {
            guard collections.count == 1, let name = collections.first?.first,
                  groupedOwnership(source, collection: name, creations: creations) else {
                return "tap collection must register every created port and remove/invalidate every stored pair"
            }
            return nil
        }
        let invalidations = count("CFMachPortInvalidate", in: source) + count("PointerTapRunLoop.remove(", in: source)
        return invalidations < creations ? "\(creations) taps, \(invalidations) invalidated" : nil
    }

    private static func groupedOwnership(_ source: String, collection: String, creations: Int) -> Bool {
        let installers = matches(#"func\s+(\w+)\s*\(\s*_\s+(\w+)\s*:\s*CFMachPort\s*\)[^{]*\{"#, in: source)
        let bindings = captures(#"\blet\s+(\w+)\s*=\s*CGEvent\.tapCreate(?:ForPid)?\s*\("#, in: source).compactMap(\.first)
        guard bindings.count == creations, Set(bindings).count == bindings.count else { return false }
        return installers.contains { match in
            let name = capture(1, match: match, source: source)
            let tap = capture(2, match: match, source: source)
            let body = block(after: match.range, in: source)
            let append = NSRegularExpression.escapedPattern(for: "\(collection).append((\(tap),")
            guard !matches(append + #"\s*\w+\s*\)\)"#, in: body).isEmpty,
                  bindings.allSatisfy({ count("\(name)(\($0))", in: source) == 1 }) else { return false }
            return completeTeardown(source, collection: collection)
        }
    }

    private static func completeTeardown(_ source: String, collection: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: collection)
        let loops = matches(#"for\s+\((\w+),\s*(\w+)\)\s+in\s+"# + escaped + #"\s*\{"#, in: source)
        return loops.contains { loop in
            let tap = capture(1, match: loop, source: source)
            let runLoopSource = capture(2, match: loop, source: source)
            let body = block(after: loop.range, in: source)
            let cleanup = body.contains("CGEvent.tapEnable(tap: \(tap), enable: false)")
                && body.contains("CFMachPortInvalidate(\(tap))")
                && !matches(#"CFRunLoopRemoveSource\([^\n]*,\s*"# + runLoopSource + #",\s*\.commonModes\)"#, in: body).isEmpty
            let remaining = (source as NSString).substring(from: NSMaxRange(loop.range) + (body as NSString).length)
            let nextLine = remaining.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty && $0 != "}" }
            return cleanup && ["\(collection) = []", "\(collection).removeAll()"].contains(nextLine ?? "")
        }
    }

    private static func block(after header: NSRange, in source: String) -> String {
        let source = source as NSString
        let start = NSMaxRange(header)
        var depth = 1
        for index in start..<source.length {
            if source.character(at: index) == 123 { depth += 1 }
            if source.character(at: index) == 125 { depth -= 1 }
            if depth == 0 { return source.substring(with: NSRange(location: start, length: index - start)) }
        }
        return ""
    }

    private static func code(_ source: String) -> String {
        source.components(separatedBy: "\n").map { line in
            String(line.components(separatedBy: "//").first ?? "")
        }.joined(separator: "\n")
    }

    private static func count(_ value: String, in source: String) -> Int { source.components(separatedBy: value).count - 1 }
    private static func matches(_ pattern: String, in source: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern).matches(in: source, range: NSRange(source.startIndex..., in: source))) ?? []
    }
    private static func capture(_ index: Int, match: NSTextCheckingResult, source: String) -> String {
        (source as NSString).substring(with: match.range(at: index))
    }
    private static func captures(_ pattern: String, in source: String) -> [[String]] {
        matches(pattern, in: source).map { match in (1..<match.numberOfRanges).map { capture($0, match: match, source: source) } }
    }

    private static func scannerRegressions(_ suite: TestSuite) {
        let valid = groupedFixture
        suite.expect(violation(valid) == nil, "one collection loop owns both dynamically registered taps")
        suite.expect(violation(valid.replacingOccurrences(of: "pairs", with: "ownedPorts")) == nil,
                     "grouped cleanup recognition follows ownership, not an allowlisted variable or file")
        for deleted in ["install(second)", "CFMachPortInvalidate(port)",
            "CGEvent.tapEnable(tap: port, enable: false)", "CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)", "pairs = []"] {
            suite.expect(violation(valid.replacingOccurrences(of: deleted, with: "")) != nil,
                         "grouped guard rejects missing lifecycle step: \(deleted)")
        }
        suite.expect(violation(valid.replacingOccurrences(of: "CFMachPortInvalidate(port)", with: "CFMachPortInvalidate(other)")) != nil,
                     "invalidating an unrelated port does not clean the owned collection")
        suite.expect(violation(valid + "\nlet extra = CGEvent.tapCreate()") != nil, "a newly unregistered tap cannot borrow loop cleanup credit")
        suite.expect(violation("let first = CGEvent.tapCreate()\nlet second = CGEvent.tapCreateForPid()\nCFMachPortInvalidate(first)") != nil,
                     "the existing individual-port leak guard remains strict")
        suite.expect(violation("let first = CGEvent.tapCreate()\n// CFMachPortInvalidate(first)") != nil,
                     "commented cleanup never satisfies the guard")
    }

    private static let groupedFixture = """
        var pairs: [(CFMachPort, CFRunLoopSource)] = []
        func start() {
            let first = CGEvent.tapCreate()
            install(first)
            let second = CGEvent.tapCreateForPid()
            install(second)
        }
        func install(_ port: CFMachPort) {
            let source = makeSource(port)
            pairs.append((port, source))
        }
        func close() {
            for (port, source) in pairs {
                CGEvent.tapEnable(tap: port, enable: false)
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                CFMachPortInvalidate(port)
            }
            pairs = []
        }
        """
}
