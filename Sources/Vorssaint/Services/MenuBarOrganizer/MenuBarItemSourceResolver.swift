// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Foundation

/// Resolves the app that created each status item. On macOS 26 the WindowServer
/// owner is commonly Control Center, so owner PID alone is not a stable item
/// identity. AX work runs away from the main actor and is bounded by the app's
/// process-wide AX timeout.
actor MenuBarItemSourceResolver {
    private struct ApplicationRecord: Sendable {
        let pid: pid_t
        let bundleIdentifier: String
        let name: String
    }

    private struct AXItemRecord: Sendable {
        let source: MenuBarItemSourceIdentity
        let frame: CGRect
    }

    private var cache: [CGWindowID: MenuBarItemSourceIdentity] = [:]
    private var scanTask: Task<[CGWindowID: MenuBarItemSourceIdentity], Never>?
    private var scanID: UUID?
    private var diagnosticRequested = false

    func resolve(records: [MenuBarOrganizerWindowRecord]) async -> [CGWindowID: MenuBarItemSourceIdentity] {
        let liveWindowIDs = Set(records.map(\.windowID))
        cache = cache.filter { liveWindowIDs.contains($0.key) && sourceStillRunning($0.value) && $0.value.canReuseWithoutAXRescan }
        cacheDirectItems(records)
        let unresolved = records.filter { cache[$0.windowID]?.stableTitle == nil }
        guard !unresolved.isEmpty, AXIsProcessTrusted() else { return cache }
        let (applications, guiRunning) = await Self.runningApplications()
        if scanTask == nil {
            scanID = UUID()
            let destination = diagnosticRequested ? nil : MenuBarAXDiagnosticTrace.destination
            if destination != nil { diagnosticRequested = true }
            scanTask = Task.detached(priority: .utility) {
                Self.match(records: unresolved, applications: applications, diagnostic: destination, guiRunning: guiRunning)
            }
        }
        guard let task = scanTask, let generation = scanID else { return cache }
        let matches = await task.value
        guard generation == scanID else { return cache }
        scanTask = nil
        scanID = nil
        for (id, source) in matches where liveWindowIDs.contains(id) { cache[id] = source }
        return cache
    }

    private func sourceStillRunning(_ source: MenuBarItemSourceIdentity) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: source.pid) else { return false }
        return !app.isTerminated && app.bundleIdentifier == source.bundleIdentifier
    }

    private func cacheDirectItems(_ records: [MenuBarOrganizerWindowRecord]) {
        for record in records where record.ownerBundleIdentifier != MenuBarOrganizerSupport.controlCenterBundleIdentifier
            && cache[record.windowID] == nil {
            guard !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            cache[record.windowID] = MenuBarItemSourceIdentity(pid: record.ownerPID,
                bundleIdentifier: record.ownerBundleIdentifier, name: record.ownerName,
                axIdentifier: nil, axTitle: record.title)
        }
    }

    @MainActor
    private static func runningApplications() -> ([ApplicationRecord], Bool) {
        let applications = NSWorkspace.shared.runningApplications.compactMap { app -> ApplicationRecord? in
            guard !app.isTerminated, let bundle = app.bundleIdentifier else { return nil }
            return ApplicationRecord(pid: app.processIdentifier, bundleIdentifier: bundle,
                                     name: app.localizedName ?? bundle)
        }
        return (applications, NSApp?.isRunning ?? false)
    }

    func invalidate() {
        scanTask?.cancel()
        scanTask = nil
        scanID = nil
        cache.removeAll()
    }

    private static func match(records: [MenuBarOrganizerWindowRecord],
                              applications: [ApplicationRecord], diagnostic: URL?, guiRunning: Bool) -> [CGWindowID: MenuBarItemSourceIdentity] {
        let trace = diagnostic.map { MenuBarAXDiagnosticTrace(destination: $0, records: records, guiRunning: guiRunning) }
        var axItems: [AXItemRecord] = []
        for app in applications {
            guard !Task.isCancelled else { return [:] }
            if let trace, !trace.shouldContinue { break }
            axItems.append(contentsOf: scanExtrasMenuBar(app, trace: trace))
        }
        let candidates = records.flatMap { record in axItems.compactMap { candidate(record, axItem: $0, trace: trace) } }
        let result = MenuBarSourceMatchPolicy.matches(candidates)
        trace?.finish(matches: result)
        return result
    }

    private static func candidate(_ record: MenuBarOrganizerWindowRecord, axItem: AXItemRecord,
                                  trace: MenuBarAXDiagnosticTrace?) -> MenuBarSourceCandidate? {
        let rejectedHost = !MenuBarOrganizerSupport.sourceIdentityAllowed(recordTitle: record.title, source: axItem.source)
        let score = MenuBarOrganizerSupport.frameMatchScore(record.frame, axItem.frame)
        trace?.addCandidate(record: record, source: axItem.source, frame: axItem.frame, score: score,
                            rejection: rejectedHost ? "generic-host-title" : score == nil ? "geometry" : nil)
        guard !rejectedHost, let score else { return nil }
        let slot = "\(axItem.source.pid):\(axItem.source.stableTitle ?? ""):\(axItem.frame.minX):\(axItem.frame.minY)"
        return MenuBarSourceCandidate(windowID: record.windowID, source: axItem.source, score: score, sourceSlot: slot)
    }

    private static func scanExtrasMenuBar(_ app: ApplicationRecord, trace: MenuBarAXDiagnosticTrace?) -> [AXItemRecord] {
        let application = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(application, 0.2)
        let extras: Read<AXUIElement> = read("AXExtrasMenuBar", from: application)
        let children: Read<[AXUIElement]> = extras.value.map { read(kAXChildrenAttribute, from: $0) } ?? .init(value: nil, error: nil)
        var childReports: [[String: Any]] = []
        let result = (children.value ?? []).prefix(trace == nil ? Int.max : 64).compactMap { child -> AXItemRecord? in
            if let trace, !trace.shouldContinue { return nil }
            return scanChild(child, app: app, single: children.value?.count == 1, reports: &childReports, trace: trace)
        }
        trace?.applications.append(["bundle": app.bundleIdentifier, "pid": app.pid,
            "extrasError": extras.error as Any? ?? NSNull(), "childrenError": children.error as Any? ?? NSNull(),
            "childCount": children.value?.count ?? 0, "children": childReports])
        return result
    }

    private static func scanChild(_ child: AXUIElement, app: ApplicationRecord, single: Bool, reports: inout [[String: Any]],
                                  trace: MenuBarAXDiagnosticTrace?) -> AXItemRecord? {
        if trace != nil { AXUIElementSetMessagingTimeout(child, 0.35) }
        let frame: Read<AXValue> = read("AXFrame", from: child)
        let point: Read<AXValue> = read(kAXPositionAttribute, from: child)
        let size: Read<AXValue> = read(kAXSizeAttribute, from: child)
        let geometry = MenuBarOrganizerSupport.accessibilityFrame(frame: frame.value, position: point.value, size: size.value)
        guard geometry != nil || trace != nil else { return nil }
        let identifier: Read<String> = read(kAXIdentifierAttribute, from: child)
        let title: Read<String> = read(kAXTitleAttribute, from: child)
        let description: Read<String> = read(kAXDescriptionAttribute, from: child)
        if trace != nil {
            reports.append(["frame": geometry.map(MenuBarAXDiagnosticTrace.rect) as Any? ?? NSNull(),
                "rawFrame": MenuBarAXDiagnosticTrace.geometry(frame.value),
                "position": MenuBarAXDiagnosticTrace.geometry(point.value), "size": MenuBarAXDiagnosticTrace.geometry(size.value),
                "frameError": frame.error as Any? ?? NSNull(), "positionError": point.error as Any? ?? NSNull(),
                "sizeError": size.error as Any? ?? NSNull(), "identifier": MenuBarAXDiagnosticTrace.textPresence(identifier.value),
                "title": MenuBarAXDiagnosticTrace.textPresence(title.value), "description": MenuBarAXDiagnosticTrace.textPresence(description.value),
                "identifierError": identifier.error as Any? ?? NSNull(), "titleError": title.error as Any? ?? NSNull(),
                "descriptionError": description.error as Any? ?? NSNull()])
        }
        guard let geometry else { return nil }
        var pid = app.pid
        AXUIElementGetPid(child, &pid)
        let source = MenuBarItemSourceIdentity(pid: pid, bundleIdentifier: app.bundleIdentifier, name: app.name,
            axIdentifier: identifier.value, axTitle: title.value, axDescription: description.value,
            isOnlyStatusItem: single && pid == app.pid)
        return AXItemRecord(source: source, frame: geometry)
    }

    private struct Read<T> {
        let value: T?
        let error: Int32?
    }

    private static func read<T>(_ name: String, from element: AXUIElement) -> Read<T> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return .init(value: error == .success ? value as? T : nil, error: error.rawValue)
    }

}
