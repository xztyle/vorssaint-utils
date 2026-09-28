// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

enum SwitcherIconStyle {
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceRaised = Color(nsColor: .windowBackgroundColor)
    static let tile = Color.primary.opacity(0.045)
    static let tileSelected = Color.accentColor.opacity(0.15)
    static let stroke = Color.primary.opacity(0.12)
    static let text = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color.secondary.opacity(0.72)
    static let thumbnailBackground = Color.primary.opacity(0.055)
}

private struct SwitcherHiddenAppBadge: ViewModifier {
    let isHidden: Bool
    let size: CGFloat

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            if isHidden {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color.black.opacity(0.72)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.68), lineWidth: 1))
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func switcherHiddenAppBadge(_ isHidden: Bool, size: CGFloat) -> some View {
        modifier(SwitcherHiddenAppBadge(isHidden: isHidden, size: size))
    }
}

struct SwitcherWindowTitleChip: View {
    let window: SwitcherItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: 4) {
            if window.isMinimized {
                Image(systemName: "minus.rectangle")
                    .font(.system(size: 9, weight: .semibold))
            }
            if window.isOnHiddenSpace {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(window.windowLabel(noOpenWindow: l10n.s.switcherNoOpenWindow))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
        .foregroundStyle(isSelected ? SwitcherIconStyle.text : SwitcherIconStyle.secondaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: SwitcherIconRowLayout.simpleTitleChipMaxWidth)
        .background(
            Capsule(style: .continuous)
                .fill(isSelected ? SwitcherIconStyle.tileSelected : SwitcherIconStyle.tile)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.9) : SwitcherIconStyle.stroke,
                              lineWidth: isSelected ? 1.15 : 1)
        )
        .contentShape(Capsule(style: .continuous))
        .onTapGesture(perform: onSelect)
        .onHover(perform: onHover)
        .accessibilityLabel(window.spokenLabel(noOpenWindow: l10n.s.switcherNoOpenWindow,
                                               hiddenApp: l10n.s.panelHiddenItem,
                                               otherDesktop: l10n.s.switcherOtherDesktop))
    }
}

struct SwitcherIconTile: View {
    let window: SwitcherItem
    let windowCount: Int
    let showsWindowTitle: Bool
    let isSelected: Bool
    let animatesSelection: Bool
    let onCommit: () -> Void

    @ObservedObject private var l10n = L10n.shared

    private var title: String {
        showsWindowTitle ? window.displayTitle : window.appName
    }

    private var labelWidth: CGFloat {
        showsWindowTitle ? SwitcherIconRowLayout.windowLabelWidth
                         : SwitcherIconRowLayout.iconLabelWidth
    }

    private var spokenLabel: String {
        if showsWindowTitle {
            return window.spokenLabel(noOpenWindow: l10n.s.switcherNoOpenWindow,
                                      hiddenApp: l10n.s.panelHiddenItem,
                                      otherDesktop: l10n.s.switcherOtherDesktop)
        }
        var label = window.appName
        if window.isAppHidden { label += ", \(l10n.s.panelHiddenItem)" }
        if windowCount == 1, window.isOnHiddenSpace {
            label += ", \(l10n.s.switcherOtherDesktop)"
        }
        return label
    }

    var body: some View {
        VStack(spacing: SwitcherIconRowLayout.iconTileSpacing) {
            ZStack(alignment: .topTrailing) {
                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: isSelected ? SwitcherIconRowLayout.selectedIconSize : SwitcherIconRowLayout.iconSize,
                               height: isSelected ? SwitcherIconRowLayout.selectedIconSize : SwitcherIconRowLayout.iconSize)
                        .switcherHiddenAppBadge(window.isAppHidden, size: 18)
                }
                if windowCount > 1 {
                    Text("\(windowCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(Color.accentColor))
                        .offset(x: -2, y: 2)
                } else if window.isOnHiddenSpace {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 18, height: 16)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor))
                        .offset(x: 1, y: -1)
                } else if window.isMinimized || window.isFullscreen {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 12, height: 12)
                        .offset(x: 1, y: -1)
                }
            }
            .frame(width: SwitcherIconRowLayout.selectedIconSize,
                   height: SwitcherIconRowLayout.selectedIconSize,
                   alignment: .bottom)
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? SwitcherIconStyle.text : SwitcherIconStyle.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: labelWidth,
                       height: SwitcherIconRowLayout.iconTitleHeight)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, SwitcherIconRowLayout.iconTileVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? SwitcherIconStyle.tileSelected : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.92) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onCommit)
        .scaleEffect(isSelected ? 1 : 0.96)
        .animation(animatesSelection ? .spring(response: 0.24, dampingFraction: 0.82) : nil,
                   value: isSelected)
        .accessibilityLabel(spokenLabel)
    }
}

