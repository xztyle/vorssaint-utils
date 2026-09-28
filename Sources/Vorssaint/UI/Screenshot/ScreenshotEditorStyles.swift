// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import AppKit

extension ScreenshotEditorView {
    var showsColorControls: Bool {
        switch model.tool {
        case .arrow, .line, .rect, .ellipse, .freehand, .highlight, .text, .counter, .redact:
            return true
        case .select:
            guard let selectedID = model.selectedID,
                  let selected = model.annotations.first(where: { $0.id == selectedID })
            else { return false }
            return selected.tool != .sticker
                && selected.tool != .pixelate
        case .sticker, .pixelate, .crop:
            return false
        }
    }

    var showsBlurControls: Bool {
        if model.tool == .pixelate { return true }
        guard model.tool == .select,
              let selectedID = model.selectedID,
              let selected = model.annotations.first(where: { $0.id == selectedID })
        else { return false }
        return selected.tool == .pixelate
    }

    /// Text takes a point size where shapes take a thickness.
    var showsTextSizeControls: Bool {
        if model.tool == .text { return true }
        guard model.tool == .select,
              let selectedID = model.selectedID,
              let selected = model.annotations.first(where: { $0.id == selectedID })
        else { return false }
        return selected.tool == .text
    }

    var showsArrowStyleControls: Bool {
        if model.tool == .arrow { return true }
        guard model.tool == .select,
              let selectedID = model.selectedID,
              let selected = model.annotations.first(where: { $0.id == selectedID })
        else { return false }
        return selected.tool == .arrow
    }

    /// Depth only means something once a shape is picked, and only when there
    /// is something else for it to pass.
    var showsLayerControls: Bool {
        model.selectedID != nil && model.annotations.count > 1
    }

    /// Each direction dims on its own once the shape reaches that end, so the
    /// buttons never offer a move that would do nothing.
    func canMoveSelected(_ move: ScreenshotSupport.LayerMove) -> Bool {
        guard let selectedID = model.selectedID else { return false }
        return ScreenshotSupport.canReorder(model.annotations, moving: selectedID, move)
    }

