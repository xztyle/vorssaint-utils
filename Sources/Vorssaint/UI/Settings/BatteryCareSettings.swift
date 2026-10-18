// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import SwiftUI

struct BatteryCareSettings: View {
    @ObservedObject private var service = BatteryCareService.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @State private var policy = BatteryCarePolicy()
    @State private var dischargeTarget = 50
    @State private var hasLoadedDaemonPolicy = false
    @State private var lastDaemonPolicy = BatteryCarePolicy()
    private var text: BatteryCareStrings { FeatureStrings.batteryCare(l10n.language) }
    private var snapshot: BatteryCareSnapshot { service.snapshot }
    private var systemRestricted: Bool { BatteryControlCompatibility.isRestricted(snapshot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusCard
            SettingsCard { PowerFlowView(reading: monitor.snapshot.power, compact: false) }
            policyCard
            actionsCard
            schedulesCard
            evidenceCard
        }
        .onAppear {
            policy = service.savedPolicy
            lastDaemonPolicy = policy
            hasLoadedDaemonPolicy = false
            service.panelDidAppear()
            monitor.panelDidAppear()
        }
        .onDisappear { service.panelDidDisappear(); monitor.panelDidDisappear() }
        .onReceive(service.$snapshot, perform: receiveSnapshot)
    }

    private func receiveSnapshot(_ snapshot: BatteryCareSnapshot) {
        guard service.helperResponding, !service.restoringPolicy, !snapshot.helperBuild.isEmpty else { return }
        if !hasLoadedDaemonPolicy || policy == lastDaemonPolicy { policy = snapshot.state.policy }
        lastDaemonPolicy = snapshot.state.policy
        hasLoadedDaemonPolicy = true
    }

    private var statusCard: some View {
        SettingsCard(title: text[.title]) {
            Label(statusTitle, systemImage: "battery.75percent")
                .font(.headline)
            if systemRestricted {
                Text(text[.systemRestrictedInfo]).font(.caption).foregroundStyle(.secondary)
            }
            if service.savedPolicy.enabled && (!service.helperResponding || service.restoringPolicy) {
                Text(String(format: text[service.helperResponding ? .policyRestoring : .policyInactive],
                            service.savedPolicy.lower, service.savedPolicy.upper))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let sample = snapshot.sample {
                measuredValues(sample)
                HStack {
                    Image(systemName: sample.connected == true ? "powerplug.fill" : "battery.100percent")
                    Text(text[!sample.isFresh(at: Date()) ? .unavailable : sample.charging == true ? .charging : (sample.watts ?? 0) < -0.5 ? .discharge : .holding])
                    Text(sample.at, style: .time)
                }.font(.caption).foregroundStyle(.secondary)
            }
            if !systemRestricted && service.helperResponding && !service.restoringPolicy &&
                snapshot.state.policy.enabled && !snapshot.state.chargeQualified {
                Text(policyStatus).font(.caption).foregroundStyle(.secondary)
            }
            serviceControls
            if !systemRestricted { Text(text[.persistentInfo]).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var statusTitle: String {
        if !service.helperResponding { return text[service.needsApproval ? .approvalPending : .serviceStopped] }
        if service.restoringPolicy { return text[.recovery] }
        if BatteryControlCompatibility.isRestricted(snapshot) { return text[.systemRestricted] }
        return text.reason(snapshot.reason)
    }

    @ViewBuilder private var serviceControls: some View {
        if !service.registered {
            Button(text[service.needsApproval ? .approve : .install]) { service.authorize() }
        } else if !service.helperResponding {
            Button(text[.retryConnection]) { service.refresh() }.disabled(service.busy)
            Button(text[.approve]) { service.openBackgroundSettings() }
        } else if !systemRestricted && (!snapshot.state.dischargeQualified ||
                    !snapshot.state.chargeQualified &&
                    (snapshot.sample?.percent ?? 100) <= snapshot.state.policy.lower) {
            if !snapshot.state.policy.enabled && (snapshot.sample?.percent ?? 100) <= 90 {
                Text(text[.testInfo]).font(.caption).foregroundStyle(.secondary)
            }
            Button(text[.test]) { service.perform(.qualify) }
                .disabled(service.busy || service.restoringPolicy || snapshot.qualificationStep != nil)
        }
    }

    private func measuredValues(_ sample: BatterySample) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text[.actual]).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 20) {
                metric(l10n.s.batteryCharge, value: sample.percent.map { "\($0)%" } ?? "—", font: .largeTitle)
                metric(l10n.s.monitorShowBatteryTemperature,
                       value: (sample.temperature ?? currentTemperature).map {
                           String(format: "%.1f °C", locale: l10n.language.formattingLocale(), $0)
                       } ?? "—")
                metric(l10n.s.powerSection, value: sample.watts.map {
                    String(format: "%+.1f W", locale: l10n.language.formattingLocale(), $0)
                } ?? "—")
            }
        }
    }

    private var currentTemperature: Double? {
        guard let reading = monitor.snapshot.power,
              (-2...20).contains(Date().timeIntervalSince(reading.sampledAt)) else { return nil }
        return reading.batteryTemperature
    }

    private var policyStatus: String {
        if snapshot.qualificationStep != nil { return text[.policyTesting] }
        if (snapshot.state.qualificationFailures ?? 0) >= 3 { return text[.policyNeedsHelp] }
        if snapshot.state.dischargeQualified {
            return String(format: text[.policyPartial], snapshot.state.policy.lower)
        }
        return text[.policyWaiting]
    }

