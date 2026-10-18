// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import AppKit
import Combine

@MainActor
final class MenuBarNativeLayoutAccess: ObservableObject {
    static let shared = MenuBarNativeLayoutAccess()
    static let bookmarkKey = DefaultsKey.menuBarNativeBookmark
    static var expectedURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist")
    }
    @Published private(set) var hasAccess = false
    @Published private(set) var failed = false

    func refresh() {
        hasAccess = (try? read()) != nil
    }

    func request() {
        let panel = NSOpenPanel()
        let text = MenuBarNativeStrings.localized(L10n.shared.language)
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
        panel.directoryURL = Self.expectedURL.deletingLastPathComponent()
        panel.nameFieldStringValue = Self.expectedURL.lastPathComponent
        panel.prompt = text.grant; panel.message = text.accessInfo
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            self?.accept(url)
        }
    }

    private func accept(_ url: URL) {
        do {
            guard url.standardizedFileURL == Self.expectedURL.standardizedFileURL else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            _ = try document(at: url)
            let bookmark = try url.bookmarkData(options: .withSecurityScope,
                includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            hasAccess = true; failed = false
        } catch { hasAccess = false; failed = true }
    }

    func read() throws -> MenuBarNativeLayoutDocument {
        do {
            let result = try withAccess { try document(at: $0) }
            if !hasAccess { hasAccess = true }
            if failed { failed = false }
            return result
        } catch {
            if hasAccess { hasAccess = false }
            if !failed { failed = true }
            throw error
        }
    }

    @discardableResult
    func write(_ changes: [String: Double], basedOn snapshot: MenuBarNativeLayoutDocument) throws -> Data {
        guard !changes.isEmpty else { return snapshot.data }
        return try writeData(snapshot.replacing(changes), basedOn: snapshot)
    }

    @discardableResult
    func writeData(_ updated: Data, basedOn snapshot: MenuBarNativeLayoutDocument) throws -> Data {
        let replacement = try MenuBarNativeLayoutDocument(data: updated)
        return try withAccess { url in
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var writeError: Error?
            var written: Data?
            coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { target in
                do {
                    guard try document(at: target).data == snapshot.data else { throw CocoaError(.fileWriteUnknown) }
                    written = try MenuBarNativePreferenceStore.write(replacement, basedOn: snapshot, at: target)
                } catch { writeError = error }
            }
            if let coordinationError { throw coordinationError }
            if let writeError { throw writeError }
            guard let written else { throw CocoaError(.fileWriteUnknown) }
            return written
        }
    }

    func cacheMatches(_ document: MenuBarNativeLayoutDocument) throws -> Bool {
        try withAccess { MenuBarNativePreferenceStore.equal(try MenuBarNativePreferenceStore.read(at: $0), document.root) }
    }

    private func document(at url: URL) throws -> MenuBarNativeLayoutDocument {
        let resources = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard resources.isRegularFile == true, resources.isSymbolicLink != true,
              (resources.fileSize ?? Int.max) <= 2_097_152 else { throw CocoaError(.fileReadInvalidFileName) }
        return try MenuBarNativeLayoutDocument(data: Data(contentsOf: url))
    }

    private func withAccess<T>(_ action: (URL) throws -> T) throws -> T {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
            throw CocoaError(.fileReadNoPermission)
        }
        return try MenuBarBookmarkAccess.perform(bookmark: bookmark, expected: Self.expectedURL,
            renew: { UserDefaults.standard.set($0, forKey: Self.bookmarkKey) }, action: action)
    }
}
