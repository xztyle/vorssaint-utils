// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct ScreenshotQuickPreviewView: View {
    let image: CGImage
    let strings: ScreenshotFeatureStrings
    @ObservedObject var model: ScreenshotQuickPreviewModel
    let perform: (ScreenshotQuickPreviewController.Action) -> Void
    let dragItem: () -> ScreenshotDragTransfer?
    let draggingChanged: (Bool) -> Void
    let swipingChanged: (Bool) -> Void
    let dismiss: () -> Void
    let share: (ScreenshotShareDuration) -> Void
    let systemShare: () -> Void
    let shareAnchor: ShelfSharePickerAnchor.Anchor
    let copySharedLink: () -> Void
    let deleteSharedLink: () -> Void
    let showQR: () -> Void
    let hoverChanged: (Bool) -> Void
    var embedded = false
    var actionsOnly = false
    var toolbar: Self {
        var view = self
        view.actionsOnly = true
        return view
    }
    @AppStorage(DefaultsKey.screenshotSharingEnabled) var sharingEnabled = true
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var floatingHovered = false
    @State var floatingDragging = false
    @State var floatingSwiping = false
    @State var trackingMenu: NSMenu?


    var body: some View {
        if actionsOnly { actionBar }
        else if embedded { preview }
        else { floatingPreview }
    }

    private var actionBar: some View {
        HStack(spacing: embedded ? 2 : 5) {
            Button {
                perform(.discard)
            } label: {
                Image(systemName: "trash")
                    .frame(width: embedded ? 28 : 22, height: embedded ? 28 : 18)
            }
            .modifier(ScreenshotPreviewActionStyle(embedded: embedded))
            .controlSize(.small)
            .screenshotSafeHelp("\(strings.discardConfirm)  (⌫)")
            .accessibilityLabel(strings.discardConfirm)
            if model.qr != nil {
                qrControl
                    .transition(.scale.combined(with: .opacity))
            }
            actionButton(symbol: "square.and.arrow.down",
                         title: strings.saveButton,
                         shortcut: "⌘S",
                         disabled: model.disabledActions.contains(.save)) {
                perform(.save)
            }
            actionButton(symbol: "doc.on.doc",
                         title: strings.copyButton,
                         shortcut: "⌘C",
                         disabled: model.disabledActions.contains(.copy)) {
                perform(.copy)
            }
            if embedded {
                Button(action: systemShare) {
                    Image(systemName: "square.and.arrow.up").frame(width: 28, height: 28)
                }
                .modifier(ScreenshotPreviewActionStyle(embedded: true))
                .controlSize(.small)
                .background(ShelfSharePickerAnchor(anchor: shareAnchor))
                .screenshotSafeHelp(strings.shareButton)
                .accessibilityLabel(strings.shareButton)
            }
            if sharingEnabled, model.sharedRecord == nil {
                shareMenu
            }
            if !embedded { Spacer(minLength: 4) }
            if embedded {
                Button {
                    perform(.pin)
                } label: {
                    Image(systemName: "pin").frame(width: 28, height: 28)
                }
                .modifier(ScreenshotPreviewActionStyle(embedded: true))
                .controlSize(.small)
                .screenshotSafeHelp(strings.pinButton)
                .accessibilityLabel(strings.pinButton)
            }
            Button { perform(.edit) } label: {
                if embedded { Image(systemName: "pencil").frame(width: 28, height: 28) }
                else { Text(strings.editButton) }
            }
            .accessibilityLabel(strings.editButton)
            .modifier(ScreenshotPreviewActionStyle(embedded: embedded, prominent: true))
            .controlSize(.small)
            .screenshotSafeHelp("\(strings.editButton)  (⏎)")
        }
    }

    private var thumbnailButtons: some View {
        HStack(spacing: 5) {
            thumbnailButton(symbol: "square.and.arrow.up", title: strings.shareButton,
                            action: systemShare)
                .background(ShelfSharePickerAnchor(anchor: shareAnchor))
            thumbnailButton(symbol: "pin", title: strings.pinButton) { perform(.pin) }
        }
        .padding(6)
    }

    private func thumbnailButton(symbol: String,
                                 title: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .screenshotSafeHelp(title)
        .accessibilityLabel(title)
    }

    private var preview: some View {
        VStack(spacing: 10) {
            Button {
                perform(.edit)
            } label: {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 138)
                    .frame(width: embedded ? nil : 320, height: 138)
                    .background(Color.black.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .overlay {
                ScreenshotPreviewDragSurface(image: image, transfer: dragItem,
                                             edit: { perform(.edit) }, dragging: draggingChanged)
            }
            .screenshotSafeHelp(strings.editButton)
            .accessibilityLabel(strings.editButton)
            .overlay(alignment: .topTrailing) {
                // The floating action row already fills its fixed width in
                // longer languages, so share and pin ride on the thumbnail
                // there instead of squeezing Save, Copy and Edit.
                if !embedded { thumbnailButtons }
            }

            if let record = model.sharedRecord {
                sharedLinkRow(record)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !embedded { actionBar }
        }
        .padding(10)
        .frame(width: embedded ? nil : ScreenshotQuickPreviewController.size(showingLink: false).width,
               height: embedded ? nil : ScreenshotQuickPreviewController.size(
                   showingLink: model.sharedRecord != nil).height)
        .background {
            if !embedded {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial)
            }
        }
        .overlay {
            if !embedded {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
        .onHover(perform: previewHoverChanged)
    }

    private func previewHoverChanged(_ inside: Bool) {
        // The island tracks the image and header together. Leaving just the
        // image must not restart dismissal while its actions are still hovered.
        guard !embedded else { return }
        hoverChanged(inside)
    }

    private func sharedLinkRow(_ record: ScreenshotShareRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.url.absoluteString)
                    .font(.system(size: 11, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: 3) {
                    Text(strings.expiresLabel)
                    Text(record.expiresAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Button(action: copySharedLink) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .disabled(model.deletingShare)
            .screenshotSafeHelp(strings.copyLink)
            .accessibilityLabel(strings.copyLink)
            Button(role: .destructive, action: deleteSharedLink) {
                Group {
                    if model.deletingShare {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "trash")
                    }
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .disabled(model.deletingShare)
            .screenshotSafeHelp(strings.deleteLink)
            .accessibilityLabel(strings.deleteLink)
        }
        .padding(.horizontal, 9)
        .frame(width: embedded ? nil : 320, height: 48)
        .background(Color.primary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        )
    }

    /// A code was found: open the result panel that spells out its content.
    private var qrControl: some View {
        Button(action: showQR) {
            Image(systemName: "qrcode")
                .frame(width: embedded ? 28 : 22, height: embedded ? 28 : 18)
        }
        .modifier(ScreenshotPreviewActionStyle(embedded: embedded))
        .controlSize(.small)
        .tint(.accentColor)
        .screenshotSafeHelp(L10n.shared.s.qrResultTitle)
        .accessibilityLabel(L10n.shared.s.qrResultTitle)
    }

    @ViewBuilder private var shareMenu: some View {
        if embedded {
            shareMenuContent.menuStyle(.borderlessButton).menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 28, height: 28)
        } else {
            shareMenuContent.menuStyle(.button).buttonStyle(.bordered).controlSize(.small)
        }
    }

    private var shareMenuContent: some View {
        Menu {
            ForEach(ScreenshotShareDuration.allCases) { duration in
                Button(duration.title(strings)) { share(duration) }
            }
        } label: {
            Group {
                if model.sharing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "link")
                }
            }
            .frame(width: embedded ? 28 : 22, height: embedded ? 28 : 18)
        }
        .disabled(model.sharing)
        .screenshotSafeHelp(model.sharing ? strings.sharingHUD : strings.shareSectionTitle)
        .accessibilityLabel(strings.shareSectionTitle)
    }

    private func actionButton(symbol: String,
                              title: String,
                              shortcut: String,
                              disabled: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if embedded { Image(systemName: symbol).frame(width: 28, height: 28) }
                else { Label(title, systemImage: symbol) }
            }
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .modifier(ScreenshotPreviewActionStyle(embedded: embedded))
        .controlSize(.small)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .screenshotSafeHelp("\(title)  (\(shortcut))")
        .accessibilityLabel(title)
    }
}

/// The island header has its own surface; native button bezels waste the space
/// needed by its title at the minimum width. Keep 28-point targets in that host.
private struct ScreenshotPreviewActionStyle: ViewModifier {
    let embedded: Bool
    var prominent = false

    @ViewBuilder func body(content: Content) -> some View {
        if embedded {
            content.buttonStyle(NotchButtonStyle(cornerRadius: 8))
                .background(prominent ? Color.white.opacity(0.14) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
