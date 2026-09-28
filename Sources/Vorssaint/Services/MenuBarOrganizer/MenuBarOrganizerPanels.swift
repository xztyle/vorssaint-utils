// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit
import SwiftUI

@MainActor
final class MenuBarOrganizerPanelController: ObservableObject {
    weak var service: MenuBarOrganizerService?
    private var panel: MenuBarSearchPanel?
    private var keyMonitor: Any?
    private var outsideMonitor: Any?
    @Published var query = ""
    @Published var selection = 0
    @Published var search = false
    @Published var includeAlwaysHidden = false

    init(service: MenuBarOrganizerService) { self.service = service }
    var isVisible: Bool { panel?.isVisible == true }

    var results: [ManagedMenuBarItem] {
        guard let service else { return [] }
        return MenuBarSearchSupport.results(service.items, query: query, searchAll: search,
                                            includeAlwaysHidden: includeAlwaysHidden)
    }

    func show(anchor: CGRect?, search: Bool, includeAlwaysHidden: Bool) {
        guard let service, service.entryAllowed else { return }
        self.search = search
        self.includeAlwaysHidden = includeAlwaysHidden
        query = ""
        selection = 0
        let screen = service.activeScreen ?? NSScreen.main
        let size = CGSize(width: min(520, (screen?.visibleFrame.width ?? 600) - 24),
                          height: min(480, (screen?.visibleFrame.height ?? 600) - 24))
        let panel = self.panel ?? makePanel(size: size)
        panel.contentViewController = NSHostingController(rootView: MenuBarOrganizerBrowser(service: service, controller: self))
        panel.setContentSize(size)
        position(panel, screen: screen, anchor: anchor)
        self.panel = panel
        installMonitors()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        keyMonitor = nil
        outsideMonitor = nil
    }

    func select(_ offset: Int) { selection = min(max(0, selection + offset), max(0, results.count - 1)) }

    func activateSelection() {
        guard results.indices.contains(selection), results[selection].identityState == .stable else { return }
        service?.activate(itemID: results[selection].id)
    }

    private func makePanel(size: CGSize) -> MenuBarSearchPanel {
        let panel = MenuBarSearchPanel(contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hidesOnDeactivate = false
        return panel
    }

    private func position(_ panel: NSPanel, screen: NSScreen?, anchor: CGRect?) {
        guard let screen else { panel.center(); return }
        let visible = screen.visibleFrame
        let center = anchor.flatMap { screen.frame.intersects($0) ? $0.midX : nil } ?? screen.frame.midX
        let top = min(visible.maxY, screen.frame.maxY - screen.safeAreaInsets.top)
        let x = min(max(center - panel.frame.width / 2, visible.minX + 8), visible.maxX - panel.frame.width - 8)
        panel.setFrameOrigin(CGPoint(x: x, y: top - panel.frame.height - 8))
    }

    private func installMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self, isVisible else { return event }
            if event.type == .leftMouseDown, event.window != panel { close(); return event }
            guard event.type == .keyDown, event.window == panel else { return event }
            switch event.keyCode {
            case 53: close(); return nil
            case 125: select(1); return nil
            case 126: select(-1); return nil
            case 36, 76: activateSelection(); return nil
            default: return event
            }
        }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }
}

private final class MenuBarSearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct MenuBarOrganizerBrowser: View {
    @ObservedObject var service: MenuBarOrganizerService
    @ObservedObject var controller: MenuBarOrganizerPanelController
    @ObservedObject var l10n = L10n.shared
    @FocusState private var focused: Bool
    private var extra: MenuBarProductStrings { .localized(l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField(extra.search, text: $controller.query).textFieldStyle(.plain).focused($focused)
                Button { controller.close() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel(l10n.s.mediaCancel)
            }.padding(16)
            Divider()
            browserList
            Divider()
            Text(extra.keyboardHint).font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .background(.regularMaterial)
        .onAppear { focused = true }
        .onChange(of: controller.query) { _, _ in controller.selection = 0 }
    }

    private var browserList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    if controller.results.isEmpty { Text(extra.noResults).foregroundStyle(.secondary).padding(30) }
                    ForEach(Array(controller.results.enumerated()), id: \.element.windowID) { index, item in
                        resultRow(item, index: index).id(index)
                    }
                }.padding(8)
            }
            .onChange(of: controller.selection) { _, value in proxy.scrollTo(value, anchor: .center) }
        }
    }

    private func resultRow(_ item: ManagedMenuBarItem, index: Int) -> some View {
        Button { service.activate(itemID: item.id) } label: {
            MenuBarOrganizerItemLabel(item: item, showsSection: true)
                .padding(9).contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(index == controller.selection ? Color.accentColor.opacity(0.18) : Color.clear))
        }
        .buttonStyle(.plain)
        .disabled(item.identityState != .stable)
        .accessibilityLabel(item.displayName)
        .help(item.identityState == .stable ? item.displayName : service.text.unresolvedItem)
    }
}

struct MenuBarOrganizerItemLabel: View {
    let item: ManagedMenuBarItem
    var showsSection = false
    var body: some View {
        HStack(spacing: 10) {
            MenuBarOrganizerItemIcon(item: item, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).lineLimit(1)
                if showsSection {
                    Text(item.section.localizedTitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if item.identityState == .provisional { Image(systemName: "questionmark.circle").foregroundStyle(.orange) }
            else if !item.isMovable { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
        }
    }
}

struct MenuBarOrganizerItemIcon: View {
    let item: ManagedMenuBarItem
    let size: CGFloat
    var body: some View {
        Group {
            if let image = item.image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "app.dashed").resizable().scaledToFit().foregroundStyle(.secondary) }
        }.frame(width: size, height: size)
    }
}

extension MenuBarOrganizerSection {
    var localizedTitle: String {
        let strings = FeatureStrings.menuBarOrganizer(L10n.shared.language)
        switch self {
        case .visible: return strings.visible
        case .hidden: return strings.hidden
        case .alwaysHidden: return strings.alwaysHidden
        }
    }
}

