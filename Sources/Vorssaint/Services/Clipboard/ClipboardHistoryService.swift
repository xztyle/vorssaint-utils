// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftUI

enum ClipboardHistoryMoveDirection {
    case up
    case down
}

/// Opt-in clipboard history. It records plain text and, optionally, copied
/// images and files; keeps a small local history and avoids obvious
/// secret-looking strings by default.
final class ClipboardHistoryService: ObservableObject {
    static let shared = ClipboardHistoryService()

    @Published var entries: [ClipboardHistoryEntry] = [] {
        didSet {
            entriesStamp &+= 1
            // Dropped rather than left to go stale, so clearing the history
            // does not keep a folded copy of its text around.
            foldedCandidateCache = nil
            scheduleSearch()
            // Keeps latestPasteboardEntry from outliving the entry it points
            // to: removing it, clearing recent/all, or trimming to a smaller
            // limit must stop the preview from claiming stale content is
            // still the latest copy. Editing history does not rewrite the
            // pasteboard, so only unchanged content may keep its preview.
            if let current = latestPasteboardEntry {
                latestPasteboardEntry = entries.first {
                    $0.id == current.id && $0.text == current.text
                }
            }
        }
    }
    /// The entry most recently put on the system pasteboard, whether from a
    /// fresh external copy or from reusing an existing entry. `touch()`
    /// deliberately leaves `entries`' own order alone when reusing one, so
    /// this is what the optional "show latest copy" menu bar item follows
    /// instead of `entries.first` (which is also wrong on its own whenever
    /// anything is pinned, since pinned entries always sort first there).
    @Published var latestPasteboardEntry: ClipboardHistoryEntry?
    let capturedEntry = PassthroughSubject<ClipboardHistoryEntry, Never>()
    @Published var isRunning = false
    @Published var shortcutRegistrationFailed = false
    @Published var quickBatchEntryIDs: Set<UUID> = []
    @Published var quickQuery = "" {
        didSet {
            if quickQuery != oldValue {
                quickResults = []
                resetQuickSelection()
                scheduleSearch()
            }
        }
    }
    @Published var visibleShortcutIDs: [UUID] = []
    @Published var keyboardFocus: ClipboardLibraryFocus = .search
    @Published var collectionFocusRequest = UUID()
    @Published var quickSelectionIndex = 0
    @Published var quickSelectionIsVisible = false
    @Published var quickWindowPresentationID = UUID()
    @Published var quickPreviewPresented = UserDefaults.standard.bool(
        forKey: DefaultsKey.clipboardHistoryQuickPreview
    )

    @Published var collections: [ClipboardCollection] = []
    @Published var selectedCollectionID: UUID? { didSet { resetQuickSelection(); scheduleSearch() } }
    @Published var quickResults: [ClipboardHistoryEntry] = []
    @Published var storageError: String?
    @Published var libraryReady = false
    @Published var isSaving = false
    @Published var pausedUntil: Date? = UserDefaults.standard.object(forKey: "clipboardCapturePausedUntil")
        .flatMap { $0 as? Double }.map { Date(timeIntervalSince1970: $0) }
    @Published var migrationCount = 0
    @Published var searchFocusRequest = UUID()
    @Published var editRequest = UUID()
    @Published var renameRequest = UUID()
    @Published var fullPreviewRequest = UUID()
    var library: ClipboardLibraryStore?
    var searchGeneration = 0
    var searchScheduled = false
    var pauseIsActive: Bool { pausedUntil.map { $0 > Date() } ?? false }

