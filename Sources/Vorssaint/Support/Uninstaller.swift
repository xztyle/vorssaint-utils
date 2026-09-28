// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation
import ServiceManagement

/// `Aster --uninstall` restores hardware before a removal script can delete the
/// bundle. Run from the installed bundle so SMAppService sees the correct app.
enum Uninstaller {
    static func runAndExit() -> Never {
        if let baseline = UserDefaults.standard.data(forKey: "menuBarOrganizerBaseline"), !baseline.isEmpty {
            print("UNINSTALL: restore the original menu layout in Aster before removal")
            exit(EXIT_FAILURE)
        }
        guard BatteryCareService.detachForRemoval() else {
            print("UNINSTALL: battery restoration pending; keep Aster installed")
            exit(EXIT_FAILURE)
        }
        let detached = FanControlService.restoreAndUnregisterForRemoval()
        print(detached
              ? "UNINSTALL: fan helper daemon unregistered"
              : "UNINSTALL: fan helper daemon still registered")
        restoreSleep()
        detachLoginItem()
        exit(detached ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    private static func restoreSleep() {
        // There is no NSApplication yet, so this path cannot show a password
        // prompt. The script verifies the setting and keeps the app on failure.
        guard UserDefaults.standard.bool(forKey: DefaultsKey.sleepDisabledFlag) else { return }
        let probe = Shell.run("/usr/bin/pmset", ["-g"])
        let restored = Sudoers.pmsetDisableSleep(false)
            || (probe.status == 0 && !SudoersSupport.sleepDisabled(inPmsetOutput: probe.output))
        print(restored
              ? "UNINSTALL: normal sleep restored"
              : "UNINSTALL: sleep is still disabled")
    }

    private static func detachLoginItem() {
        do {
            try SMAppService.mainApp.unregister()
            print("UNINSTALL: login item unregistered")
        } catch {
            print("UNINSTALL: login item was not registered")
        }
    }
}
