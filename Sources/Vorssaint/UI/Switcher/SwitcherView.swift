// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Content of the switcher panel: a grid of large window cards with live
/// thumbnails, hover/keyboard selection and an optional springy highlight.
struct SwitcherView: View {
    @EnvironmentObject private var switcher: AppSwitcher
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.minimalWindowPreviews) private var minimalPreviews = false
    @AppStorage(DefaultsKey.switcherIconRowMode) private var iconRowMode = false
    @AppStorage(DefaultsKey.switcherSimpleMode) private var simpleMode = false
    @AppStorage(DefaultsKey.switcherInstantSelection) private var instantSelection = false
    @AppStorage(DefaultsKey.switcherMergeTabs) private var mergeWindowsByApp = false
    @AppStorage(DefaultsKey.switcherShowShortcutHints) private var showsShortcutHints = true
    @AppStorage(DefaultsKey.switcherShortcut) private var switcherShortcutStorage = GlobalShortcut.switcherDefault.storageValue
    @AppStorage(DefaultsKey.switcherWindowShortcut) private var switcherWindowShortcutStorage = GlobalShortcut.switcherWindowDefault.storageValue

    var body: some View {
        if SwitcherSupport.usesIconRowLayout(iconRowMode: iconRowMode,
                                             simpleMode: simpleMode),
           !switcher.windows.isEmpty {
            iconRowPanel
        } else {
            standardPanel
        }
    }

    private var standardPanel: some View {
        Group {
            if switcher.windows.isEmpty {
                emptyState
            } else {
                cardGrid
            }
        }
        .padding(SwitcherGrid.padding)
        .background(HUDBackdrop(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topTrailing) {
            searchChip
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(minimalPreviews ? Color.clear : SwitcherIconStyle.stroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        if switcher.searchQuery.isEmpty {
            Text(l10n.s.switcherNoWindows)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(switcher.searchQuery)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: SwitcherGrid.cardWidth - 36)
                Text("0/\(switcher.totalWindowCount)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var iconRowPanel: some View {
        iconRowSwitcher
            .frame(width: iconRowPanelSize.width,
                   height: iconRowPanelSize.height,
                   alignment: .center)
            .overlay(alignment: .topTrailing) {
                searchChip
            }
    }

    @ViewBuilder
    private var searchChip: some View {
        if !switcher.searchQuery.isEmpty || switcher.isSearchPinned {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .bold))
                Text(switcher.searchQuery.isEmpty ? l10n.s.switcherSearchPin : switcher.searchQuery)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180)
                Text("\(switcher.windows.count)/\(switcher.totalWindowCount)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    // The label is `.primary`, so the chip under it has to turn
                    // over with the theme too: a fixed dark capsule left black
                    // text on a dark fill in the light appearance.
                    .fill(Color.primary.opacity(0.12))
            )
            .padding(12)
        }
    }

    private var cardGrid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(SwitcherGrid.cardWidth),
                                                       spacing: SwitcherGrid.spacing),
                                   count: switcher.grid.columns),
                    spacing: SwitcherGrid.spacing
                ) {
                    ForEach(Array(switcher.windows.enumerated()), id: \.element.id) { index, window in
                        WindowCard(window: window,
                                   preview: window.previewWindowID.flatMap { switcher.previews[$0] },
                                   isSelected: index == switcher.selectedIndex,
                                   animatesSelection: !instantSelection,
                                   onCommit: {
                                       switcher.select(index: index)
                                       switcher.commitSession()
                                   },
                                   onClose: {
                                       switcher.closeWindow(window)
                                   })
                            .id(window.id)
                            .onHover { hovering in
                                if hovering {
                                    switcher.hoverSelect(index: index)
                                } else {
                                    switcher.hoverSelectEnded(index: index)
                                }
                            }
                    }
                }
            }
            .scrollDisabled(switcher.grid.rows <= switcher.grid.visibleRows)
            .onChange(of: switcher.selectedIndex) { _, newIndex in
                guard switcher.windows.indices.contains(newIndex) else { return }
                withAnimation(instantSelection ? nil : .easeOut(duration: 0.15)) {
                    proxy.scrollTo(switcher.windows[newIndex].id, anchor: nil)
                }
            }
        }
    }

    private var iconRowSwitcher: some View {
        VStack(spacing: 0) {
            if simpleMode {
                if !usesWindowRow {
                    selectedAppTitlePanel
                    Spacer()
                        .frame(height: SwitcherIconRowLayout.simpleTitleGap)
                }
            } else {
                selectedAppPreviewPanel
                Spacer()
                    .frame(height: SwitcherIconRowLayout.previewGap)
            }
            iconRowSurface
            if showsShortcutHints {
                Spacer()
                    .frame(height: SwitcherIconRowLayout.hintGap)
                shortcutHintBar
            }
        }
        .padding(SwitcherIconRowLayout.padding)
    }

    private var iconRowPanelSize: CGSize {
        if usesWindowRow { return switcher.iconRowLayout.simpleWindowPanelSize }
        return simpleMode ? switcher.iconRowLayout.simplePanelSize : switcher.iconRowLayout.panelSize
    }

    private var usesWindowRow: Bool {
        SwitcherSupport.usesWindowRow(simpleMode: simpleMode,
                                      mergeWindowsByApp: mergeWindowsByApp,
                                      sessionScope: switcher.sessionScope)
    }

    private var shortcutHintBar: some View {
        let shortcut = GlobalShortcut(storageValue: switcherShortcutStorage) ?? .switcherDefault
        let windowShortcut = GlobalShortcut(storageValue: switcherWindowShortcutStorage) ?? .switcherWindowDefault
        let hints = SwitcherSupport.shortcutHints(for: shortcut, windowShortcut: windowShortcut)
        return HStack(spacing: 12) {
            if usesWindowRow {
                shortcutHint(label: l10n.s.switcherShortcutHintWindows, value: hints.apps)
            } else {
                shortcutHint(label: l10n.s.switcherShortcutHintApps, value: hints.apps)
                Divider()
                    .frame(height: 16)
                    .overlay(Color.primary.opacity(0.18))
                shortcutHint(label: l10n.s.switcherShortcutHintWindows, value: hints.windows)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: min(SwitcherIconRowLayout.hintBarWidth, iconRowContentWidth),
               height: SwitcherIconRowLayout.hintHeight)
        .background(
            Capsule(style: .continuous)
                .fill(SwitcherIconStyle.surfaceRaised)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(SwitcherIconStyle.stroke, lineWidth: 1)
        )
    }

    private func shortcutHint(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SwitcherIconStyle.secondaryText)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(SwitcherIconStyle.text)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private var selectedAppPreviewPanel: some View {
        if let selected = selectedWindow {
            let appWindows = selectedAppWindows
            let placement = selectedPreviewPlacement
            ZStack(alignment: .topLeading) {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        if let icon = selected.appIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                                .switcherHiddenAppBadge(selected.isAppHidden, size: 10)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(selected.appName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SwitcherIconStyle.text)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if let detail = selected.windowDetail(
                                noOpenWindow: l10n.s.switcherNoOpenWindow) {
                                Text(detail)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(SwitcherIconStyle.secondaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Spacer(minLength: 0)
                        Text("\(appWindows.count)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(SwitcherIconStyle.secondaryText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule(style: .continuous).fill(SwitcherIconStyle.tile))
                    }

                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SwitcherIconRowLayout.spacing) {
                                ForEach(appWindows, id: \.element.id) { index, window in
                                    SwitcherWindowPreviewTile(window: window,
                                                              preview: window.previewWindowID.flatMap { switcher.previews[$0] },
                                                              isSelected: index == switcher.selectedIndex,
                                                              instantSelection: instantSelection,
                                                              onCommit: {
                                                                  switcher.select(index: index)
                                                                  switcher.commitSession()
                                                              },
                                                              onClose: {
                                                                  switcher.closeWindow(window)
                                                              })
                                        .id(window.id)
                                        .onHover { hovering in
                                            if hovering {
                                                switcher.hoverSelect(index: index)
                                            } else {
                                                switcher.hoverSelectEnded(index: index)
                                            }
                                        }
                                    }
                                }
                            .frame(height: SwitcherIconRowLayout.previewCardHeight, alignment: .center)
                        }
                        .scrollDisabled(switcher.iconRowLayout.previewFitsWithoutScrolling(cardCount: appWindows.count))
                        .frame(width: switcher.iconRowLayout.previewContentWidth,
                               height: SwitcherIconRowLayout.previewCardHeight)
                        .onAppear { revealSelection(in: proxy, animated: false) }
                        .onChange(of: switcher.selectedIndex) { previous, selected in
                            revealSelection(in: proxy, animated: abs(selected - previous) == 1)
                        }
                        .onChange(of: appWindows.map(\.element.id)) { _, _ in
                            revealSelection(in: proxy, animated: false)
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in
                            DispatchQueue.main.async {
                                revealSelection(in: proxy, animated: false)
                            }
                        }
                    }
                    .id(appWindows.map(\.element.id))
                }
                .padding(SwitcherIconRowLayout.previewPanelPadding)
                .frame(width: switcher.iconRowLayout.previewSurfaceWidth,
                       height: SwitcherIconRowLayout.previewHeight)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(SwitcherIconStyle.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(minimalPreviews ? Color.clear : SwitcherIconStyle.stroke, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.24), radius: 10, x: 0, y: 5)
                .offset(x: placement.leading)
            }
            .frame(width: placement.contentWidth,
                   height: SwitcherIconRowLayout.previewHeight,
                   alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var selectedAppTitlePanel: some View {
        if let selected = selectedWindow {
            let appWindows = selectedAppWindows
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let icon = selected.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 18, height: 18)
                            .switcherHiddenAppBadge(selected.isAppHidden, size: 9)
                    }
                    Text(selected.appName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SwitcherIconStyle.text)
                        .lineLimit(1)
                    Text("\(appWindows.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SwitcherIconStyle.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(SwitcherIconStyle.tile))
                    if let detail = selected.windowDetail(
                        noOpenWindow: l10n.s.switcherNoOpenWindow) {
                        Text(detail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SwitcherIconStyle.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: SwitcherIconRowLayout.simpleTitleSpacing) {
                            ForEach(appWindows, id: \.element.id) { entry in
                                SwitcherWindowTitleChip(
                                    window: entry.element,
                                    isSelected: entry.offset == switcher.selectedIndex,
                                    onSelect: {
                                        switcher.select(index: entry.offset)
                                        switcher.commitSession()
                                    },
                                    onHover: { hovering in
                                        if hovering {
                                            switcher.hoverSelect(index: entry.offset)
                                        } else {
                                            switcher.hoverSelectEnded(index: entry.offset)
                                        }
                                    }
                                )
                                .id(entry.element.id)
                            }
                        }
                        .padding(.horizontal, SwitcherIconRowLayout.simpleTitleScrollPadding)
                    }
                    .onAppear { revealSelection(in: proxy, animated: false) }
                    .onChange(of: switcher.selectedIndex) { previous, selected in
                        revealSelection(in: proxy, animated: abs(selected - previous) == 1)
                    }
                    .onChange(of: appWindows.map(\.element.id)) { _, _ in
                        revealSelection(in: proxy, animated: false)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in
                        DispatchQueue.main.async {
                            revealSelection(in: proxy, animated: false)
                        }
                    }
                }
                .id(appWindows.map(\.element.id))
                .frame(height: 25 * SwitcherIconRowLayout.scale)
            }
            .padding(SwitcherIconRowLayout.simpleTitlePanelPadding)
            .frame(width: iconRowContentWidth,
                   height: SwitcherIconRowLayout.simpleTitleHeight,
                   alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(SwitcherIconStyle.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(SwitcherIconStyle.stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
        }
    }

    private var iconRowSurface: some View {
        iconRow
            .padding(.horizontal, SwitcherIconRowLayout.rowHorizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(SwitcherIconStyle.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(SwitcherIconStyle.stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 5)
            .frame(width: switcher.iconRowLayout.appRowSurfaceWidth,
                   height: SwitcherIconRowLayout.rowHeight)
    }

    @ViewBuilder
    private var iconRow: some View {
        if usesWindowRow {
            windowIconRow
        } else {
            appIconRow
        }
    }

    private var appIconRow: some View {
        let groups = appGroups
        let dividerPIDs = SwitcherSupport.windowlessAppDividerPIDs(items: switcher.windows)
        return overflowingIconRow(
            itemCount: groups.count,
            tileWidth: SwitcherIconRowLayout.appTileWidth
        ) {
            ForEach(groups) { group in
                let index = group.representativeIndex
                let window = switcher.windows[index]
                SwitcherIconTile(window: window,
                                 windowCount: group.windowCount,
                                 showsWindowTitle: false,
                                 isSelected: group.pid == selectedWindow?.pid,
                                 animatesSelection: !instantSelection,
                                 onCommit: {
                                     switcher.select(index: index)
                                     switcher.commitSession()
                                 })
                    .overlay(alignment: .leading) {
                        if dividerPIDs.contains(group.pid) {
                            Rectangle()
                                .fill(Color(nsColor: .separatorColor))
                                .frame(width: 1, height: SwitcherIconRowLayout.iconSize)
                                // Occupy the existing gap so scrolling and hit targets stay aligned.
                                .offset(x: -(SwitcherIconRowLayout.spacing + 1) / 2)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .onHover { hovering in
                        if hovering {
                            switcher.hoverSelectIconRow(index: index)
                        } else {
                            switcher.hoverSelectIconRowEnded(index: index)
                        }
                    }
            }
        }
    }

    private var windowIconRow: some View {
        overflowingIconRow(
            itemCount: switcher.windows.count,
            tileWidth: SwitcherIconRowLayout.windowTileWidth
        ) {
            ForEach(Array(switcher.windows.enumerated()), id: \.element.id) { index, window in
                SwitcherIconTile(
                    window: window,
                    windowCount: 1,
                    showsWindowTitle: true,
                    isSelected: index == switcher.selectedIndex,
                    animatesSelection: !instantSelection,
                    onCommit: {
                        switcher.select(index: index)
                        switcher.commitSession()
                    }
                )
                .onHover { hovering in
                    if hovering {
                        switcher.hoverSelectIconRow(index: index)
                    } else {
                        switcher.hoverSelectIconRowEnded(index: index)
                    }
                }
            }
        }
    }

    private func overflowingIconRow<Content: View>(itemCount: Int,
                                                   tileWidth: CGFloat,
                                                   @ViewBuilder content: () -> Content) -> some View {
        let overflow = itemCount > switcher.iconRowLayout.visibleIconCount
        return HStack(alignment: .center, spacing: SwitcherIconRowLayout.spacing) {
            content()
        }
        .frame(height: SwitcherIconRowLayout.rowHeight, alignment: .center)
        .offset(x: overflow ? iconRowOverflowOffset(tileWidth: tileWidth) : 0)
        .animation(instantSelection ? nil : .easeOut(duration: SwitcherSupport.iconRowEdgeHoverAnimationDuration),
                   value: switcher.iconRowFirstVisibleIndex)
        .frame(width: switcher.iconRowLayout.appRowContentWidth,
               height: SwitcherIconRowLayout.rowHeight,
               alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
    }

    private func iconRowOverflowOffset(tileWidth: CGFloat) -> CGFloat {
        let first = switcher.iconRowFirstVisibleIndex
        return -CGFloat(first) * (tileWidth + SwitcherIconRowLayout.spacing)
    }

    private var selectedWindow: SwitcherItem? {
        guard switcher.windows.indices.contains(switcher.selectedIndex) else { return nil }
        return switcher.windows[switcher.selectedIndex]
    }

    /// A search can resize the strip without moving the selection, and closing
    /// a window can replace the selected item at the same index. Reveal after
    /// the viewport's actual geometry changes, allowing its native scroll view
    /// to finish resizing before the queued reveal reads the current selection.
    /// Resize corrections are unanimated. SwiftUI before macOS 26 can also drop
    /// animated reveals during rapid navigation, so use immediate scrolling there.
    private func revealSelection(in proxy: ScrollViewProxy, animated: Bool) {
        let index = switcher.selectedIndex
        guard switcher.windows.indices.contains(index) else { return }
        let id = switcher.windows[index].id
        guard animated, !instantSelection, #available(macOS 26, *) else {
            proxy.scrollTo(id, anchor: .center)
            return
        }
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private var selectedAppWindows: [(offset: Int, element: SwitcherItem)] {
        guard let selectedWindow else { return [] }
        return Array(switcher.windows.enumerated()).filter { $0.element.pid == selectedWindow.pid }
    }

    private var appGroups: [SwitcherAppGroup] {
        SwitcherSupport.appGroups(items: switcher.windows)
    }

    private var iconRowContentWidth: CGFloat {
        switcher.iconRowLayout.contentWidth(simpleMode: simpleMode, windowRow: usesWindowRow)
    }

    private var selectedPreviewPlacement: SwitcherIconRowPreviewPlacement {
        let groups = appGroups
        let selectedIndex = selectedWindow
            .flatMap { selected in groups.firstIndex { $0.pid == selected.pid } }
            ?? 0
        return SwitcherSupport.selectedPreviewPlacement(
            appCount: groups.count,
            selectedAppIndex: selectedIndex,
            selectedWindowIndex: selectedAppWindows.firstIndex { $0.offset == switcher.selectedIndex } ?? 0,
            selectedWindowCount: selectedAppWindows.count,
            visibleIconCount: switcher.iconRowLayout.visibleIconCount,
            appRowContentWidth: switcher.iconRowLayout.appRowContentWidth,
            appRowSurfaceWidth: switcher.iconRowLayout.appRowSurfaceWidth,
            previewContentWidth: switcher.iconRowLayout.previewContentWidth,
            previewSurfaceWidth: switcher.iconRowLayout.previewSurfaceWidth
        )
    }
}
