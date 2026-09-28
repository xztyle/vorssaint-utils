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

extension ClipboardHistoryService {
    // MARK: - Shortcut

    func syncHotkey() {
        let wanted = UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistoryEnabled)
            && UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistoryShortcutEnabled)
        wanted ? registerHotkey() : unregisterHotkey()
    }

    func registerHotkey() {
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.clipboardHistoryShortcut,
                                            fallback: .clipboardDefault)
        if hotKeyRef != nil, registeredShortcut == shortcut { return }
        unregisterHotkey()
        if hotKeyHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                if let event {
                    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &id)
                }
                guard id.signature == 0x5655_434C, id.id == 3
                else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<ClipboardHistoryService>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { service.toggleHistoryWindow() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        }
        let id = EventHotKeyID(signature: 0x5655_434C, id: 3) // 'VUCL'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.carbonKeyCode,
                                         shortcut.carbonModifiers,
                                         id, GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRef = ref
            registeredShortcut = shortcut
            shortcutRegistrationFailed = false
            SystemShortcutTakeover.claim(DefaultsKey.clipboardHistoryShortcut, shortcut: shortcut)
        } else {
            hotKeyRef = nil
            registeredShortcut = nil
            shortcutRegistrationFailed = true
        }
    }

    /// Lets go of the global key while a shortcut field is listening, so the
    /// user can record the very combination this feature uses. The next
    /// `syncWithPreferences` takes it back.
    func suspendShortcut() { unregisterHotkey() }

    func unregisterHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            SystemShortcutTakeover.release(DefaultsKey.clipboardHistoryShortcut)
        }
        hotKeyRef = nil
        registeredShortcut = nil
        shortcutRegistrationFailed = false
    }

    // MARK: - Quick window

    func toggleQuickPreview() {
        setQuickPreviewPresented(!quickPreviewPresented)
    }

    func setQuickPreviewPresented(_ presented: Bool) {
        guard presented != quickPreviewPresented else { return }
        quickPreviewPresented = presented
        DispatchQueue.main.async { ClipboardLibraryProbe.recordState() }
        if ClipboardLibraryProbe.root == nil { UserDefaults.standard.set(presented, forKey: DefaultsKey.clipboardHistoryQuickPreview) }
    }

    func toggleHistoryWindow() {
        drawerPresentation.isPresented ? hideHistoryWindow() : showHistoryWindow()
    }

    func showHistoryWindow(preferNotch: Bool = true) {
        let panel = ensurePanel()
        rememberPasteTarget()
        keyboardFocus = .search
        visibleShortcutIDs = []
        quickWindowPresentationID = UUID()
        quickQuery = ""
        clearQuickBatchSelection()
        resetQuickSelection()
        _ = drawerPresentation.request(true)
        position(panel)
        installKeyMonitor(for: panel)
        installDismissMonitors(for: panel)
        panel.reveal(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        panel.makeKey()
    }

    func hideHistoryWindow() {
        guard drawerPresentation.isPresented else { return }
        let token = drawerPresentation.request(false)
        removeKeyMonitor()
        removeDismissMonitors()
        panel?.dismiss(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) { [weak self] in
            guard let self, self.drawerPresentation.accepts(token, presented: false) else { return }
            self.panel?.orderOut(nil)
            ClipboardLibraryProbe.recordState()
        }
        clearQuickBatchSelection()
    }

    func rememberPasteTarget() {
        guard ClipboardLibraryProbe.root == nil else { pasteTargetApp = nil; return }
        let ownBundleID = Bundle.main.bundleIdentifier
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != ownBundleID,
              app.activationPolicy == .regular,
              !app.isTerminated
        else {
            pasteTargetApp = nil
            return
        }
        pasteTargetApp = app
    }

    /// The entry is already on the clipboard, so a paste that cannot follow
    /// says so the way Paste as Plain Text does (#186) instead of doing nothing.
    /// No target means the window opened over Vorssaint itself or an app
    /// without a Dock icon, where a pick is only a copy and stays silent.
    func pasteIntoPreviousApp(_ app: NSRunningApplication?) {
        guard ClipboardLibraryProbe.root == nil else { return }
        guard let app else { return }
        guard !app.isTerminated else {
            NSSound.beep()
            return
        }
        app.activate(options: [])
        guard AXIsProcessTrusted() else {
            if promptedForAccessibility {
                NSSound.beep()
            } else {
                promptedForAccessibility = true
                Permissions.shared.requestAccessibility()
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard !app.isTerminated,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                NSSound.beep()
                return
            }
            Self.postPasteShortcut()
        }
    }

    static func postPasteShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source,
                                    virtualKey: CGKeyCode(kVK_ANSI_V),
                                    keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source,
                                  virtualKey: CGKeyCode(kVK_ANSI_V),
                                  keyDown: false)
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    func ensurePanel() -> ClipboardDrawerPanel {
        if let panel { return panel }
        let panel = ClipboardDrawerPanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = FeatureStrings.clipboard(L10n.shared.language).title
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        drawerScreenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.drawerPresentation.isPresented else { return }
            self.position(panel)
        }
        self.panel = panel
        return panel
    }

    func position(_ panel: ClipboardDrawerPanel) {
        let screen = NSScreen.withMouse ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        panel.place(on: screen.frame)
    }

    func installKeyMonitor(for panel: NSPanel) {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel, panel.attachedSheet == nil else { return event }
            if let textView = panel.firstResponder as? NSTextView,
               ClipboardHistoryFocus.textViewOwnsKeys(isComposing: textView.hasMarkedText(),
                   isFieldEditor: textView.isFieldEditor, isEditable: textView.isEditable) { return event }
            return self.handleLibraryKey(event) ? nil : event
        }
    }

    func handleLibraryKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if modifiers == [.command], handleCommandKey(key) { return true }
        if event.keyCode == UInt16(kVK_Escape) { escapeLibrary(); return true }
        if event.keyCode == UInt16(kVK_Tab) {
            keyboardFocus = keyboardFocus.next(reverse: modifiers.contains(.shift))
            quickSelectionIsVisible = keyboardFocus == .results
            if keyboardFocus == .search { searchFocusRequest = UUID() }
            if keyboardFocus == .collections { collectionFocusRequest = UUID() }
            return true
        }
        if event.keyCode == UInt16(kVK_Space), quickSelectionIsVisible, modifiers.isEmpty {
            fullPreviewRequest = UUID(); return true
        }
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            return handleLibraryReturn(modifiers)
        }
        if handleLibraryArrows(event.keyCode, modifiers: modifiers) { return true }
        if modifiers == [.option], key == "p" { togglePinSelectedQuickEntry(); return true }
        if modifiers == [.command], event.keyCode == UInt16(kVK_Delete), quickSelectionIsVisible {
            removeSelectedQuickEntries(); return true
        }
        if keyboardFocus == .results, modifiers.isEmpty, let chars = event.characters, chars.unicodeScalars.allSatisfy({ !$0.properties.isWhitespace && $0.value >= 32 && $0.value < 0xF700 }) {
            keyboardFocus = .search; quickQuery += chars; searchFocusRequest = UUID(); return true
        }
        return false
    }

    func handleCommandKey(_ key: String) -> Bool {
        switch key {
        case "f": keyboardFocus = .search; quickSelectionIsVisible = false; searchFocusRequest = UUID()
        case "e" where quickSelectionIsVisible: editRequest = UUID()
        case "r" where quickSelectionIsVisible: renameRequest = UUID()
        case "c" where quickSelectionIsVisible || quickBatchCount > 0: copySelectedQuickEntryOnly()
        case "a" where quickSelectionIsVisible: selectAllQuickEntries()
        default:
            guard let number = Int(key), (1...9).contains(number) else { return false }
            copyQuickEntry(at: number - 1)
        }
        return true
    }

    func handleLibraryReturn(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        if !quickSelectionIsVisible { keyboardFocus = .results; moveQuickSelection(0); return true }
        if modifiers == [.shift], let entry = selectedQuickEntry { pastePlain(entry); return true }
        if modifiers == [.command] { toggleSelectedQuickEntryBatchSelection(); return true }
        if modifiers.isEmpty { copySelectedQuickEntry(); return true }
        return false
    }

    func handleLibraryArrows(_ code: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let forward = code == UInt16(kVK_RightArrow) || code == UInt16(kVK_DownArrow)
        let backward = code == UInt16(kVK_LeftArrow) || code == UInt16(kVK_UpArrow)
        guard forward || backward else { return false }
        if keyboardFocus == .collections {
            let ids: [UUID?] = [nil] + collections.map { Optional($0.id) }
            let index = ids.firstIndex(of: selectedCollectionID) ?? 0
            selectedCollectionID = ids[min(max(index + (forward ? 1 : -1), 0), ids.count - 1)]
            return true
        }
        // Horizontal arrows still edit a search query until results own focus.
        if !quickSelectionIsVisible, code == UInt16(kVK_LeftArrow) || code == UInt16(kVK_RightArrow) { return false }
        let old = selectedQuickEntry
        let delta = modifiers.contains(.command) ? (forward ? quickResults.count : -quickResults.count) : (forward ? 1 : -1)
        keyboardFocus = .results
        moveQuickSelection(delta)
        if modifiers.contains(.shift), let old, let next = selectedQuickEntry {
            quickBatchEntryIDs.formUnion([old.id, next.id])
        }
        return true
    }

    func escapeLibrary() {
        if quickBatchCount > 0 { clearQuickBatchSelection() }
        else if quickPreviewPresented { setQuickPreviewPresented(false) }
        else if !quickQuery.isEmpty { quickQuery = ""; searchFocusRequest = UUID() }
        else { hideHistoryWindow() }
    }

    func pastePlain(_ entry: ClipboardHistoryEntry) {
        guard entry.kind == .text else { NSSound.beep(); return }
        var plain = entry
        plain.representations = [:]
        copyQuickEntry(plain)
    }

    func installDismissMonitors(for panel: NSPanel) {
        removeDismissMonitors()
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, panel.attachedSheet == nil else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) {
                self.hideHistoryWindow()
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, panel.attachedSheet == nil else { return }
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel),
               // Every key on the Accessibility Keyboard is a click outside this
               // panel. Dismissing on those makes the panel impossible to type into.
               !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) {
                self.hideHistoryWindow()
            }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier,
                  app.bundleIdentifier != AssistiveKeyboard.bundleID
            else { return }
            self.hideHistoryWindow()
        }
    }

    static func mouseIsInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    func removeDismissMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    func resetQuickSelection() {
        quickSelectionIndex = ClipboardHistorySelection.initialIndex(totalCount: filteredQuickEntries.count)
        quickSelectionIsVisible = false
    }

    var quickBatchEntries: [ClipboardHistoryEntry] {
        let allIDs = entries.map(\.id)
        let indexes = ClipboardHistoryBatch.orderedSelectedIndexes(allIDs: allIDs,
                                                                  selectedIDs: quickBatchEntryIDs)
        return indexes.map { entries[$0] }
    }

    func quickEntriesForPrimaryAction() -> [ClipboardHistoryEntry] {
        let batch = quickBatchEntries
        if !batch.isEmpty { return batch }
        guard let entry = selectedQuickEntry else { return [] }
        return [entry]
    }

    func pruneQuickBatchSelection() {
        let validIDs = Set(entries.map(\.id))
        quickBatchEntryIDs = Set(quickBatchEntryIDs.filter { validIDs.contains($0) })
    }

    static func digitIndex(for keyCode: UInt16) -> Int? {
        switch Int(keyCode) {
        case kVK_ANSI_1: return 0
        case kVK_ANSI_2: return 1
        case kVK_ANSI_3: return 2
        case kVK_ANSI_4: return 3
        case kVK_ANSI_5: return 4
        case kVK_ANSI_6: return 5
        case kVK_ANSI_7: return 6
        case kVK_ANSI_8: return 7
        case kVK_ANSI_9: return 8
        default: return nil
        }
    }

    func clampedQuickSelectionIndex(for count: Int) -> Int {
        min(max(quickSelectionIndex, 0), max(count - 1, 0))
    }
}