struct SwitcherWindowPreviewTile: View {
    let window: SwitcherItem
    let preview: CGImage?
    let isSelected: Bool
    let instantSelection: Bool
    let onCommit: () -> Void
    let onClose: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.minimalWindowPreviews) private var minimalPreviews = false
    @State private var isHovering = false
    @State private var isCloseHovering = false
    @State private var suppressNextCommit = false

    private var hasStatusBadges: Bool {
        window.isMinimized || window.isFullscreen || window.isOnHiddenSpace
    }

    private var showsCloseButton: Bool {
        !minimalPreviews && isHovering && window.windowID != nil
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(minimalPreviews ? Color.clear : SwitcherIconStyle.thumbnailBackground)

                if let preview {
                    Image(decorative: preview, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(5)
                } else if window.isAppEntry, let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: SwitcherIconRowLayout.appEntryIconSize,
                               height: SwitcherIconRowLayout.appEntryIconSize)
                        .switcherHiddenAppBadge(window.isAppHidden, size: 18)
                } else if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .switcherHiddenAppBadge(window.isAppHidden, size: 20)
                }

                if !minimalPreviews && hasStatusBadges {
                    VStack {
                        Spacer()
                        HStack(spacing: 5) {
                            statusBadges
                            Spacer()
                        }
                        .padding(7)
                    }
                }

                VStack {
                    HStack {
                        closeButton
                            .padding(5)
                        Spacer()
                    }
                    Spacer()
                }
            }
            .frame(width: SwitcherIconRowLayout.previewCardWidth - 16,
                   height: SwitcherIconRowLayout.previewCardHeight - (minimalPreviews ? 16 : 38))

            // The header above already names the app. A window with no name of
            // its own would only say it again under its own thumbnail, and two
            // such windows would say it twice, which tells nobody anything.
            if !minimalPreviews, let detail = window.windowDetail(noOpenWindow: l10n.s.switcherNoOpenWindow) {
                Text(detail)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? SwitcherIconStyle.text : SwitcherIconStyle.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: SwitcherIconRowLayout.previewCardWidth - 20)
            }
        }
        .padding(8)
        .frame(width: SwitcherIconRowLayout.previewCardWidth,
               height: SwitcherIconRowLayout.previewCardHeight)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? SwitcherIconStyle.tileSelected : (minimalPreviews ? Color.clear : SwitcherIconStyle.tile))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.9) : (minimalPreviews ? Color.clear : SwitcherIconStyle.stroke),
                              lineWidth: isSelected ? 1.25 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            guard !suppressNextCommit else { return }
            onCommit()
        }
        .onHover { isHovering = $0 }
        .animation(instantSelection ? nil : .easeOut(duration: 0.12), value: showsCloseButton)
        .accessibilityLabel(window.spokenLabel(noOpenWindow: l10n.s.switcherNoOpenWindow,
                                               hiddenApp: l10n.s.panelHiddenItem,
                                               otherDesktop: l10n.s.switcherOtherDesktop))
    }

    @ViewBuilder
    private var closeButton: some View {
        if showsCloseButton {
            Button {
                suppressNextCommit = true
                onClose()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    suppressNextCommit = false
                }
            } label: {
                Image(systemName: isCloseHovering ? "xmark.circle.fill" : "xmark.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isCloseHovering ? SwitcherIconStyle.text : SwitcherIconStyle.secondaryText)
            .help(l10n.s.dockPreviewCloseWindow)
            .accessibilityLabel(l10n.s.dockPreviewCloseWindow)
            .onHover { isCloseHovering = $0 }
        }
    }

    private var statusBadges: some View {
        HStack(spacing: 4) {
            if window.isMinimized {
                statusBadge(systemName: "minus.rectangle")
            }
            if window.isFullscreen {
                statusBadge(systemName: "arrow.up.left.and.arrow.down.right")
            }
            if window.isOnHiddenSpace {
                statusBadge(systemName: "rectangle.stack")
            }
        }
    }

    private func statusBadge(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.9))
            .frame(width: 20, height: 18)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.46))
            )
            .accessibilityHidden(true)
    }
}

