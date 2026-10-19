// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import SwiftUI

/// Local addresses in the network menu, as iStat lists them. Read only while
/// shown; nothing leaves the machine, so there is no public IP lookup.
struct NetworkAddressCard: View {
    @ObservedObject private var l10n = L10n.shared
    @StateObject private var service = NetworkAddressService()

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(l10n.s.networkLocalIP).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text(service.localAddresses.isEmpty ? "-" : service.localAddresses.joined(separator: "\n"))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .panelCard()
        .onAppear { service.refreshLocalAddresses() }
        .onReceive(SystemMonitor.shared.$snapshot) { _ in service.refreshLocalAddresses() }
        .onDisappear { service.cancel() }
    }
}
