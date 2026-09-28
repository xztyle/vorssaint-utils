// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Draws the production Features page without running services or showing a window.
enum FeatureHubLayoutTests {
    final class FeatureRuntime: ObservableObject {
        static let shared = FeatureRuntime()
        let needsRestartToUnload = false
        var availableCount: Int { AppFeature.allCases.filter(\.isAvailable).count }
        var installableCount: Int { AppFeature.allCases.count }
        func setAllAvailable(_ available: Bool) {}
        func setAvailable(_ features: [AppFeature], _ available: Bool) {}
        func apply(_ preset: FeaturePreset) {}
        func relaunchApp() {}
    }
    struct PermissionsPortalSections: View {
        let hub: FeatureHubStrings
        var body: some View { EmptyView() }
    }
    struct NavigationHost: View {
        @ObservedObject private var router = SettingsRouter.shared
        var body: some View {
            NavigationSplitView {
                List { Text("Features") }
                    .navigationSplitViewColumnWidth(min: 198, ideal: 210, max: 240)
            } detail: {
                GeometryReader { geometry in
                    Group {
                        if router.page == .features { FeatureHubSettings() }
                        else { Text("About") }
                    }
                    .settingsSectionFocus(for: router.page)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                }
            }
            .navigationSplitViewStyle(.balanced)
        }
    }

    static func run(_ suite: TestSuite) {
        FeatureHubNavigationContract.run(suite)
        let defaults = UserDefaults.standard
        let saved = AppFeature.allCases.map { ($0.availabilityKey, defaults.object(forKey: $0.availabilityKey)) }
        let installed: Set<AppFeature> = [.clipboardHistory, .keepAwake, .mixer, .monitorCPU,
                                          .monitorGPU, .monitorDisk, .monitorMemory, .monitorNetwork, .monitorPower]
        for feature in AppFeature.allCases { defaults.set(installed.contains(feature), forKey: feature.availabilityKey) }
        defer { for (key, value) in saved { defaults.set(value, forKey: key) } }
        checkLayout(suite, width: 772)
        checkLayout(suite, width: 1_050)
    }

    private static func checkLayout(_ suite: TestSuite, width: CGFloat) {
        SettingsRouter.shared.page = .about
        let host = NSHostingView(rootView: NavigationHost())
        host.frame = NSRect(x: 0, y: 0, width: width, height: 839)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close(); SettingsRouter.shared.page = .about }
        host.layoutSubtreeIfNeeded()
        let started = ProcessInfo.processInfo.systemUptime
        SettingsRouter.shared.request(FeatureSettingsDestination(.features), targetFeature: .screenshot)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        suite.expect(SettingsRouter.shared.pendingFeatureTarget == nil, "Features consumes Screenshot target at width \(width)")
        suite.expect(ProcessInfo.processInfo.systemUptime - started < 5, "Features target layout stays bounded at width \(width)")
        suite.expect(host.fittingSize.width.isFinite, "Features layout has finite width")
    }
}

extension AppFeature {
    var installBlockedReason: String? { nil }
}

/// Executes the real reveal methods with recorded scrolling and a deterministic queue.
enum FeatureHubNavigationContract {
    enum DispatchQueue {
        static let main = Queue()
        final class Queue {
            var pending: [() -> Void] = []
            func async(execute: @escaping () -> Void) { pending.append(execute) }
            func asyncAfter(deadline: DispatchTime, execute: @escaping () -> Void) { pending.append(execute) }
            func drain() { while !pending.isEmpty { pending.removeFirst()() } }
        }
    }
    final class ScrollViewProxy {
        var targets: [AnyHashable] = []
        func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint?) { targets.append(AnyHashable(id)) }
    }
    class Fixture {
        enum Tab { case features, permissions }
        let router = SettingsRouter()
        var tab = Tab.permissions
        var revealID = UUID()
        var highlightedFeature: AppFeature?
        var expandedGroups = Set<FeatureGroup>()
        var islandExtensionsExpanded = false
        var reduceMotion = true
        var animatedScrolls = 0
        var disabledAnimationTransactions = 0
        func withTransaction(_ transaction: Transaction, _ body: () -> Void) {
            if transaction.animation != nil { animatedScrolls += 1 }
            if transaction.disablesAnimations { disabledAnimationTransactions += 1 }
            body()
        }
    }

    static func run(_ suite: TestSuite) {
        let host = Host(), proxy = ScrollViewProxy()
        host.router.request(FeatureSettingsDestination(.features), targetFeature: .screenshot)
        host.revealPendingFeatureTarget(using: proxy)
        suite.expect(host.tab == .features && host.expandedGroups.contains(.tools), "search opens and expands the requested feature group")
        suite.expect(proxy.targets.isEmpty, "feature jump waits for expanded content to lay out")
        DispatchQueue.main.drain()
        suite.expect(proxy.targets == [AnyHashable(AppFeature.screenshot)], "one search makes exactly one row jump without competing retries")
        suite.expect(host.animatedScrolls == 0 && host.disabledAnimationTransactions == 1, "distant feature jumps disable inherited scroll animations")
        suite.expect(host.highlightedFeature == nil, "feature highlight clears after the jump")
        staleRequest(suite)
    }

    private static func staleRequest(_ suite: TestSuite) {
        let host = Host(), proxy = ScrollViewProxy()
        for feature in [AppFeature.screenshot, .notchAgents] {
            host.router.request(FeatureSettingsDestination(.features), targetFeature: feature)
            host.revealPendingFeatureTarget(using: proxy)
        }
        DispatchQueue.main.drain()
        suite.expect(proxy.targets == [AnyHashable(AppFeature.notchAgents)], "new navigation jumps only once to the latest feature row")
        suite.expect(host.islandExtensionsExpanded, "targeted Dynamic Island extension expands before scrolling")
    }
}
