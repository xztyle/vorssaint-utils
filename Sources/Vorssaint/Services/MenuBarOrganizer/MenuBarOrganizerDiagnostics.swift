// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit

@MainActor
extension MenuBarOrganizerService {
    func restoreAndDisable() {
        UserDefaults.standard.set(false, forKey: DefaultsKey.menuBarOrganizerEnabled)
        stop()
    }

    func copyDiagnostics() {
        let facts: [String: Any] = [
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "supported": AppFeature.menuBarOrganizer.isSupportedOnCurrentSystem,
            "accessibility": AXIsProcessTrusted(), "running": isRunning,
            "enumeration": capabilities.canEnumerate, "privateWindowList": capabilities.hasPrivateWindowList,
            "unresolved": capabilities.unresolvedItemCount, "recoveryNeeded": recoveryNeeded,
            "automationPaused": automationPaused, "displayCount": NSScreen.screens.count,
            "sections": Dictionary(grouping: items, by: { $0.section.rawValue }).mapValues(\.count),
            "stableItems": items.filter { $0.identityState == .stable }.count,
            "conflicts": conflictingManagers.map(\.name), "profiles": library.profiles.count,
            "rules": library.rules.count, "lastError": operationMessage ?? "",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
