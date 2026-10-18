// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import SwiftUI

struct PowerFlowView: View {
    let reading: PowerReading?
    var compact = true
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.monitorInterval) private var interval = 2
    @State private var detailsExpanded = false
    @State private var explanationShown = false
    private var text: PowerFlowStrings { FeatureStrings.powerFlow(l10n.language) }
    private var model: PowerFlowModel? {
        guard let reading, !reading.isEmpty else { return nil }
        return PowerFlowModel.make(adapter: reading.adapterWatts,
            battery: PowerSampler.hasInternalBattery ? reading.batteryWatts : 0, system: reading.systemWatts,
            connected: reading.externalConnected || !PowerSampler.hasInternalBattery,
            sampledAt: reading.sampledAt, chip: reading.chip.chipWatts)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fresh = model?.isFresh(at: context.date, interval: Double(Defaults.sanitizedMonitorInterval(interval))) == true
            VStack(alignment: .leading, spacing: 10) {
                header(fresh: fresh)
                if let model {
                    Text(!fresh ? text[.stale] : model.readingsSettling ? text[.settling] : text.state(model.state))
                        .font(.system(size: compact ? 10.5 : 12)).foregroundStyle(.secondary)
                    PowerSankeyView(model: model, fresh: fresh, compact: compact, text: text, l10n: l10n)
                } else {
                    Text(reading == nil ? l10n.s.breakdownMeasuring : text[.unavailable])
                        .font(.caption).foregroundStyle(.secondary)
                }
                details
            }
        }
    }

    private func header(fresh: Bool) -> some View {
        HStack(spacing: 6) {
            Text(text[.title]).font(.system(size: compact ? 12 : 15, weight: .semibold))
            Spacer(minLength: 0)
            Circle().fill(fresh ? Color.accentColor : Color.secondary).frame(width: 5, height: 5)
            Text(fresh ? text[.live] : text[.stale]).font(.system(size: 9)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Button { explanationShown.toggle() } label: { Image(systemName: "info.circle") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel(text[.details])
                .popover(isPresented: $explanationShown) {
                    Text(text[.derived] + "\n\n" + text[.chipNote]).font(.callout).padding(16).frame(width: 285)
                }
        }
    }

    @ViewBuilder private var details: some View {
        if compact {
            DisclosureGroup(text[.details], isExpanded: $detailsExpanded) { measuredDetails.padding(.top, 6) }
                .font(.system(size: 10.5)).tint(.secondary)
        } else { measuredDetails }
    }

    private var measuredDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text[.measured]).font(.caption).foregroundStyle(.secondary)
            if let reading {
                if let system = reading.systemWatts { sensorRow(l10n.s.powerSystem, watts: system) }
                ForEach(reading.components) { component in
                    sensorRow(text.component(component.component, memory: l10n.s.memorySection), watts: component.watts)
                }
                ForEach(ChipPowerComponent.allCases) { component in
                    if let watts = reading.chip.watts[component] {
                        sensorRow(text.chipComponent(component, memory: l10n.s.memorySection), watts: watts)
                    }
                }
            }
            if !compact { EnergyAppsBreakdown() }
        }
    }

    private func sensorRow(_ name: String, watts: Double) -> some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text(MetricFormat.wattsPrecise(watts)).monospacedDigit().contentTransition(.numericText())
        }.font(.system(size: compact ? 11 : 12))
            .accessibilityElement(children: .combine)
    }
}