    func layerButton(_ move: ScreenshotSupport.LayerMove,
                             symbol: String,
                             label: String) -> some View {
        Button {
            commitEditingTextIfNeeded()
            model.moveSelected(move)
        } label: {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .disabled(!canMoveSelected(move))
        .screenshotSafeHelp(label)
        .accessibilityLabel(label)
    }

    var showsStickerControls: Bool {
        if model.tool == .sticker { return true }
        guard model.tool == .select,
              let selectedID = model.selectedID,
              let selected = model.annotations.first(where: { $0.id == selectedID })
        else { return false }
        return selected.tool == .sticker
    }

    var bottomRow: some View {
        // One row, no stacking: the chips can never collide with the style
        // bar on a narrow window.
        HStack(alignment: .center, spacing: 10) {
            infoChip
            Spacer(minLength: 6)
            if model.tool == .crop, model.cropDraft != nil {
                cropBar
            } else {
                styleBar
            }
            Spacer(minLength: 6)
            zoomChip
        }
    }

    var styleBar: some View {
        HStack(spacing: 10) {
            if showsArrowStyleControls {
                arrowStyleMenu
                Divider().frame(height: 16)
            }
            if showsStickerControls {
                stickerMenu
                Divider().frame(height: 16)
            }
            if showsBlurControls {
                blurLevelControl
                Divider().frame(height: 16)
            }
            if showsColorControls {
                HStack(spacing: 4) {
                    ForEach(ScreenshotSupport.ColorID.allCases, id: \.self) { colorID in
                        colorDot(colorID)
                    }
                }
                Divider().frame(height: 16)
                if showsTextSizeControls {
                    textSizeControl
                } else {
                    HStack(spacing: 3) {
                        ForEach(ScreenshotSupport.StrokeID.allCases, id: \.self) { stroke in
                            strokeGlyph(stroke)
                        }
                    }
                }
                Divider().frame(height: 16)
            }
            if showsLayerControls {
                layerButton(.backward, symbol: "square.2.layers.3d.bottom.filled",
                            label: strings.sendBackward)
                layerButton(.forward, symbol: "square.2.layers.3d.top.filled",
                            label: strings.bringForward)
                Divider().frame(height: 16)
            }
            annotationShadowButton
            Divider().frame(height: 16)
            backdropButton
            Divider().frame(height: 16)
            watermarkButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 12, y: 3)
    }

    /// The same kind of menu as the sticker picker: an inline picker gives
    /// each style a native row with a checkmark, and the sample images come
    /// from the editor's own renderer, so the menu shows exactly what draws.
    var arrowStyleMenu: some View {
        Menu {
            Picker(strings.arrowStyleLabel, selection: $model.arrowStyle) {
                ForEach(ScreenshotSupport.ArrowStyleID.allCases, id: \.self) { style in
                    Label {
                        Text(strings.arrowStyleTitle(style))
                    } icon: {
                        Image(nsImage: ScreenshotArrowStyleSamples.image(for: style))
                    }
                    .tag(style)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 5) {
                Image(nsImage: ScreenshotArrowStyleSamples.image(for: model.arrowStyle))
                    .renderingMode(.template)
                Text(strings.arrowStyleTitle(model.arrowStyle))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .frame(height: 24)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .screenshotSafeHelp(strings.arrowStyleLabel)
        .accessibilityLabel(strings.arrowStyleLabel)
    }

    var stickerMenu: some View {
        Menu {
            ForEach(ScreenshotSupport.StickerID.allCases, id: \.self) { sticker in
                Button {
                    model.sticker = sticker
                } label: {
                    HStack {
                        Text(sticker.glyph)
                        if model.sticker == sticker {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(model.sticker.glyph)
                    .font(.system(size: 16))
                Text(strings.toolSticker)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .frame(height: 24)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .screenshotSafeHelp(strings.toolSticker)
        .accessibilityLabel(strings.toolSticker)
    }

    var cropBar: some View {
        HStack(spacing: 8) {
            Button(strings.cancel) {
                model.tool = .select
            }
            Button(strings.cropApply) {
                model.applyCrop()
            }
            .buttonStyle(.borderedProminent)
            .screenshotSafeHelp("⏎")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 3)
    }

    func colorDot(_ colorID: ScreenshotSupport.ColorID) -> some View {
        let selected = model.color == colorID
        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
                model.color = colorID
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color(nsColor: ScreenshotRenderer.nsColor(colorID)))
                    .frame(width: 17, height: 17)
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(0.22), lineWidth: 0.5)
                    )
                if selected {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.9), lineWidth: 1.5)
                        .frame(width: 23, height: 23)
                }
            }
            .frame(width: 24, height: 24)
            .scaleEffect(selected ? 1.05 : 1)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(strings.colorLabel)
    }

    /// Line-weight glyphs with three increasing stroke widths.
    func strokeGlyph(_ stroke: ScreenshotSupport.StrokeID) -> some View {
        let selected = model.stroke == stroke
        let height: CGFloat = switch stroke {
        case .small: 1.8
        case .medium: 3.4
        case .large: 5.4
        }
        return Button {
            model.stroke = stroke
        } label: {
            Capsule()
                .fill(selected ? Color.accentColor : Color.primary.opacity(0.6))
                .frame(width: 15, height: height)
                .frame(width: 25, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.18) : .clear)
                )
        }
        .buttonStyle(.borderless)
        .screenshotSafeHelp(strings.strokeLabel)
        .accessibilityLabel(strings.strokeLabel)
    }

    /// Smaller and larger buttons step through the presets; the menu jumps
    /// straight to any of them.
    var textSizeControl: some View {
        HStack(spacing: 1) {
            textSizeStepButton(up: false)
            Menu {
                Picker(strings.fontSizeLabel, selection: $model.textSize) {
                    ForEach(ScreenshotSupport.textSizes, id: \.self) { size in
                        Text("\(size) pt").tag(size)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text("\(model.textSize) pt")
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .frame(height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            textSizeStepButton(up: true)
        }
        .screenshotSafeHelp(strings.fontSizeLabel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(strings.fontSizeLabel)
    }

    /// Five steps from a light blur to a heavy one; the middle is the
    /// strength the tool always had.
    var blurLevelControl: some View {
        let levels = ScreenshotSupport.BlurStrength.levels
        return HStack(spacing: 5) {
            Image(systemName: "aqi.low")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(model.blurLevel) },
                                  set: { model.blurLevel = Int($0.rounded()) }),
                   in: Double(levels.lowerBound)...Double(levels.upperBound),
                   step: 1)
                .controlSize(.mini)
                .frame(width: 84)
            Image(systemName: "aqi.high")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(height: 24)
        .screenshotSafeHelp(strings.blurStrengthLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(strings.blurStrengthLabel)
        .accessibilityValue("\(model.blurLevel)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.blurLevel = min(levels.upperBound, model.blurLevel + 1)
            case .decrement: model.blurLevel = max(levels.lowerBound, model.blurLevel - 1)
            @unknown default: break
            }
        }
    }

    func textSizeStepButton(up: Bool) -> some View {
        let next = ScreenshotSupport.steppedTextSize(from: model.textSize, up: up)
        return Button {
            if let next { model.textSize = next }
        } label: {
            Image(systemName: up ? "textformat.size.larger" : "textformat.size.smaller")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .disabled(next == nil)
        .accessibilityLabel(strings.fontSizeLabel + (up ? " +" : " −"))
    }

    var annotationShadowButton: some View {
        Button {
            model.annotationShadowsEnabled.toggle()
        } label: {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 25, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(model.annotationShadowsEnabled
                                ? Color.accentColor.opacity(0.20) : .clear)
                )
                .foregroundStyle(model.annotationShadowsEnabled
                                    ? Color.accentColor : Color.primary.opacity(0.65))
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.borderless)
        .screenshotSafeHelp(strings.shadowLabel)
        .accessibilityLabel(strings.shadowLabel)
        .accessibilityAddTraits(model.annotationShadowsEnabled ? .isSelected : [])
    }

    var backdropButton: some View {
        // A plain view with an explicit tap gesture: every point of the
        // control opens the popover, swatch included, with a hover wash so
        // it reads as one button.
        HStack(spacing: 6) {
            Group {
                switch model.backdropStyle.sanitized().kind {
                case .none:
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.85))
                case .image:
                    Image(systemName: "photo.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.85))
                case .preset, .solid, .gradient:
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(fillPreview(for: model.backdropStyle))
                        .frame(width: 21, height: 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                        )
                }
            }
            Text(strings.backdropLabel)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(backdropButtonHovered ? Color.primary.opacity(0.10) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { inside in backdropButtonHovered = inside }
        .onTapGesture { backdropPopoverShown.toggle() }
        .screenshotSafeHelp(strings.backdropLabel)
        .accessibilityLabel(strings.backdropLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { backdropPopoverShown.toggle() }
        .popover(isPresented: $backdropPopoverShown, arrowEdge: .top) {
            ScreenshotBackdropPopover(model: model)
        }
    }


    var watermarkButton: some View {
        // Built like the backdrop button: one tappable surface with a hover
        // wash, tinted while a mark is actually on the capture.
        let active = model.showsWatermark
        return HStack(spacing: 6) {
            Image(systemName: "signature")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : Color.primary.opacity(0.85))
            Text(strings.watermarkLabel)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(watermarkButtonHovered ? Color.primary.opacity(0.10) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { inside in watermarkButtonHovered = inside }
        .onTapGesture { watermarkPopoverShown.toggle() }
        .screenshotSafeHelp(strings.watermarkLabel)
        .accessibilityLabel(strings.watermarkLabel)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { watermarkPopoverShown.toggle() }
        .popover(isPresented: $watermarkPopoverShown, arrowEdge: .top) {
            ScreenshotWatermarkPopover(model: model)
        }
    }


    func fillPreview(for style: ScreenshotSupport.BackdropStyle) -> LinearGradient {
        let colors = BackdropPickerAssets.previewColors(for: style)
        return LinearGradient(colors: colors,
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Corner chips

}
