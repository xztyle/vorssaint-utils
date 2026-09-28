// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

extension ScreenshotQuickPreviewView {
    private var floatingSize: CGSize {
        ScreenshotPreviewPolicy.floatingSize(image: CGSize(width: image.width, height: image.height))
    }
    private var imageSize: CGSize {
        ScreenshotPreviewPolicy.imageSize(CGSize(width: image.width, height: image.height))
    }
    private var showsFloatingActions: Bool {
        ScreenshotPreviewPolicy.showsActions(hovered: floatingHovered,
            menuTracking: trackingMenu != nil, dragging: floatingDragging)
    }

    var floatingPreview: some View {
        floatingImage
            .frame(width: floatingSize.width, height: floatingSize.height, alignment: .bottomLeading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if showsFloatingActions { floatingActions.padding(4).transition(.opacity) }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: showsFloatingActions)
            .onHover(perform: floatingHoverChanged)
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification), perform: menuBegan)
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification), perform: menuEnded)
    }

    private var floatingImage: some View {
        Image(decorative: image, scale: 1)
            .resizable().interpolation(.high)
            .frame(width: imageSize.width, height: imageSize.height)
            .overlay {
                ScreenshotPreviewDragSurface(image: image, transfer: dragItem,
                    edit: { perform(.edit) }, dragging: floatingDragChanged, dismiss: dismiss)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(strings.pageTitle)
            .accessibilityAction(named: Text(strings.editButton)) { perform(.edit) }
            .accessibilityAction(named: Text(strings.copyButton)) { perform(.copy) }
            .accessibilityAction(named: Text(strings.saveButton)) { perform(.save) }
            .accessibilityAction(named: Text(L10n.shared.s.menuClose), dismiss)
    }

    private var floatingActions: some View {
        ViewThatFits(in: .horizontal) {
            floatingActionRow(compact: false)
            floatingActionRow(compact: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func floatingActionRow(compact: Bool) -> some View {
        HStack(spacing: 2) {
            if !compact { floatingButton("xmark", L10n.shared.s.menuClose, action: dismiss) }
            floatingButton("pencil", strings.editButton) { perform(.edit) }
            floatingButton("doc.on.doc", strings.copyButton, disabled: model.disabledActions.contains(.copy)) { perform(.copy) }
            if !compact {
                floatingButton("square.and.arrow.down", strings.saveButton,
                               disabled: model.disabledActions.contains(.save)) { perform(.save) }
            }
            floatingMoreMenu
        }
        .padding(4)
        .fixedSize()
        .background(HUDBackdrop(cornerRadius: 11, contrast: .high))
    }

    private func floatingButton(_ symbol: String, _ title: String, disabled: Bool = false,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(.primary)
        .disabled(disabled).opacity(disabled ? 0.45 : 1)
        .screenshotSafeHelp(title).accessibilityLabel(title)
    }

    private var floatingMoreMenu: some View {
        Menu {
            Button(strings.saveButton) { perform(.save) }.disabled(model.disabledActions.contains(.save))
            Button(strings.pinButton) { perform(.pin) }
            Button(strings.shareButton, action: systemShare)
            if model.qr != nil { Button(L10n.shared.s.qrResultTitle, action: showQR) }
            floatingLinkActions
            Divider()
            Button(L10n.shared.s.menuClose, action: dismiss)
            Button(strings.discardConfirm, role: .destructive) { perform(.discard) }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .background(ShelfSharePickerAnchor(anchor: shareAnchor))
        .accessibilityLabel(FeatureStrings.recorder(L10n.shared.language).moreOptions)
    }

    @ViewBuilder private var floatingLinkActions: some View {
        if model.sharedRecord != nil {
            Button(strings.copyLink, action: copySharedLink).disabled(model.deletingShare)
            Button(strings.deleteLink, role: .destructive, action: deleteSharedLink).disabled(model.deletingShare)
        } else if sharingEnabled {
            Menu(strings.shareSectionTitle) {
                ForEach(ScreenshotShareDuration.allCases) { duration in
                    Button(duration.title(strings)) { share(duration) }
                }
            }.disabled(model.sharing)
        }
    }

    private func floatingHoverChanged(_ inside: Bool) {
        floatingHovered = inside
        hoverChanged(inside || trackingMenu != nil)
    }

    private func floatingDragChanged(_ value: Bool) {
        floatingDragging = value
        draggingChanged(value)
    }

    private func menuBegan(_ notification: Notification) {
        guard floatingHovered, let menu = notification.object as? NSMenu else { return }
        trackingMenu = menu
        hoverChanged(true)
    }

    private func menuEnded(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu, menu === trackingMenu else { return }
        trackingMenu = nil
        hoverChanged(floatingHovered)
    }
}