    static let ocrQueue = DispatchQueue(label: "aster.clipboard-ocr", qos: .utility)
    var timer: Timer?
    var lastChangeCount = 0
    /// The poll reads the pasteboard off the main thread: while a password
    /// prompt is up the pasteboard server can take seconds to answer, and a
    /// blocked main thread stalls every event tap with it, so typing freezes
    /// system wide (issue #189). The shared access lane also keeps the URL
    /// cleaner from touching AppKit's mutable pasteboard cache concurrently.
    var captureState = ClipboardHistoryCaptureState()
    /// Keep at most one history write queued or executing, even after its
    /// caller timed out. A blocked provider cannot accumulate user actions.
    var copyInFlight = false
    static let pasteboardTimeout: TimeInterval = 5
    var panel: ClipboardDrawerPanel?
    var drawerPresentation = ClipboardDrawerPresentation()
    var drawerScreenObserver: NSObjectProtocol?
    var keyMonitor: Any?
    var localClickMonitor: Any?
    var outsideClickMonitor: Any?
    var activationObserver: NSObjectProtocol?
    var hotKeyRef: EventHotKeyRef?
    var hotKeyHandler: EventHandlerRef?
    var registeredShortcut: GlobalShortcut?
    var pasteTargetApp: NSRunningApplication?
    var promptedForAccessibility = false
    /// Writes coalesce per mutation cycle; the JSON encode and the disk write
    /// stay off the main thread (a full history of long texts is real work),
    /// serialized so blobs land in mutation order.
    static let persistQueue = DispatchQueue(label: "io.github.xztyle.Aster.clipboard-persist",
                                                    qos: .utility)
    var persistScheduled = false
    var persistenceGeneration = 0
    /// True while the history still lives in the legacy UserDefaults blob;
    /// only a store-file write that really landed retires that blob, so a
    /// crash mid-migration never loses entries.

    init() {
        load()
    }