struct WindowCard: View {
    let window: SwitcherItem
    let preview: CGImage?
    let isSelected: Bool
    let animatesSelection: Bool
    let onCommit: () -> Void
    let onClose: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.minimalWindowPreviews) private var minimalPreviews = false
    @State private var isHovering = false
    @State private var isCloseHovering = false
    @State private var suppressNextCommit = false

    private var showsCloseButton: Bool {
        !minimalPreviews && isHovering && window.windowID != nil
    }

    private var hasStatusBadges: Bool {
        window.isMinimized || window.isFullscreen || window.isOnHiddenSpace
    }

    /// Without a thumbnail the app icon already fills the card, so the small
    /// corner badge would only repeat it.
    private var showsAppBadge: Bool {
        preview != nil
    }

    private static let appBadgeSize: CGFloat = 32
    /// App artwork is drawn on the system icon grid, which leaves a clear
    /// margin around it (measured at 9.4% of the side on every app checked).
    /// The frame hangs past the row by that much so the artwork itself, and
    /// not its empty margin, lines up with the card edge and with the status
    /// badges across the row.
    private static let appBadgeArtworkInset: CGFloat = (appBadgeSize * 0.094).rounded()

    var body: some View {
        VStack(spacing: SwitcherGridCard.titleSpacing) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(minimalPreviews ? Color.clear : Color.white.opacity(0.06))

                if let preview {
                    Image(decorative: preview, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(5)
                } else if window.isAppEntry {
                    appEntryMark
                } else if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: SwitcherGridCard.fallbackIconSize,
                               height: SwitcherGridCard.fallbackIconSize)
                        .switcherHiddenAppBadge(window.isAppHidden, size: 22 * PreviewSizing.switcherScale)
                }

                // One row along the bottom of the thumbnail: the app on the
                // left, the window's state on the right, sharing a baseline.
                if !minimalPreviews && (showsAppBadge || hasStatusBadges) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        HStack(alignment: .bottom, spacing: 8) {
                            if showsAppBadge, let icon = window.appIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: Self.appBadgeSize, height: Self.appBadgeSize)
                                    .shadow(radius: 3)
                                    .switcherHiddenAppBadge(window.isAppHidden, size: 12)
                                    .padding(.leading, -Self.appBadgeArtworkInset)
                                    .padding(.bottom, -Self.appBadgeArtworkInset)
                            }
                            Spacer(minLength: 0)
                            if hasStatusBadges {
                                HStack(spacing: 5) {
                                    statusBadges
                                }
                            }
                        }
                        .padding(7)
                    }
                }

                VStack {
                    HStack {
                        closeButton
                            .padding(6)
                        Spacer()
                    }
                    Spacer()
                }
            }
            .frame(width: SwitcherGridCard.thumbnailWidth,
                   height: SwitcherGridCard.thumbnailHeight
                       + (minimalPreviews ? SwitcherGridCard.titleSpacing + SwitcherGridCard.titleHeight : 0))

            if !minimalPreviews {
                VStack(spacing: 2) {
                    ScrollingTitle(text: window.displayTitle,
                                   weight: isSelected ? .semibold : .regular,
                                   width: SwitcherGridCard.titleWidth,
                                   alignment: .center,
                                   scrolls: isHovering)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    if let subtitle = window.displaySubtitle {
                        Text(subtitle)
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(height: SwitcherGridCard.titleHeight, alignment: .top)
                .frame(maxWidth: SwitcherGridCard.titleWidth)
            }
        }
        .padding(SwitcherGridCard.padding)
        .frame(width: SwitcherGridCard.width, height: SwitcherGridCard.height)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            guard !suppressNextCommit else { return }
            onCommit()
        }
        .onHover { isHovering = $0 }
        .scaleEffect(isSelected ? 1.0 : 0.97)
        .animation(animatesSelection ? .spring(response: 0.25, dampingFraction: 0.8) : nil,
                   value: isSelected)
        .accessibilityLabel(window.spokenLabel(noOpenWindow: l10n.s.switcherNoOpenWindow,
                                               hiddenApp: l10n.s.panelHiddenItem,
                                               otherDesktop: l10n.s.switcherOtherDesktop))
    }

    /// An app with no window has nothing to take a thumbnail of. Saying so
    /// under a larger icon is what separates this card from a capture that did
    /// not arrive, which is exactly what a lone icon in an empty well reads as.
    private var appEntryMark: some View {
        VStack(spacing: 9) {
            if let icon = window.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 84 * PreviewSizing.switcherScale, height: 84 * PreviewSizing.switcherScale)
                    .switcherHiddenAppBadge(window.isAppHidden, size: 22 * PreviewSizing.switcherScale)
            }
            Text(l10n.s.switcherNoOpenWindow)
                .font(.system(size: 11 * PreviewSizing.switcherScale, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var statusBadges: some View {
        if window.isMinimized {
            statusBadge(systemName: "minus.rectangle")
        }
        if window.isFullscreen {
            statusBadge(systemName: "arrow.up.left.and.arrow.down.right")
        }
        if window.isOnHiddenSpace {
            statusBadge(systemName: "rectangle.stack")
        }
    }

    private func statusBadge(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.9))
            .frame(width: 22, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.46))
            )
            .accessibilityHidden(true)
    }

    private var closeButton: some View {
        Button {
            suppressNextCommit = true
            onClose()
            DispatchQueue.main.async {
                suppressNextCommit = false
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 19, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white.opacity(isCloseHovering ? 0.95 : 0.72),
                                 Color(red: 1.0, green: 0.38, blue: 0.33).opacity(isCloseHovering ? 1 : 0.92))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(showsCloseButton ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: showsCloseButton)
        .allowsHitTesting(showsCloseButton)
        .onHover { isCloseHovering = $0 }
        .help(l10n.s.dockPreviewCloseWindow)
        .accessibilityLabel(l10n.s.dockPreviewCloseWindow)
    }
}
