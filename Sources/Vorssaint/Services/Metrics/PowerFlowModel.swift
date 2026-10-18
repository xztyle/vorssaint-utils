// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

/// The diagram balances charger input and signed battery flow. The separate
/// system sensor is not forced to match: SMC sensors have independent windows.
struct PowerFlowModel: Equatable {
    enum Role: String { case adapter, batterySource, mac, batteryCharge, chip, other }
    enum State { case charging, paused, discharging, assisting, unavailable }
    struct Node: Identifiable, Equatable {
        let role: Role
        let watts: Double?
        var id: Role { role }
    }
    struct Link: Identifiable, Equatable {
        let source: Role
        let destination: Role
        let watts: Double?
        var id: String { source.rawValue + destination.rawValue }
    }

    let sources: [Node]
    let destinations: [Node]
    let links: [Link]
    let breakdown: [Node]
    let breakdownLinks: [Link]
    let state: State
    let calculatedMac: Bool
    let readingsSettling: Bool
    let sampledAt: Date
    var isEmpty: Bool { sources.isEmpty || destinations.isEmpty }
    var totalWatts: Double { max(sources.compactMap(\.watts).reduce(0, +), destinations.compactMap(\.watts).reduce(0, +), 1) }

    static func make(adapter: Double?, battery: Double?, system: Double?,
                     connected: Bool, sampledAt: Date, chip: Double? = nil) -> Self {
        let input = connected ? valid(adapter) : nil
        let flow = battery.flatMap { $0.isFinite && abs($0) < 1000 ? $0 : nil }
        let discharge = flow.map { max(0, -$0) }.flatMap { $0 > 0.5 ? $0 : nil }
        let charge = connected ? flow.map { max(0, $0) }.flatMap { $0 > 0.5 ? $0 : nil } : nil
        let settling = inconsistent(input: input, charge: charge)
        let mac = macPower(input: input, discharge: discharge, charge: charge,
                           system: valid(system), connected: connected, settling: settling || flow == nil)
        let parts = splitMac(mac.watts, chip: valid(chip))
        let sources = sourceNodes(input: input, discharge: discharge, connected: connected)
        var destinations = [Node(role: .mac, watts: mac.watts)]
        if let charge { destinations.append(Node(role: .batteryCharge, watts: charge)) }
        return Self(sources: sources, destinations: destinations,
                    links: makeLinks(sources: sources, charge: charge, settling: settling || flow == nil),
                    breakdown: parts.nodes, breakdownLinks: parts.links,
                    state: flow == nil ? .unavailable : flowState(input: input, discharge: discharge, charge: charge, connected: connected),
                    calculatedMac: mac.calculated, readingsSettling: settling || parts.settling, sampledAt: sampledAt)
    }

    private static func splitMac(_ mac: Double?, chip: Double?) -> (nodes: [Node], links: [Link], settling: Bool) {
        guard let chip else { return ([], [], false) }
        let other = mac.flatMap { $0 >= chip ? $0 - chip : nil }
        let nodes = [Node(role: .chip, watts: chip), Node(role: .other, watts: other)]
        let links = [Link(source: .mac, destination: .chip, watts: other == nil ? nil : chip),
                     Link(source: .mac, destination: .other, watts: other)]
        return (nodes, links, mac.map { chip > $0 } ?? false)
    }

    func isFresh(at date: Date, interval: Double) -> Bool {
        let age = date.timeIntervalSince(sampledAt)
        return age >= -2 && age <= max(6, interval * 3)
    }

    private static func valid(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && $0 >= 0 && $0 < 1000 ? $0 : nil }
    }

    private static func inconsistent(input: Double?, charge: Double?) -> Bool {
        guard let input, let charge else { return false }
        return charge > input
    }

    private static func sourceNodes(input: Double?, discharge: Double?, connected: Bool) -> [Node] {
        var nodes: [Node] = []
        if connected { nodes.append(Node(role: .adapter, watts: input)) }
        if let discharge { nodes.append(Node(role: .batterySource, watts: discharge)) }
        if !connected && discharge == nil { nodes.append(Node(role: .batterySource, watts: nil)) }
        return nodes
    }

    private static func macPower(input: Double?, discharge: Double?, charge: Double?,
                                 system: Double?, connected: Bool, settling: Bool) -> (watts: Double?, calculated: Bool) {
        if connected, let input, !settling {
            return (max(0, input + (discharge ?? 0) - (charge ?? 0)), true)
        }
        if !connected, let discharge { return (discharge, true) }
        return (system, false)
    }

    private static func makeLinks(sources: [Node], charge: Double?, settling: Bool) -> [Link] {
        sources.flatMap { source -> [Link] in
            if source.role == .batterySource {
                return [Link(source: source.role, destination: .mac, watts: source.watts)]
            }
            let remainder = source.watts.map { max(0, $0 - (charge ?? 0)) }
            var links = [Link(source: .adapter, destination: .mac, watts: settling ? nil : remainder)]
            if let charge {
                links.append(Link(source: .adapter, destination: .batteryCharge,
                                  watts: source.watts == nil || settling ? nil : charge))
            }
            return links
        }
    }

    private static func flowState(input: Double?, discharge: Double?, charge: Double?, connected: Bool) -> State {
        if charge != nil { return .charging }
        if discharge != nil { return connected && (input ?? 0) > 0.5 ? .assisting : .discharging }
        if connected { return .paused }
        return .unavailable
    }
}

enum PowerComponent: String, CaseIterable, Identifiable {
    case display, memory, leftPort, rightPort
    var id: String { rawValue }
    var keys: [String] {
        switch self {
        case .display: return ["PDBR", "PBwo"]
        case .memory: return ["PMTR"]
        case .leftPort: return ["PU1R"]
        case .rightPort: return ["PU2R"]
        }
    }
}

struct PowerComponentReading: Identifiable, Equatable {
    let component: PowerComponent
    let watts: Double
    var id: PowerComponent { component }
}