    func syncWithPreferences() {
        if AppFeature.clipboardHistory.isAvailable,
           UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistoryEnabled) {
            start()
            syncHotkey()
        } else {
            stop()
            unregisterHotkey()
        }
    }

    /// Skips capturing pasteboard changes up to the given change count. Quick
    /// tools that rewrite the pasteboard transiently (paste as plain text)
    /// use this so their intermediate writes never churn the history.
    func ignoreNextChange(upTo changeCount: Int) {
        lastChangeCount = max(lastChangeCount, changeCount)
    }

    /// ClipboardAutoClearService calls this after it actually empties the
    /// system pasteboard, so the menu bar preview stops showing content that
    /// is no longer there. Deliberately separate from ignoreNextChange:
    /// a transient rewrite-then-restore (paste as plain text) also calls
    /// that, but the pasteboard's real content never changed there, so the
    /// preview must not clear in that case.
    func pasteboardWasCleared() {
        latestPasteboardEntry = nil
    }

    func togglePin(_ entry: ClipboardHistoryEntry) {
        if entry.isPinned { removeFromCollections(entry) }
        else { addToCollection(entry, id: ensureDefaultCollection()) }
    }

    func remove(_ entry: ClipboardHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        for board in collections.indices { collections[board].entryIDs.removeAll { $0 == entry.id } }
        var selected = quickBatchEntryIDs
        selected.remove(entry.id)
        quickBatchEntryIDs = selected
        save()
    }

    @discardableResult
    func updateText(_ entry: ClipboardHistoryEntry, to draft: String) -> Bool {
        guard entry.kind == .text, let text = ClipboardHistoryEditing.storableText(draft),
              let index = entries.firstIndex(where: { $0.id == entry.id }) else { return false }
        guard entries[index].text != text else { return true }
        // Editing creates a new clip, retaining the exact original in history.
        var edited = ClipboardHistoryEntry(text: text)
        edited.title = entry.title
        edited.collectionIDs = entry.collectionIDs
        edited.pinnedAt = entry.pinnedAt
        entries.insert(edited, at: 0)
        for position in collections.indices where collections[position].entryIDs.contains(entry.id) {
            collections[position].entryIDs.insert(edited.id, at: 0)
        }
        save()
        return true
    }

    func clearRecent() {
        entries.removeAll { !$0.isPinned }
        pruneQuickBatchSelection()
        save()
    }

    func clearAll() {
        clearRecent()
    }

    func canMove(_ entry: ClipboardHistoryEntry, _ direction: ClipboardHistoryMoveDirection) -> Bool {
        moveDestination(for: entry, direction) != nil
    }

    func move(_ entry: ClipboardHistoryEntry, _ direction: ClipboardHistoryMoveDirection) {
        guard let from = entries.firstIndex(where: { $0.id == entry.id }),
              let to = moveDestination(for: entry, direction)
        else { return }
        entries.swapAt(from, to)
        save()
    }

    var pinnedEntries: [ClipboardHistoryEntry] {
        entries.filter(\.isPinned)
    }

    var recentEntries: [ClipboardHistoryEntry] {
        entries.filter { !$0.isPinned }
    }

    var filteredQuickEntries: [ClipboardHistoryEntry] {
        quickResults
    }

    var selectedQuickEntryID: UUID? {
        selectedQuickEntry?.id
    }

    var quickBatchCount: Int {
        quickBatchEntries.count
    }

    var selectedQuickEntry: ClipboardHistoryEntry? {
        let matches = filteredQuickEntries
        guard !matches.isEmpty else { return nil }
        return matches[clampedQuickSelectionIndex(for: matches.count)]
    }

    func isQuickBatchSelected(_ entry: ClipboardHistoryEntry) -> Bool {
        quickBatchEntryIDs.contains(entry.id)
    }

    func toggleQuickBatchSelection(_ entry: ClipboardHistoryEntry) {
        if let index = filteredQuickEntries.firstIndex(where: { $0.id == entry.id }) {
            quickSelectionIndex = index
        }
        var selected = quickBatchEntryIDs
        if selected.contains(entry.id) {
            selected.remove(entry.id)
        } else {
            selected.insert(entry.id)
        }
        quickBatchEntryIDs = selected
    }

    /// Finder-style shift-click: selects everything between the last row the
    /// user touched and the clicked one.
    func extendQuickBatchSelection(to entry: ClipboardHistoryEntry) {
        let matches = filteredQuickEntries
        guard let target = matches.firstIndex(where: { $0.id == entry.id }) else { return }
        let anchor = clampedQuickSelectionIndex(for: matches.count)
        let ids = ClipboardHistoryBatch.rangeSelectionIDs(allIDs: matches.map(\.id),
                                                          anchor: anchor,
                                                          target: target)
        quickBatchEntryIDs = quickBatchEntryIDs.union(ids)
        quickSelectionIndex = target
        quickSelectionIsVisible = true
    }

    /// Selects every visible result, so "search, select all, copy" works.
    func selectAllQuickEntries() {
        let visible = filteredQuickEntries.map(\.id)
        guard !visible.isEmpty else { return }
        quickBatchEntryIDs = quickBatchEntryIDs.union(visible)
    }

    func toggleSelectedQuickEntryBatchSelection() {
        guard let entry = selectedQuickEntry else { return }
        toggleQuickBatchSelection(entry)
    }

    func clearQuickBatchSelection() {
        quickBatchEntryIDs = []
    }

    /// Bumped by the `entries` didSet; lets the search cache below notice any
    /// mutation without every mutating site having to remember it.
    var entriesStamp = 0
    var filterCache: (query: String, stamp: Int, imageLabel: String,
                              result: [ClipboardHistoryEntry])?

    func filteredEntries(matching query: String) -> [ClipboardHistoryEntry] {
        // One ranking pass over a large history of long texts costs real
        // time, and SwiftUI asks for the filtered list many times per
        // render. The last result is reused until the query, the language
        // or the history itself changes.
        let imageLabel = FeatureStrings.clipboard(L10n.shared.language).imageEntryLabel
        if let cache = filterCache, cache.query == query,
           cache.stamp == entriesStamp, cache.imageLabel == imageLabel {
            return cache.result
        }
        let result: [ClipboardHistoryEntry]
        if let indexed = indexedEntries(matching: query) {
            result = indexed
        } else if ClipboardHistorySearch.hasSearchTerms(query) {
            result = ClipboardHistorySearch.rankedIndexes(candidates: foldedCandidates(imageLabel: imageLabel),
                                                          matching: query,
                                                          textIsNormalized: true)
                .map { entries[$0] }
        } else {
            result = entries
        }
        filterCache = (query, entriesStamp, imageLabel, result)
        return result
    }

    func indexedEntries(matching query: String) -> [ClipboardHistoryEntry]? {
        guard ClipboardHistorySearch.hasSearchTerms(query), let library else { return nil }
        let ids = Self.persistQueue.sync { try? library.search(query) }
        guard let ids else { return nil }
        let lookup = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        return ids.compactMap { lookup[$0] }
    }

    var foldedCandidateCache: (imageLabel: String, candidates: [ClipboardHistorySearchCandidate])?

    /// The query changes on every keystroke, so the result cache above never
    /// hits while typing; folding every entry's full text again each time is
    /// what made the Command Bar lag with a large history (#1885). The folded
    /// text only changes with the history or the language.
    func foldedCandidates(imageLabel: String) -> [ClipboardHistorySearchCandidate] {
        if let cache = foldedCandidateCache, cache.imageLabel == imageLabel {
            return cache.candidates
        }
        let candidates = entries.enumerated().map { index, entry in
            ClipboardHistorySearchCandidate(
                index: index,
                text: ClipboardHistorySearch.normalized(entry.searchableText(imageLabel: imageLabel)),
                isPinned: entry.isPinned)
        }
        foldedCandidateCache = (imageLabel, candidates)
        return candidates
    }

    func copyQuickEntry(at index: Int) {
        let ids = visibleShortcutIDs.isEmpty ? Array(filteredQuickEntries.prefix(9).map(\.id)) : visibleShortcutIDs
        guard ids.indices.contains(index), let entry = filteredQuickEntries.first(where: { $0.id == ids[index] }) else { return }
        copyQuickEntry(entry)
    }

    func copySelectedQuickEntry() {
        let selectedEntries = quickEntriesForPrimaryAction()
        guard !selectedEntries.isEmpty else { return }
        if selectedEntries.count == 1 {
            copyQuickEntry(selectedEntries[0])
        } else {
            copyQuickEntries(selectedEntries)
        }
    }

    func copySelectedQuickEntryOnly() {
        let selectedEntries = quickEntriesForPrimaryAction()
        guard !selectedEntries.isEmpty else { return }
        if selectedEntries.count == 1 {
            copyOnlyQuickEntry(selectedEntries[0])
        } else {
            copyOnlyQuickEntries(selectedEntries)
        }
    }

    func togglePinSelectedQuickEntry() {
        guard let entry = selectedQuickEntry else { return }
        togglePin(entry)
        quickSelectionIndex = clampedQuickSelectionIndex(for: filteredQuickEntries.count)
    }

    func removeSelectedQuickEntries() {
        let selectedEntries = quickEntriesForPrimaryAction()
        guard !selectedEntries.isEmpty else { return }
        let idsToRemove = Set(selectedEntries.map(\.id))
        entries.removeAll { idsToRemove.contains($0.id) }
        for board in collections.indices { collections[board].entryIDs.removeAll { idsToRemove.contains($0) } }
        var selected = quickBatchEntryIDs
        selected.subtract(idsToRemove)
        quickBatchEntryIDs = selected
        quickSelectionIndex = clampedQuickSelectionIndex(for: filteredQuickEntries.count)
        save()
    }

    /// Where the pointer sat when the keyboard last moved the selection. Rows
    /// scrolling under a still pointer report hover, and hover would otherwise
    /// take the preview back from the row the arrow keys chose.
    var keyboardSelectionPointer: NSPoint?

    func moveQuickSelection(_ delta: Int) {
        // Out of the way while the keys drive, back at the first real move.
        NSCursor.setHiddenUntilMouseMoves(true)
        keyboardSelectionPointer = NSEvent.mouseLocation
        let count = filteredQuickEntries.count
        guard count > 0 else {
            quickSelectionIndex = 0
            quickSelectionIsVisible = false
            return
        }
        if !quickSelectionIsVisible {
            quickSelectionIndex = clampedQuickSelectionIndex(for: count)
            quickSelectionIsVisible = true
            return
        }
        quickSelectionIndex = min(max(quickSelectionIndex + delta, 0), count - 1)
    }

    /// The window leaves the screen at once; the paste waits for the write,
    /// because pasting before it lands would paste whatever the user had
    /// copied before. A stale entry leaves the clipboard untouched and pastes
    /// nothing at all.
    func copyQuickEntry(_ entry: ClipboardHistoryEntry) {
        let target = pasteTargetApp
        hideHistoryWindow()
        pasteTargetApp = nil
        copy(entry) { [weak self] copied in
            guard copied else {
                NSSound.beep()
                return
            }
            self?.pasteIntoPreviousApp(target)
        }
    }

    func copyQuickEntries(_ selectedEntries: [ClipboardHistoryEntry]) {
        let target = pasteTargetApp
        hideHistoryWindow()
        pasteTargetApp = nil
        copy(selectedEntries) { [weak self] copied in
            guard copied else {
                NSSound.beep()
                return
            }
            self?.pasteIntoPreviousApp(target)
        }
    }

    func editImage(_ entry: ClipboardHistoryEntry) {
        guard entry.kind == .image, AppFeature.screenshot.isAvailable,
              let directory = ClipboardImageStore.directory else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let capture = autoreleasepool {
                ClipboardHistoryImageSupport.editorImage(for: entry, directory: directory)
                    .flatMap { ScreenshotService.imageCapture(from: $0) }
            }
            DispatchQueue.main.async {
                guard AppFeature.screenshot.isAvailable else { return }
                guard let capture else {
                    NSSound.beep()
                    return
                }
                self.hideHistoryWindow()
                (NSApp.delegate as? AppDelegate)?.closePopover()
                NotchService.shared.perform {
                    ScreenshotService.shared.openEditor(with: capture)
                }
            }
        }
    }

    /// No paste follows these two, so nothing has to wait for the write: the
    /// window closes now and a stale entry simply leaves the clipboard as the
    /// user left it.
    func copyOnlyQuickEntry(_ entry: ClipboardHistoryEntry) {
        copy(entry) { if !$0 { NSSound.beep() } }
        hideHistoryWindow()
        pasteTargetApp = nil
    }

    func copyOnlyQuickEntries(_ selectedEntries: [ClipboardHistoryEntry]) {
        copy(selectedEntries) { if !$0 { NSSound.beep() } }
        hideHistoryWindow()
        pasteTargetApp = nil
    }

    func trimToLimit() {
        // Count limits from the old small-history feature never delete an upgrade.
        let days = UserDefaults.standard.integer(forKey: DefaultsKey.clipboardRetentionDays)
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let expired = entries.filter { !$0.isPinned && $0.copiedAt < cutoff }
        guard !expired.isEmpty else { return }
        let ids = Set(expired.map(\.id))
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    /// The saved file drops whatever it cannot hold, pinned items included, so
    /// a pin or an edit that would push them past it is refused instead.
    var encodedHistoryByteLimit: Int { ClipboardHistoryEditing.maxEncodedHistoryBytes }

    var firstRecentIndex: Int {
        entries.firstIndex { !$0.isPinned } ?? entries.endIndex
    }

    func insertPromoted(_ entry: ClipboardHistoryEntry) {
        if entry.isPinned {
            entries.insert(entry, at: 0)
        } else {
            entries.insert(entry, at: firstRecentIndex)
        }
        latestPasteboardEntry = entry
        capturedEntry.send(entry)
    }

    func normalizeEntryOrder() {
        let pinned = entries.filter(\.isPinned)
        let recent = entries.filter { !$0.isPinned }
        entries = pinned + recent
    }

    func moveDestination(for entry: ClipboardHistoryEntry,
                                 _ direction: ClipboardHistoryMoveDirection) -> Int? {
        let groupIndices = entries.indices.filter { entries[$0].isPinned == entry.isPinned }
        guard let groupPosition = groupIndices.firstIndex(where: { entries[$0].id == entry.id }) else {
            return nil
        }
        switch direction {
        case .up:
            guard groupPosition > groupIndices.startIndex else { return nil }
            return groupIndices[groupIndices.index(before: groupPosition)]
        case .down:
            let next = groupIndices.index(after: groupPosition)
            guard next < groupIndices.endIndex else { return nil }
            return groupIndices[next]
        }
    }

    func looksSensitive(_ text: String) -> Bool {
        ClipboardHistorySensitiveText.looksSensitive(text)
    }

}
