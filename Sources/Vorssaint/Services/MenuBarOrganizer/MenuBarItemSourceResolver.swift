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

    func resolve(records: [MenuBarOrganizerWindowRecord]) async -> [CGWindowID: MenuBarItemSourceIdentity] {
        let liveWindowIDs = Set(records.map(\.windowID))
        cache = cache.filter { liveWindowIDs.contains($0.key) && sourceStillRunning($0.value) }
        cacheDirectItems(records)
        let unresolved = records.filter { cache[$0.windowID]?.stableTitle == nil }
        guard !unresolved.isEmpty, AXIsProcessTrusted() else { return cache }
        let applications = await Self.runningApplications()
        if scanTask == nil {
            scanID = UUID()
            scanTask = Task.detached(priority: .utility) { Self.match(records: unresolved, applications: applications) }
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
    private static func runningApplications() -> [ApplicationRecord] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard !app.isTerminated, let bundle = app.bundleIdentifier else { return nil }
            return ApplicationRecord(pid: app.processIdentifier, bundleIdentifier: bundle,
                                     name: app.localizedName ?? bundle)
        }
    }

    func invalidate() {
        scanTask?.cancel()
        scanTask = nil
        scanID = nil
        cache.removeAll()
    }

    private struct Candidate {
        let windowID: CGWindowID
        let source: MenuBarItemSourceIdentity
        let score: CGFloat
        let sourceSlot: String
    }

    private static func match(records: [MenuBarOrganizerWindowRecord],
                              applications: [ApplicationRecord]) -> [CGWindowID: MenuBarItemSourceIdentity] {
        var axItems: [AXItemRecord] = []
        for app in applications {
            guard !Task.isCancelled else { return [:] }
            axItems.append(contentsOf: scanExtrasMenuBar(app))
        }
        let candidates = records.flatMap { record in axItems.compactMap { candidate(record, axItem: $0) } }
        var usedSources: Set<String> = []
        var result: [CGWindowID: MenuBarItemSourceIdentity] = [:]
        for (_, group) in Dictionary(grouping: candidates, by: \.windowID) {
            let ordered = group.sorted { $0.score < $1.score }
            guard let best = ordered.first, !usedSources.contains(best.sourceSlot),
                  ordered.count == 1 || ordered[1].score - best.score > 0.5 else { continue }
            usedSources.insert(best.sourceSlot)
            result[best.windowID] = best.source
        }
        return result
    }

    private static func candidate(_ record: MenuBarOrganizerWindowRecord, axItem: AXItemRecord) -> Candidate? {
        if MenuBarOrganizerSupport.isGenericControlCenterHostedTitle(record.title),
           axItem.source.bundleIdentifier == MenuBarOrganizerSupport.controlCenterBundleIdentifier { return nil }
        guard let score = MenuBarOrganizerSupport.frameMatchScore(record.frame, axItem.frame) else { return nil }
        let slot = "\(axItem.source.pid):\(axItem.source.stableTitle ?? ""):\(Int(axItem.frame.minX)):\(Int(axItem.frame.minY))"
        return Candidate(windowID: record.windowID, source: axItem.source, score: score, sourceSlot: slot)
    }

    private static func scanExtrasMenuBar(_ app: ApplicationRecord) -> [AXItemRecord] {
        let application = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(application, 0.2)
        guard let extras: AXUIElement = attribute("AXExtrasMenuBar", from: application),
              let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: extras)
        else { return [] }

        return children.compactMap { child in
            guard let frame = frame(of: child) else { return nil }
            var pid = app.pid
            AXUIElementGetPid(child, &pid)
            let source = MenuBarItemSourceIdentity(
                pid: pid,
                bundleIdentifier: app.bundleIdentifier,
                name: app.name,
                axIdentifier: attribute(kAXIdentifierAttribute, from: child),
                axTitle: attribute(kAXTitleAttribute, from: child))
            return AXItemRecord(source: source, frame: frame)
        }
    }

    private static func attribute<T>(_ name: String,
                                     from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
        else { return nil }
        return value as? T
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        MenuBarOrganizerSupport.accessibilityFrame(
            frame: attribute("AXFrame", from: element),
            position: attribute(kAXPositionAttribute, from: element),
            size: attribute(kAXSizeAttribute, from: element))
    }
}
