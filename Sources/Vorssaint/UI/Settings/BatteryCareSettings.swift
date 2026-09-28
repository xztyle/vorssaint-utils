// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import SwiftUI

struct BatteryCareSettings: View {
    @ObservedObject private var service = BatteryCareService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var policy = BatteryCarePolicy()
    @State private var dischargeTarget = 50
    private var text: BatteryCareStrings { FeatureStrings.batteryCare(l10n.language) }
    private var snapshot: BatteryCareSnapshot { service.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusCard
            policyCard
            actionsCard
            schedulesCard
            evidenceCard
        }
        .onAppear {
            policy = service.savedPolicy
            service.panelDidAppear()
        }
        .onDisappear { service.panelDidDisappear() }
    }

    private var statusCard: some View {
        SettingsCard(title: text[.title]) {
            Label(text.reason(snapshot.reason), systemImage: "battery.75percent")
                .font(.headline)
            if let sample = snapshot.sample {
                HStack(spacing: 20) {
                    Text(sample.percent.map { "\($0)%" } ?? "—").font(.largeTitle.monospacedDigit())
                    Text(sample.temperature.map { String(format: "%.1f °C", $0) } ?? "—")
                    Text(sample.watts.map { String(format: "%+.1f W", $0) } ?? "—")
                }.accessibilityLabel(text[.actual])
                Text(sample.at, style: .time).font(.caption).foregroundStyle(.secondary)
            }
            if !service.registered {
                Button(text[service.needsApproval ? .approve : .install]) { service.authorize() }
            } else if !snapshot.state.chargeQualified {
                Text(text[.testInfo]).font(.caption).foregroundStyle(.secondary)
                Button(text[.test]) { service.perform(.qualify) }
                    .disabled(service.busy || snapshot.qualificationStep != nil)
            }
            Text(text[.persistentInfo]).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var policyCard: some View {
        SettingsCard {
            Toggle(text[.enabled], isOn: $policy.enabled)
            Stepper("\(text[.lower]): \(policy.lower)%", value: $policy.lower, in: 20...99)
            Stepper("\(text[.upper]): \(policy.upper)%", value: $policy.upper, in: 21...100)
            Stepper("\(text[.heat]): \(Int(policy.heatCutoff))", value: $policy.heatCutoff, in: 30...45)
            Stepper("\(text[.resumeTemperature]): \(Int(policy.heatResume))", value: $policy.heatResume, in: 20...44)
            Toggle(text[.autoDischarge], isOn: $policy.automaticDischarge)
                .disabled(!snapshot.state.dischargeQualified)
            Button(text[.save]) { service.apply(policy) }
                .disabled(!policy.isValid || !service.registered || service.busy
                    || (policy.enabled && !snapshot.state.chargeQualified) || snapshot.state.operation != nil)
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
                    .disabled(!canStart || !snapshot.state.dischargeQualified)
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
                .disabled(!service.registered || service.busy)
        }
    }

    private var canStart: Bool {
        service.registered && snapshot.state.chargeQualified && !service.busy
            && snapshot.state.operation == nil && snapshot.qualificationStep == nil
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
            Button(text[.save]) { service.apply(policy) }
                .disabled(!policy.isValid || !service.registered || service.busy || snapshot.state.operation != nil)
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
