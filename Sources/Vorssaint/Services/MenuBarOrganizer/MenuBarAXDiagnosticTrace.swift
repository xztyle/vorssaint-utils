// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin

/// Explicit local diagnostics cover status items only. Text attributes are
/// represented by presence/length, never menu contents or document/window data.
final class MenuBarAXDiagnosticTrace {
    static var destination: URL? {
        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--menu-bar-ax-diagnostics=") }) else { return nil }
        let path = String(argument.dropFirst("--menu-bar-ax-diagnostics=".count))
        guard path.hasPrefix("/"), path.hasSuffix(".json") else { return nil }
        return URL(fileURLWithPath: path)
    }

    let deadline = Date().addingTimeInterval(20)
    var applications: [[String: Any]] = []
    var candidates: [[String: Any]] = []
    var limited = false
    private let destination: URL
    private let guiRunning: Bool
    private let records: [[String: Any]]

    init(destination: URL, records: [MenuBarOrganizerWindowRecord], guiRunning: Bool = false) {
        self.destination = destination
        self.guiRunning = guiRunning
        self.records = records.prefix(128).map {
            ["windowID": $0.windowID, "hostPID": $0.ownerPID, "hostBundle": $0.ownerBundleIdentifier,
             "titlePresent": !$0.title.isEmpty, "genericHostTitle": MenuBarOrganizerSupport.isGenericControlCenterHostedTitle($0.title),
             "frame": Self.rect($0.frame)]
        }
    }

    var shouldContinue: Bool {
        let allowed = Date() < deadline && applications.count < 256
        if !allowed { limited = true }
        return allowed
    }

    func addCandidate(record: MenuBarOrganizerWindowRecord, source: MenuBarItemSourceIdentity, frame: CGRect,
                      score: CGFloat?, rejection: String?) {
        guard candidates.count < 4096 else { limited = true; return }
        candidates.append(["windowID": record.windowID, "sourcePID": source.pid,
            "sourceBundle": source.bundleIdentifier, "sourceFrame": Self.rect(frame),
            "stableTitlePresent": source.stableTitle != nil, "score": score as Any? ?? NSNull(),
            "rejection": rejection as Any? ?? NSNull()])
    }

    func finish(matches: [CGWindowID: MenuBarItemSourceIdentity]) {
        let report: [String: Any] = ["schema": 1, "pid": getpid(), "parentPID": getppid(),
            "bundle": Bundle.main.bundleIdentifier ?? "", "bundlePath": Bundle.main.bundleURL.path,
            "accessibility": AXIsProcessTrusted(), "inventoryProbe": CommandLine.arguments.contains("--menu-bar-inventory"),
            "guiRunning": guiRunning,
            "limited": limited, "records": records, "applications": applications, "candidates": candidates,
            "matches": matches.map { ["windowID": $0.key, "sourceBundle": $0.value.bundleIdentifier,
                                      "singleItemIdentity": $0.value.usesSingleItemIdentity,
                                      "protected": MenuBarOrganizerSupport.isSystemImmovable(bundleIdentifier: $0.value.bundleIdentifier, title: $0.value.stableTitle ?? ""),
                                      "stableTitlePresent": $0.value.stableTitle != nil] }]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return }
        let fd = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        try? handle.write(contentsOf: data)
    }

    static func rect(_ value: CGRect) -> [CGFloat] {
        [value.minX, value.minY, value.width, value.height]
    }

    static func textPresence(_ value: String?) -> [String: Any] {
        ["present": value != nil, "length": value?.count ?? 0,
         "generic": value.map(MenuBarOrganizerSupport.isGenericControlCenterHostedTitle) ?? true]
    }

    static func geometry(_ value: AXValue?) -> [CGFloat] {
        guard let value else { return [] }
        var numbers: [CGFloat] = []
        switch AXValueGetType(value) {
        case .cgRect:
            var rect = CGRect.zero
            if AXValueGetValue(value, .cgRect, &rect) { numbers = Self.rect(rect) }
        case .cgPoint:
            var point = CGPoint.zero
            if AXValueGetValue(value, .cgPoint, &point) { numbers = [point.x, point.y] }
        case .cgSize:
            var size = CGSize.zero
            if AXValueGetValue(value, .cgSize, &size) { numbers = [size.width, size.height] }
        default: break
        }
        return numbers.allSatisfy(\.isFinite) ? numbers : []
    }
}