    private func metric(_ label: String, value: String, font: Font = .body) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(font.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    private var policyCard: some View {
        SettingsCard {
            Toggle(text[.enabled], isOn: Binding(get: { policy.enabled }, set: setPolicyEnabled))
                .disabled(!canConfigure || service.busy)
            Stepper("\(text[.lower]): \(policy.lower)%", value: $policy.lower, in: 20...99)
            Stepper("\(text[.upper]): \(policy.upper)%", value: $policy.upper, in: 21...100)
            Stepper("\(text[.heat]): \(Int(policy.heatCutoff))", value: $policy.heatCutoff, in: 30...45)
            Stepper("\(text[.resumeTemperature]): \(Int(policy.heatResume))", value: $policy.heatResume, in: 20...44)
            Toggle(text[.autoDischarge], isOn: $policy.automaticDischarge)
            Button(text[.save], action: savePolicy)
                .disabled(!policy.isValid || !canConfigure || service.busy
                    || snapshot.state.operation != nil)
        }
    }

    private var actionsCard: some View {
        SettingsCard {
            HStack {
                Button(text[.topUp]) { service.perform(.topUp) }
                Button(text[.calibration]) { service.perform(.calibrate) }
                    .disabled(!snapshot.state.dischargeQualified)
            }.disabled(!canStart)
            HStack {
                Stepper("\(text[.target]): \(dischargeTarget)%", value: $dischargeTarget, in: 10...99)
                Button(text[.discharge]) { service.perform(.discharge, target: dischargeTarget) }
                    .disabled(!canOperate || !snapshot.state.dischargeQualified)
            }
            Text(text[.calibrationInfo]).font(.caption).foregroundStyle(.secondary)
            if let operation = snapshot.state.operation {
                if operation.kind == .calibration {
                    Text(text.phase(operation.phase)).font(.headline)
                    ProgressView(value: progress(operation))
                }
                if operation.paused {
                    Button(text[.resume]) { service.perform(.resume) }.disabled(service.busy)
                }
                Button(text[.cancel]) { service.perform(.cancel) }.disabled(service.busy)
            }
            if snapshot.qualificationStep != nil {
                ProgressView(value: Double(snapshot.qualificationStep ?? 0), total: 4)
                Button(text[.cancel]) { service.perform(.cancel) }.disabled(service.busy)
            }
            Button(text[.system]) { service.perform(.returnToSystem) }
                .disabled(!service.helperResponding || service.busy)
        }
    }

    private var canStart: Bool {
        canOperate && snapshot.state.chargeQualified
    }

    private var canOperate: Bool {
        canConfigure && !service.busy
            && snapshot.state.operation == nil && snapshot.qualificationStep == nil
    }

    private var canConfigure: Bool {
        service.helperResponding && !service.restoringPolicy
    }

    private func savePolicy() {
        service.apply(policy) { succeeded in
            if !succeeded { self.policy = self.service.savedPolicy }
        }
    }

    private func setPolicyEnabled(_ enabled: Bool) {
        guard enabled != policy.enabled else { return }
        policy.enabled = enabled
        hasLoadedDaemonPolicy = true
        savePolicy()
    }

    private func progress(_ operation: BatteryOperation) -> Double {
        let percent = Double(snapshot.sample?.percent ?? 0)
        switch operation.phase {
        case .charge: return percent / 400
        case .discharge: return 0.25 + (100 - percent) / 360
        case .recharge: return 0.5 + percent / 400
        case .hold: return 0.75 + min(1, operation.holdSeconds / 3600) / 4
        }
    }

    private var schedulesCard: some View {
        SettingsCard(title: text[.schedules]) {
            ForEach($policy.schedules) { $schedule in
                BatteryScheduleEditor(schedule: $schedule, text: text) {
                    policy.schedules.removeAll { $0.id == schedule.id }
                }
                Divider()
            }
            Button(text[.add]) {
                var schedule = BatterySchedule()
                schedule.start = Calendar.current.date(bySetting: .second, value: 0, of: schedule.start)!
                policy.schedules.append(schedule)
            }.disabled(policy.schedules.count >= 32)
            Button(text[.save], action: savePolicy)
                .disabled(!policy.isValid || !canConfigure || service.busy
                    || snapshot.state.operation != nil)
        }
    }

    private var evidenceCard: some View {
        SettingsCard {
            DisclosureGroup(text[.evidence]) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.fingerprint).font(.caption)
                    if let diagnostic = snapshot.diagnostic { Text(diagnostic).textSelection(.enabled) }
                    ForEach(snapshot.competitors, id: \.self) { Text($0) }
                    ForEach(snapshot.state.events.reversed()) { event in
                        HStack(alignment: .top) {
                            Text(event.at, style: .time)
                            Text(text.reason(event.reason))
                            if let detail = event.detail { Text(detail).textSelection(.enabled) }
                        }.font(.caption)
                    }
                }
            }
        }
    }
}

private struct BatteryScheduleEditor: View {
    @Binding var schedule: BatterySchedule
    let text: BatteryCareStrings
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(text[.enabled], isOn: $schedule.enabled)
                Spacer()
                Button(text[.remove], action: remove)
            }
            Picker(text[.schedules], selection: $schedule.action) {
                ForEach(BatteryScheduleAction.allCases, id: \.self) { Text(text.action($0)).tag($0) }
            }
            DatePicker(text[.when], selection: $schedule.start)
            Picker(text[.repetition], selection: $schedule.repetition) {
                ForEach(BatteryRepeat.allCases, id: \.self) { Text(text.repetition($0)).tag($0) }
            }
            TextField(text[.timeZone], text: $schedule.timeZone)
            if schedule.action == .limit || schedule.action == .discharge {
                Stepper("\(text[.target]): \(schedule.target)%", value: $schedule.target,
                        in: schedule.action == .limit ? 21...100 : 10...99)
            }
            Toggle(text[.missed], isOn: $schedule.runMissed)
        }
    }
}
