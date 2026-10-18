// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import AppKit

@MainActor
extension MenuBarOrganizerService {
    var usesNativeBackend: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 }
    var layoutPreferenceKey: String { MenuBarBackendPreferences.layout }
    var baselinePreferenceKey: String { MenuBarBackendPreferences.baseline }
    var setupPreferenceKey: String { MenuBarBackendPreferences.setup }
    var organizerAnchor: CGRect? { usesNativeBackend ? nativeBackend.controlFrame : controlItem?.frame }

    func inventorySnapshot() async -> MenuBarItemSnapshot {
        if usesNativeBackend { return await nativeBackend.snapshot() }
        let excluded = Set([controlItem?.windowID, hiddenDivider?.windowID, alwaysHiddenDivider?.windowID].compactMap { $0 })
        return await provider.snapshot(hiddenDividerMidX: hiddenDivider?.frame?.midX,
            alwaysHiddenDividerMidX: alwaysHiddenDivider?.frame?.midX, excludedWindowIDs: excluded)
    }

    func prepareNativeBackend() async -> Bool {
        guard usesNativeBackend else { return true }
        // Validate the original physical baseline before applying the saved
        // logical sections. A saved hidden item is not failed quit recovery.
        nativeBackend.prepareForStartup()
        if nativeBackend.layout.recoveryNeeded, controlItem == nil { createControls() }
        nativeBackend.layout.requestRefresh = { [weak self] in self?.controlItem?.requestNativeRefresh() }
        do { return try await nativeBackend.layout.recover() }
        catch { recoveryNeeded = true; automationPaused = true; operationMessage = extra.restoreFailed; return false }
    }

    func moveNativeItem(_ identity: MenuBarItemIdentity, before target: MenuBarItemIdentity?,
                        to section: MenuBarOrganizerSection) async -> Bool {
        do {
            try await nativeBackend.move(identity, before: target, to: section)
            guard await settleAndRefresh(), items.first(where: { $0.id == identity })?.section == section else {
                throw MenuBarItemMoveError.verificationFailed
            }
            operationMessage = nil; return true
        } catch {
            recoveryNeeded = nativeBackend.layout.recoveryNeeded
            if recoveryNeeded { automationPaused = true }
            operationMessage = moveErrorMessage(error); return false
        }
    }

    func applyNativeVisibility() {
        nativeBackend.applyVisibility(hiddenShown: hiddenSectionShown, alwaysShown: alwaysHiddenSectionShown,
            editing: editingCount > 0, items: items) { [weak self] in
                guard let self else { return }
                hiddenSectionShown = true; alwaysHiddenSectionShown = true
                automationPaused = true; operationMessage = text.errorVerification
            }
    }

    func clickItem(_ item: ManagedMenuBarItem) async throws {
        if usesNativeBackend { try await MenuBarNativePress.press(item) }
        else { try await mover.click(item: item) }
    }
}
