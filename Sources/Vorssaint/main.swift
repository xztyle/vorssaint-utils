// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

MenuBarAXDiagnosticProbe.runIfRequested()

if CommandLine.arguments.contains("--menu-bar-inventory") {
    MenuBarInventoryProbe.runAndExit()
}

SuperKeyMappingGuard.runIfRequestedAndExit()
Defaults.register()
MouseAccelerationGuard.runIfRequestedAndExit()
MouseAccelerationService.recoverPendingAtLaunch()

#if VORSSAINT_DEVELOPMENT
if CommandLine.arguments.contains("--notch-presentation-test") {
    NotchPresentationProbe.runAndExit()
}
#endif

if CommandLine.arguments.contains("--selftest") {
    SelfTest.runAndExit()
}
if CommandLine.arguments.contains("--sensors") {
    SensorDump.runAndExit()
}
if CommandLine.arguments.contains("--uninstall") {
    Uninstaller.runAndExit()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