private struct PowerSankeyView: View {
    let model: PowerFlowModel
    let fresh: Bool
    let compact: Bool
    let text: PowerFlowStrings
    let l10n: L10n
    @State private var showsBreakdown = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            nodeColumn(model.sources).frame(width: nodeWidth)
            animatedRibbons(model.links, sources: model.sources, destinations: model.destinations)
            nodeColumn(model.destinations).frame(width: nodeWidth)
            if showsBreakdown && !model.breakdown.isEmpty {
                animatedRibbons(model.breakdownLinks, sources: model.destinations, destinations: model.breakdown)
                nodeColumn(model.breakdown).frame(width: nodeWidth)
            }
        }
        .frame(height: model.sources.count == 1 && model.destinations.count == 1
            && (!showsBreakdown || model.breakdown.count < 2) ? 96 : 136)
        .opacity(fresh ? 1 : 0.55)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: model)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: showsBreakdown)
    }

    private var nodeWidth: Double { compact ? 64 : 78 }

    private func animatedRibbons(_ links: [PowerFlowModel.Link], sources: [PowerFlowModel.Node],
                                 destinations: [PowerFlowModel.Node]) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !animates)) { context in
            ribbons(links, sources: sources, destinations: destinations,
                    phase: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) * 24)
        }.accessibilityHidden(true)
    }

    private var animates: Bool {
        fresh && !reduceMotion && !model.readingsSettling && model.links.contains { ($0.watts ?? 0) > 0.5 }
    }

    private func nodeColumn(_ nodes: [PowerFlowModel.Node]) -> some View {
        VStack(spacing: 0) {
            ForEach(nodes) { node in
                if node.role == .mac && !model.breakdown.isEmpty {
                    Button { showsBreakdown.toggle() } label: { nodeLabel(node) }
                        .buttonStyle(.plain).frame(maxHeight: .infinity)
                        .help(text[showsBreakdown ? .hideChip : .showChip])
                        .accessibilityHint(text[showsBreakdown ? .hideChip : .showChip])
                } else {
                    nodeLabel(node).frame(maxHeight: .infinity)
                }
            }
        }
    }

    private func nodeLabel(_ node: PowerFlowModel.Node) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol(node.role)).font(.system(size: 17, weight: .medium)).foregroundStyle(color(node.role))
            Text(title(node.role)).font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            Text(node.watts.map(MetricFormat.wattsPrecise) ?? "—")
                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }

    private func ribbons(_ links: [PowerFlowModel.Link], sources: [PowerFlowModel.Node],
                         destinations: [PowerFlowModel.Node], phase: Double) -> some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(links) { link in
                    let ports = ports(for: link, links: links, sources: sources, destinations: destinations,
                                      height: geometry.size.height)
                    if let watts = link.watts, watts > 0.5 {
                        ribbon(link, ports: ports, phase: phase)
                    } else if link.watts == nil {
                        SankeyCenterLine(startY: ports.start, endY: ports.end)
                            .stroke(.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))
                    }
                }
            }
        }
    }

    private func ribbon(_ link: PowerFlowModel.Link, ports: Ports, phase: Double) -> some View {
        ZStack {
            SankeyRibbon(startY: ports.start, endY: ports.end, thickness: ports.thickness)
                .fill(LinearGradient(colors: [color(link.source).opacity(reduceTransparency ? 0.8 : 0.42),
                    color(link.destination).opacity(reduceTransparency ? 0.8 : 0.24)], startPoint: .leading, endPoint: .trailing))
            SankeyCenterLine(startY: ports.start, endY: ports.end)
                .stroke(color(link.source).opacity(contrast == .increased ? 1 : 0.7),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 18], dashPhase: -phase))
        }
    }

    private struct Ports { let start: Double; let end: Double; let thickness: Double }
    private func ports(for link: PowerFlowModel.Link, links: [PowerFlowModel.Link], sources: [PowerFlowModel.Node],
                       destinations: [PowerFlowModel.Node], height: Double) -> Ports {
        let scale = 46 / model.totalWatts
        let thickness = max(3, (link.watts ?? 0) * scale)
        let outgoing = links.filter { $0.source == link.source }
        let incoming = links.filter { $0.destination == link.destination }
        let start = center(link.source, nodes: sources, height: height) + offset(link, links: outgoing, scale: scale)
        let end = center(link.destination, nodes: destinations, height: height) + offset(link, links: incoming, scale: scale)
        return Ports(start: start, end: end, thickness: thickness)
    }

    private func center(_ role: PowerFlowModel.Role, nodes: [PowerFlowModel.Node], height: Double) -> Double {
        let index = nodes.firstIndex { $0.role == role } ?? 0
        return height * (Double(index) + 0.5) / Double(max(1, nodes.count))
    }

    private func offset(_ link: PowerFlowModel.Link, links: [PowerFlowModel.Link], scale: Double) -> Double {
        let widths = links.map { max(3, ($0.watts ?? 0) * scale) }
        let index = links.firstIndex { $0.id == link.id } ?? 0
        return -widths.reduce(0, +) / 2 + widths.prefix(index).reduce(0, +) + widths[index] / 2
    }

    private func title(_ role: PowerFlowModel.Role) -> String {
        switch role {
        case .adapter: return l10n.s.powerAdapter
        case .batterySource: return l10n.s.powerBattery
        case .mac: return model.calculatedMac ? text[.mac] : l10n.s.powerSystem
        case .batteryCharge: return text[.charging]
        case .chip: return text[.chip]
        case .other: return text[.other]
        }
    }

    private func symbol(_ role: PowerFlowModel.Role) -> String {
        switch role {
        case .adapter: return "powerplug.fill"
        case .batterySource: return "battery.75percent"
        case .mac: return "laptopcomputer"
        case .batteryCharge: return "battery.100percent.bolt"
        case .chip: return "cpu"
        case .other: return "ellipsis.circle"
        }
    }

    private func color(_ role: PowerFlowModel.Role) -> Color {
        switch role {
        case .adapter, .mac: return .accentColor
        case .batterySource: return PanelMetricColor.orange(for: scheme)
        case .batteryCharge: return PanelMetricColor.green(for: scheme)
        case .chip: return .accentColor
        case .other: return PanelMetricColor.orange(for: scheme)
        }
    }
}

private struct SankeyRibbon: Shape {
    var startY: Double
    var endY: Double
    var thickness: Double
    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get { AnimatablePair(AnimatablePair(startY, endY), thickness) }
        set { startY = newValue.first.first; endY = newValue.first.second; thickness = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let half = thickness / 2
        let control = rect.width * 0.45
        var path = Path()
        path.move(to: CGPoint(x: 0, y: startY - half))
        path.addCurve(to: CGPoint(x: rect.width, y: endY - half),
            control1: CGPoint(x: control, y: startY - half), control2: CGPoint(x: rect.width - control, y: endY - half))
        path.addLine(to: CGPoint(x: rect.width, y: endY + half))
        path.addCurve(to: CGPoint(x: 0, y: startY + half),
            control1: CGPoint(x: rect.width - control, y: endY + half), control2: CGPoint(x: control, y: startY + half))
        path.closeSubpath()
        return path
    }
}

private struct SankeyCenterLine: Shape {
    var startY: Double
    var endY: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startY, endY) }
        set { startY = newValue.first; endY = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: startY))
        path.addCurve(to: CGPoint(x: rect.width, y: endY),
            control1: CGPoint(x: rect.width * 0.45, y: startY), control2: CGPoint(x: rect.width * 0.55, y: endY))
        return path
    }
}
