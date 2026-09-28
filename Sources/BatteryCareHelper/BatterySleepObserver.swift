// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation
import IOKit
import IOKit.pwr_mgt

final class BatterySleepObserver {
    private let controller: BatteryController
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var connection: io_connect_t = 0

    init(controller: BatteryController) {
        self.controller = controller
        let context = Unmanaged.passUnretained(self).toOpaque()
        connection = IORegisterForSystemPower(context, &port, { context, _, message, argument in
            guard let context else { return }
            Unmanaged<BatterySleepObserver>.fromOpaque(context).takeUnretainedValue()
                .receive(message, argument: argument)
        }, &notifier)
        if let port, let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    var isRegistered: Bool { connection != 0 }

    private func receive(_ message: UInt32, argument: UnsafeMutableRawPointer?) {
        switch message {
        case 0xe0000270: // kIOMessageCanSystemSleep (IOMessage.h)
            IOAllowPowerChange(connection, Int(bitPattern: argument))
        case 0xe0000280: // kIOMessageSystemWillSleep
            controller.powerChange(sleep: true)
            IOAllowPowerChange(connection, Int(bitPattern: argument))
        case 0xe0000300: // kIOMessageSystemHasPoweredOn
            controller.powerChange(sleep: false)
        default: break
        }
    }

    deinit {
        if notifier != 0 { IODeregisterForSystemPower(&notifier) }
        if connection != 0 { IOServiceClose(connection) }
        if let port { IONotificationPortDestroy(port) }
    }
}
