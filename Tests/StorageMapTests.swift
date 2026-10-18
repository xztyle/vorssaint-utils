// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

enum StorageMapTests {
    static func run(_ suite: TestSuite) {
        layout(suite)
        remainder(suite)
        navigation(suite)
        do { try scannedContent(suite) } catch { suite.expect(false, "storage map generated fixture failed: \(error)") }
        for language in AppLanguage.allCases {
            suite.expect(StorageMapStrings.values[language]?.count == StorageMapStrings.Key.allCases.count,
                         "storage map has every label in \(language)")
            for key in StorageMapStrings.Key.allCases {
                suite.expect(!StorageMapStrings(language: language)[key].isEmpty, "storage map labels are not empty")
            }
        }
    }

    private static func layout(_ suite: TestSuite) {
        let items = (1...16).map { StorageMapItem(id: "\($0)", url: nil, bytes: Int64($0 * $0), kind: .file) }
        for size in [CGSize(width: 640, height: 260), CGSize(width: 260, height: 640), CGSize(width: 120, height: 120)] {
            let circles = StorageMapLayout.circles(items, size: size)
            suite.expect(circles.count == items.count, "every bounded map item gets a circle")
            for (index, circle) in circles.enumerated() {
                suite.expect(circle.center.x - circle.radius >= -0.0001 && circle.center.y - circle.radius >= -0.0001
                    && circle.center.x + circle.radius <= size.width + 0.0001 && circle.center.y + circle.radius <= size.height + 0.0001,
                    "storage bubbles stay inside wide, tall and small viewports")
                let ratio = circle.radius * circle.radius / (circles[0].radius * circles[0].radius)
                suite.expect(abs(ratio - Double(items[index].bytes) / Double(items[0].bytes)) < 0.00001,
                             "area, rather than diameter, is proportional to measured bytes")
                for other in circles.dropFirst(index + 1) {
                    suite.expect(hypot(circle.center.x - other.center.x, circle.center.y - other.center.y) >= circle.radius + other.radius,
                                 "packed circles never overlap their hit targets")
                }
            }
        }
        suite.expect(StorageMapLayout.circles([], size: .init(width: 640, height: 260)).isEmpty, "empty maps have no fake storage")
        suite.expect(StorageMapLayout.circles(items, size: .zero).isEmpty, "unlaid-out views have no invalid circles")
        suite.expect(StorageMapLayout.circles(items, size: .init(width: Double.infinity, height: 260)).isEmpty,
                     "nonfinite viewport measurements are rejected")
    }

    private static func remainder(_ suite: TestSuite) {
        let items = (1...50_000).map { StorageMapItem(id: "\($0)", url: nil, bytes: Int64(50_001 - $0), kind: .file) }
        let content = StorageMapContent(items: items)
        let bubbles = content.bubbles
        suite.expect(bubbles.count == 16 && bubbles.last?.kind == .other, "large folders have a bounded map and a smaller-items group")
        suite.expect(bubbles.reduce(0) { $0 + $1.bytes } == items.reduce(0) { $0 + $1.bytes },
                     "the smaller-items bubble retains all measured bytes")
        suite.expect(bubbles.last?.count == 49_985 && content.items.count == 50_000, "grouping does not remove items from the list")
        let extreme = Array(repeating: StorageMapItem(id: "large", url: nil, bytes: .max, kind: .file), count: 30)
        suite.expect(StorageMapContent(items: extreme).bubbles.last?.bytes == .max, "extreme grouped sizes cannot overflow")
        suite.expect(StorageMapContent(items: [.init(id: "empty", url: nil, bytes: 0, kind: .file)]).bubbles.isEmpty,
                     "zero-size items remain in the list without invented bubble area")
    }

    private static func navigation(_ suite: TestSuite) {
        let root = URL(fileURLWithPath: "/generated/storage", isDirectory: true)
        let child = root.appendingPathComponent("Child", isDirectory: true)
        let grandchild = child.appendingPathComponent("Nested", isDirectory: true)
        var path = StorageMapNavigation()
        path.visit(root); path.visit(child); path.visit(grandchild)
        suite.expect(path.breadcrumbs(roots: [root]).map(\.path) == [root.path, child.path, grandchild.path],
                     "breadcrumbs contain the scanned root and each visited directory")
        suite.expect(path.parent(roots: [root])?.path == child.path, "moving up stays within the scanned root")
        path.back()
        suite.expect(path.current == child && path.canGoForward, "Back retains a Forward destination")
        path.forward()
        suite.expect(path.current == grandchild, "Forward restores the visited folder")
        path.back(); path.visit(root)
        suite.expect(!path.canGoForward && path.current == root, "a new visit replaces the discarded forward path")
        suite.expect(path.parent(roots: [root]) == nil, "moving up from a root returns to the scanned-folder overview")
        path.visit(URL(fileURLWithPath: root.path))
        suite.expect(path.current == root, "a slash representation does not add another visit")
        path.reset()
        suite.expect(path.current == nil && !path.canGoBack && !path.canGoForward, "choosing new scan roots clears browsing history")
        path.visit(URL(fileURLWithPath: "/outside"))
        suite.expect(path.breadcrumbs(roots: [root]).isEmpty, "breadcrumbs never manufacture a path outside the scan")
    }

    private static func scannedContent(_ suite: TestSuite) throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("AsterStorageMap-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let root = try StorageLocalAccess.canonicalRoot(temporary)
        let child = try populate(root)
        let result = StorageFolderScanner.scan(roots: [root], cancellation: .init())
        let overview = StorageMapContent.make(result: result, roots: [root, child], folder: nil)
        suite.expect(overview.items.count == 1 && overview.items.first?.bytes == result.totalBytes,
                     "nested selected roots do not double-count storage in the overview")
        suite.expect(overview.files.isEmpty, "the overview list and map show the same folder level")
        let inside = StorageMapContent.make(result: result, roots: [root], folder: root)
        suite.expect(inside.items.count == 2 && inside.files.count == 1 && inside.folders.count == 1,
                     "drilling shows only direct files and folders")
        suite.expect(inside.items.reduce(0) { $0 + $1.bytes } == result.totalBytes,
                     "folder totals and direct-file bytes balance without counting descendants twice")
        let leaf = StorageMapContent.make(result: result, roots: [root], folder: child)
        suite.expect(leaf.files.first?.url.lastPathComponent == "Nested.bin" && leaf.folders.isEmpty,
                     "a leaf folder retains its file preview and selection source")
        suite.expect(StorageMapContent.make(result: result, roots: [root], folder: root, minimumBytes: 1_000_000).files.isEmpty,
                     "the large-file filter still uses logical file size")
        suite.expect(StorageMapContent.make(result: result, roots: [root], folder: nil, minimumBytes: 1).files.count == 2,
                     "large-file searches across scanned roots retain nested files")
    }

    private static func populate(_ root: URL) throws -> URL {
        let child = root.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(repeating: 7, count: 8192).write(to: root.appendingPathComponent("Root.bin"))
        try Data(repeating: 9, count: 4096).write(to: child.appendingPathComponent("Nested.bin"))
        return child
    }
}
