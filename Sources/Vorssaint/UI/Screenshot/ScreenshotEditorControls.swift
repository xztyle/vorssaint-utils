// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import AppKit

extension ScreenshotEditorView {
    var orderedTools: [ScreenshotSupport.Tool] {
        ScreenshotSupport.Tool.ordered(from: toolOrderRaw)
    }

    var toolRail: some View {
        VStack(spacing: 2) {
            ForEach(orderedTools, id: \.self) { tool in
                railButton(tool)
            }
            Divider()
                .frame(width: 22)
                .padding(.vertical, 2)
            Button {
                toolOptionsShown.toggle()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 33, height: 29)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(toolOptionsShown
                                    ? Color.accentColor.opacity(0.22) : .clear)
                    )
                    .foregroundStyle(toolOptionsShown ? Color.accentColor : Color.secondary)
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.borderless)
            .screenshotSafeHelp(strings.toolShortcutsTitle)
            .accessibilityLabel(strings.toolShortcutsTitle)
            .popover(isPresented: $toolOptionsShown, arrowEdge: .leading) {
                ScreenshotToolOrderControls(orderRaw: $toolOrderRaw,
                                            shortcutsEnabled: $toolShortcutsEnabled)
                    .padding(14)
                    .frame(width: 340)
            }
        }
        .padding(5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 5)
    }

    func railButton(_ tool: ScreenshotSupport.Tool) -> some View {
        let isActive = model.tool == tool
        let isHovered = hoveredTool == tool
        let shortcutLabel = ScreenshotSupport.Tool.shortcutLabel(
            for: tool, orderRaw: toolOrderRaw, bindingsRaw: bindingsRaw, enabled: toolShortcutsEnabled,
            capsLockOn: keyboard.capsLockOn)
        return Button {
            commitEditingTextIfNeeded()
            model.tool = tool
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: tool.screenshotSymbolName)
                    .font(.system(size: 13.5, weight: .medium))
                    .symbolEffect(.bounce, value: isActive)
                    .frame(width: 33, height: 29)
                if let shortcutLabel {
                    Text(shortcutLabel)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .fixedSize()
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                        .padding(2)
                        .opacity(isHovered || isActive ? 0.9 : 0.55)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive
                            ? Color.accentColor.opacity(0.22)
                            : isHovered ? Color.primary.opacity(0.08) : .clear)
            )
            .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.85))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .scaleEffect(isHovered && !isActive ? 1.06 : 1)
        }
        .buttonStyle(.borderless)
        .onHover { inside in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                hoveredTool = inside ? tool : (hoveredTool == tool ? nil : hoveredTool)
            }
        }
        .screenshotSafeHelp(tool.screenshotTitle(strings)
            + (shortcutLabel.map { "  (\($0))" } ?? ""))
        .accessibilityLabel(tool.screenshotTitle(strings)
            + (shortcutLabel.map { "  (\($0))" } ?? ""))
    }

    // MARK: - QR code (shown only when the capture holds one)

    /// Opens the shared result panel that spells out the code's content, with
    /// copy and open actions.
    var qrControl: some View {
        Button {
            controller.showQRResult()
        } label: {
            Image(systemName: "qrcode")
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .tint(.accentColor)
        .screenshotSafeHelp(l10n.s.qrResultTitle)
        .accessibilityLabel(l10n.s.qrResultTitle)
    }

    // MARK: - Action cluster (top right)

    var actionCluster: some View {
        HStack(spacing: 4) {
            Button {
                if controller.allowsExternalActions { RecentCaptureService.shared.showHistoryWindow() }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .screenshotSafeHelp(recentCapturesTitle)
            .accessibilityLabel(recentCapturesTitle)

            Divider().frame(height: 16).padding(.horizontal, 3)

            Button {
                controller.discardAndClose()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .screenshotSafeHelp(strings.discardConfirm)
            .accessibilityLabel(strings.discardConfirm)

            Divider().frame(height: 16).padding(.horizontal, 3)

            Button {
                commitEditingTextIfNeeded()
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!model.canUndo)
            Button {
                commitEditingTextIfNeeded()
                model.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!model.canRedo)

            if model.qrReading != nil {
                Divider().frame(height: 16).padding(.horizontal, 3)
                qrControl
                    .transition(.scale.combined(with: .opacity))
            }

            Divider().frame(height: 16).padding(.horizontal, 3)

            Button {
                commitEditingTextIfNeeded()
                controller.pin()
            } label: {
                Image(systemName: "pin")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .screenshotSafeHelp(strings.pinButton + "  (⌘P)")
            .accessibilityLabel(strings.pinButton)

            Divider().frame(height: 16).padding(.horizontal, 3)

            Button {
                commitEditingTextIfNeeded()
                guard let url = controller.shareFile() else {
                    NSSound.beep()
                    return
                }
                shareAnchor.present([url]) { chosen in
                    if chosen { model.markExported() }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .background(ShelfSharePickerAnchor(anchor: shareAnchor))
            .screenshotSafeHelp(strings.shareButton)
            .accessibilityLabel(strings.shareButton)

            if sharingEnabled, controller.allowsExternalActions {
                shareMenu
            }
            Divider().frame(height: 16).padding(.horizontal, 3)

            Menu {
                Button(strings.saveButton) {
                    commitEditingTextIfNeeded()
                    controller.save()
                }
                Button(strings.saveAsButton) {
                    commitEditingTextIfNeeded()
                    controller.saveAs()
                }
            } label: {
                Text(strings.saveButton)
            } primaryAction: {
                commitEditingTextIfNeeded()
                controller.save()
            }
            .fixedSize()
            .screenshotSafeHelp("⌘S")

            if controller.returnsToPreview {
                Button(strings.done) {
                    commitEditingTextIfNeeded()
                    controller.applyAndClose()
                }
                .buttonStyle(.borderedProminent)
                .screenshotSafeHelp("⏎")
            }
            Button(strings.copyButton) {
                commitEditingTextIfNeeded()
                controller.copyToClipboard()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!controller.allowsExternalActions)
            .screenshotSafeHelp("⌘C")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 14, y: 4)
    }

    var shareMenu: some View {
        Menu {
            ForEach(ScreenshotShareDuration.allCases) { duration in
                Button(duration.title(strings)) {
                    commitEditingTextIfNeeded()
                    sharing = true
                    controller.share(duration: duration) { record in
                        sharing = false
                        sharedRecord = record
                    }
                }
            }
        } label: {
            Group {
                if sharing {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "link")
                }
            }
            .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(sharing)
        .screenshotSafeHelp(sharing ? strings.sharingHUD : strings.shareSectionTitle)
        .accessibilityLabel(strings.shareSectionTitle)
    }

    // MARK: - Bottom row

    var infoChip: some View {
        HStack(spacing: 8) {
            dragOutHandle
            Text(dimensionsLabel)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    var zoomChip: some View {
        HStack(spacing: 3) {
            zoomButton(active: model.zoomOverride == nil, help: "⌘0") {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 11, weight: .medium))
            } action: {
                model.zoomOverride = nil
            }
            Text(zoomPercentLabel)
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 38)
                .lineLimit(1)
                .fixedSize()
            zoomButton(active: isActualZoom, help: "⌘1") {
                Text("1:1")
                    .font(.system(size: 11, weight: .medium))
            } action: {
                model.zoomOverride = 1 / model.scale
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .screenshotSafeHelp("⌃ scroll · ⌘+ ⌘-")
    }

    func zoomButton<Label: View>(active: Bool,
                                         help: String,
                                         @ViewBuilder label: () -> Label,
                                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
                .frame(width: 30, height: 20)
                .background(active ? Color.accentColor : .clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundStyle(active ? Color.white : Color.primary.opacity(0.85))
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.borderless)
        .screenshotSafeHelp(help)
    }

    var isActualZoom: Bool {
        guard let override = model.zoomOverride else { return false }
        return abs(override - 1 / model.scale) < 0.001
    }

    var zoomPercentLabel: String {
        let zoom = model.zoomOverride ?? model.currentDisplayZoom
        return "\(Int((zoom * model.scale * 100).rounded()))%"
    }

    var dimensionsLabel: String {
        let width = Int(model.imageSize.width)
        let height = Int(model.imageSize.height)
        let retina = model.scale > 1 ? "  @\(Int(model.scale))x" : ""
        return "\(width) × \(height) px\(retina)"
    }

    /// A draggable control that exports the flattened PNG. Lives in infoChip
    /// (bottom row), not the top toolbar — that region overlaps the
    /// window's real system title bar, where no subview-level override
    /// can reliably stop AppKit from treating a click as "move the
    /// window."
    var dragOutHandle: some View {
        Label(strings.dragOutHandleLabel, systemImage: "arrow.up.doc")
            .labelStyle(.iconOnly)
            .font(.system(size: 11, weight: .medium))
            .frame(width: 26, height: 18)
            .contentShape(Rectangle())
            .onDrag {
                commitEditingTextIfNeeded()
                guard let export = model.exportImage(),
                      let provider = controller.dragItemProvider(export)
                else { return NSItemProvider() }
                controller.commit(export)
                return provider
            }
            .screenshotSafeHelp(strings.dragOutHandleLabel)
            .accessibilityLabel(strings.dragOutHandleLabel)
    }}
