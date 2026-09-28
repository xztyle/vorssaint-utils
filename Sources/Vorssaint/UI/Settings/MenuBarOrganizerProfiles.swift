// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import SwiftUI

struct MenuBarOrganizerProfiles: View {
    @ObservedObject var service: MenuBarOrganizerService
    @ObservedObject private var l10n = L10n.shared
    @State private var name = ""
    @State private var renaming: UUID?
    @State private var editingRule: MenuBarRevealRule?
    private var text: MenuBarProductStrings { .localized(l10n.language) }

    var body: some View {
        profileSection
        ruleSection
        Section {
            ForEach(GlobalShortcutRole.menuBarRoles) { role in
                MenuBarOrganizerShortcutRow(role: role)
            }
            if service.shortcutRegistrationFailed {
                Text(l10n.s.shortcutUnavailable).font(.caption).foregroundStyle(.orange)
            }
        } header: { Text(l10n.s.shortcutsPageTitle) }
        .sheet(item: $editingRule) { rule in
            MenuBarRuleEditor(service: service, rule: rule) { editingRule = nil }
        }
    }

    private var profileSection: some View {
        Section {
            HStack {
                TextField(text.name, text: $name)
                Button(renaming == nil ? text.save : text.rename) {
                    if let renaming { service.renameProfile(renaming, name: name) }
                    else { service.saveProfile(name: name) }
                    name = ""; renaming = nil
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.isBusy)
            }
            ForEach(service.library.profiles) { profile in
                HStack {
                    Text(profile.name).lineLimit(1)
                    if service.library.activeProfileID == profile.id { Image(systemName: "checkmark.circle") }
                    Spacer()
                    Button(text.apply) { service.applyProfile(profile.id) }.disabled(service.isBusy)
                    Button(text.rename) { name = profile.name; renaming = profile.id }
                    Button(text.delete) { service.deleteProfile(profile.id) }
                }
            }
        } header: { Text(text.profiles) }
    }

    private var ruleSection: some View {
        Section {
            ForEach(service.library.rules) { rule in
                HStack {
                    Toggle(rule.name, isOn: Binding(get: { rule.enabled }, set: { value in
                        var updated = rule; updated.enabled = value; service.saveRule(updated)
                    }))
                    Button(text.edit) { editingRule = rule }
                    Button(text.delete) { service.deleteRule(rule.id) }
                }
            }
            Button(text.addRule) { editingRule = MenuBarRevealRule(name: text.addRule) }
            Text(text.rulesHint).font(.caption).foregroundStyle(.secondary)
        } header: { Text(text.rules) }
    }
}

private struct MenuBarOrganizerShortcutRow: View {
    let role: GlobalShortcutRole
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        ShortcutPreferenceRow(role: role, label: role.title(l10n.s), includeInactiveConflicts: true) {
            MenuBarOrganizerService.shared.syncHotkeys()
        }
    }
}

private struct MenuBarRuleEditor: View {
    @ObservedObject var service: MenuBarOrganizerService
    @State var rule: MenuBarRevealRule
    let close: () -> Void
    @ObservedObject private var l10n = L10n.shared
    private var text: MenuBarProductStrings { .localized(l10n.language) }

    var body: some View {
        VStack {
            Form {
                TextField(text.name, text: $rule.name)
                Toggle(text.enabled, isOn: $rule.enabled)
                conditionControls
                actionControls
                Stepper("\(text.duration): \(Int(rule.duration))", value: $rule.duration, in: 1...300, step: 1)
                Stepper("\(text.priority): \(rule.priority)", value: $rule.priority, in: -100...100)
            }.formStyle(.grouped)
            HStack {
                Button(l10n.s.mediaCancel, action: close)
                Spacer()
                Button(text.apply) { service.saveRule(rule); close() }.disabled(!valid)
                    .buttonStyle(.borderedProminent)
            }.padding()
        }.frame(width: 520, height: 460)
    }

    private var conditionControls: some View {
        Group {
            Picker(text.condition, selection: $rule.condition) {
                ForEach(MenuBarRuleCondition.allCases, id: \.self) { Text(text.conditionName($0)).tag($0) }
            }
            if ![.onBattery, .onPower, .itemPresent].contains(rule.condition) {
                TextField(text.conditionName(rule.condition), text: $rule.value)
            }
            if rule.condition == .timeRange {
                Stepper("\(text.endMinute): \(rule.endMinute)", value: $rule.endMinute, in: 0...1439)
            }
            if rule.condition == .itemPresent { itemPicker }
        }
    }

    private var actionControls: some View {
        Group {
            Picker(text.action, selection: $rule.action) {
                ForEach(MenuBarRuleAction.allCases, id: \.self) { Text(text.actionName($0)).tag($0) }
            }
            if rule.action == .revealItem, rule.condition != .itemPresent { itemPicker }
            if rule.action == .applyProfile {
                Picker(text.profile, selection: $rule.profileID) {
                    Text("—").tag(Optional<UUID>.none)
                    ForEach(service.library.profiles) { Text($0.name).tag(Optional($0.id)) }
                }
            }
        }
    }

    private var itemPicker: some View {
        Picker(text.item, selection: $rule.item) {
            Text("—").tag(Optional<MenuBarItemIdentity>.none)
            ForEach(service.items.filter { $0.isMovable && $0.id.isPortable }) {
                Text($0.displayName).tag(Optional($0.id))
            }
        }
    }

    private var valid: Bool {
        guard rule.isValid else { return false }
        if rule.action == .applyProfile, rule.profileID == nil { return false }
        if rule.action == .revealItem || rule.condition == .itemPresent { return rule.item != nil }
        switch rule.condition {
        case .frontmostApp: return rule.value.contains(".")
        case .batteryBelow: return Int(rule.value).map { (1...100).contains($0) } ?? false
        case .timeRange: return Int(rule.value).map { (0...1439).contains($0) && $0 != rule.endMinute } ?? false
        case .displayCount: return Int(rule.value).map { (1...32).contains($0) } ?? false
        default: return true
        }
    }
}
