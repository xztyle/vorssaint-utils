// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI
import Vision

/// Everything the annotation editor can do to one capture: the mutable
/// document (image, annotations, undo history) and the export paths. The
/// SwiftUI editor view observes this model; geometry is in image pixels.
final class ScreenshotEditorModel: ObservableObject, BackdropEditing {
    @Published var baseImage: CGImage
    @Published var annotations: [ScreenshotSupport.Annotation] = []
    @Published var selectedID: UUID?
    @Published var editingTextID: UUID?
    @Published var tool: ScreenshotSupport.Tool {
        didSet {
            preferences.set(tool.rawValue, forKey: DefaultsKey.screenshotLastTool)
            if tool != .select { clearTextSelection() }
            if tool != oldValue, tool != .select {
                selectedID = nil
                editingTextID = nil
            }
            if tool == .crop, oldValue != .crop {
                selectedID = nil
                cropDraft = CGRect(origin: .zero, size: imageSize)
            } else if oldValue == .crop {
                cropDraft = nil
                cropLoupePoint = nil
            }
        }
    }
    /// Words recognized in the capture and selectable with the select tool.
    @Published var textWords: [ScreenshotSupport.RecognizedWord] = []
    @Published var selectedWordIndexes: [Int] = []
    var textSelectionAnchor: CGPoint?
    /// A QR code found in the capture, offered as a copy or open action.
    @Published var qrReading: BarcodeDetector.Reading?
    @Published var color: ScreenshotSupport.ColorID {
        didSet {
            preferences.set(color.rawValue, forKey: DefaultsKey.screenshotLastColor)
            applyStyleToSelection()
        }
    }
    @Published var stroke: ScreenshotSupport.StrokeID {
        didSet {
            preferences.set(stroke.rawValue, forKey: DefaultsKey.screenshotLastStroke)
            applyStyleToSelection()
        }
    }
    @Published var textSize: Int {
        didSet {
            preferences.set(textSize, forKey: DefaultsKey.screenshotLastTextSize)
            applyStyleToSelection()
        }
    }
    @Published var blurLevel: Int {
        didSet {
            preferences.set(blurLevel, forKey: DefaultsKey.screenshotLastBlurLevel)
            applyBlurLevelToSelection()
        }
    }
    @Published var arrowStyle: ScreenshotSupport.ArrowStyleID {
        didSet {
            preferences.set(arrowStyle.rawValue,
                                      forKey: DefaultsKey.screenshotLastArrowStyle)
            applyStyleToSelection()
        }
    }
    @Published var sticker: ScreenshotSupport.StickerID {
        didSet {
            preferences.set(sticker.rawValue,
                                      forKey: DefaultsKey.screenshotLastSticker)
            applyStickerToSelection()
        }
    }
    @Published var annotationShadowsEnabled: Bool {
        didSet {
            preferences.set(annotationShadowsEnabled,
                                      forKey: DefaultsKey.screenshotAnnotationShadows)
            refreshDirtyState()
        }
    }
    /// The full backdrop configuration (kind, colors or image, margin and
    /// corner sliders), persisted as JSON and applied live on the canvas.
    @Published var backdropStyle: ScreenshotSupport.BackdropStyle {
        didSet {
            preferences.set(backdropStyle.encoded(),
                                      forKey: DefaultsKey.screenshotBackdropStyle)
            reloadBackdropImageIfNeeded()
            refreshDirtyState()
        }
    }
    /// Custom backdrops the user chose to keep.
    @Published var backdropPresets: [ScreenshotSupport.BackdropStyle] {
        didSet {
            preferences.set(
                ScreenshotSupport.encodedBackdropPresets(backdropPresets),
                forKey: DefaultsKey.screenshotBackdropPresets)
        }
    }
    /// Loaded image for an image-kind backdrop; nil when missing on disk,
    /// which quietly renders as no backdrop.
    @Published var backdropImage: CGImage?
    /// A mark of your own over the capture, persisted as JSON like the
    /// backdrop and applied live on the canvas.
    @Published var watermarkStyle: ScreenshotSupport.WatermarkStyle {
        didSet {
            preferences.set(watermarkStyle.encoded(),
                                      forKey: DefaultsKey.screenshotWatermarkStyle)
            reloadWatermarkImageIfNeeded()
            refreshDirtyState()
        }
    }
    /// Loaded picture for an image-kind watermark; nil when missing on disk,
    /// which quietly draws nothing.
    @Published var watermarkImage: CGImage?
    /// Watermarks the user chose to keep.
    @Published var watermarkPresets: [ScreenshotSupport.WatermarkStyle] {
        didSet {
            preferences.set(
                ScreenshotSupport.encodedWatermarkPresets(watermarkPresets),
                forKey: DefaultsKey.screenshotWatermarkPresets)
        }
    }
    @Published var cropDraft: CGRect?
    /// Exact image pixel under a crop resize grip. Nil while moving the
    /// whole crop so the loupe appears only when it adds precision.
    @Published var cropLoupePoint: CGPoint?
    /// Continuous zoom (view points per image pixel); nil fits the window.
    @Published var zoomOverride: CGFloat?
    /// What the view actually laid out last, so pinch and scroll zoom start
    /// from the visible scale even in fit mode. Plain var on purpose: the
    /// view writes it during layout.
    var currentDisplayZoom: CGFloat = 0.5
    @Published var canUndo = false
    @Published var canRedo = false
    /// True while there is work that never left the app: closing then asks.
    @Published var isDirty = false

    let preferences: UserDefaults
    let scale: CGFloat
    /// Sampled mosaics of the base image, one per blur level in use.
    var pixelated: [Int: CGImage] = [:]

    var undoStack: [(image: CGImage, annotations: [ScreenshotSupport.Annotation])] = []
    var redoStack: [(image: CGImage, annotations: [ScreenshotSupport.Annotation])] = []
    static let undoLimit = 60
    var cleanImage: CGImage?
    var cleanAnnotations: [ScreenshotSupport.Annotation] = []
    var cleanBackdropStyle = ScreenshotSupport.BackdropStyle()
    var cleanWatermarkStyle = ScreenshotSupport.WatermarkStyle()
    var cleanAnnotationShadowsEnabled = false

    // Gesture state, in image pixels.
    var dragStart: CGPoint = .zero
    var draftID: UUID?
    var moveOrigin: CGRect = .zero
    var movePoints: [CGPoint] = []
    var activeHandle: ScreenshotSupport.Handle?
    var cropResizeOrigin: CGRect?
    var cropMoveOrigin: CGRect?
    var cropSelectionOrigin: CGRect?
    var dragRegistered = false
    var editingSelectedAnnotation = false
    var newTextID: UUID?

    var imageSize: CGSize {
        CGSize(width: baseImage.width, height: baseImage.height)
    }

    /// Natural on-screen size in points (pixels over capture scale).
    var pointSize: CGSize {
        CGSize(width: CGFloat(baseImage.width) / scale, height: CGFloat(baseImage.height) / scale)
    }

    init(image: CGImage, scale: CGFloat, preferences: UserDefaults = .standard, flattened: Bool = false) {
        self.preferences = preferences
        baseImage = image
        self.scale = scale
        let defaults = preferences
        var lastTool = ScreenshotSupport.Tool(
            rawValue: defaults.string(forKey: DefaultsKey.screenshotLastTool) ?? "") ?? .arrow
        if lastTool == .select || lastTool == .crop { lastTool = .arrow }
        tool = lastTool
        color = ScreenshotSupport.ColorID.sanitized(
            defaults.string(forKey: DefaultsKey.screenshotLastColor))
        stroke = ScreenshotSupport.StrokeID.sanitized(
            defaults.string(forKey: DefaultsKey.screenshotLastStroke))
        textSize = ScreenshotSupport.sanitizedTextSize(
            defaults.integer(forKey: DefaultsKey.screenshotLastTextSize))
        blurLevel = ScreenshotSupport.BlurStrength.startingLevel(
            remembered: defaults.integer(forKey: DefaultsKey.screenshotLastBlurLevel))
        arrowStyle = ScreenshotSupport.ArrowStyleID.sanitized(
            defaults.string(forKey: DefaultsKey.screenshotLastArrowStyle))
        sticker = ScreenshotSupport.StickerID.sanitized(
            defaults.string(forKey: DefaultsKey.screenshotLastSticker))
        annotationShadowsEnabled = defaults.bool(
            forKey: DefaultsKey.screenshotAnnotationShadows)
        let rawStyle = defaults.string(forKey: DefaultsKey.screenshotBackdropStyle) ?? ""
        backdropStyle = flattened ? ScreenshotSupport.BackdropStyle(kind: .none, cornerRadius: 0)
            : ScreenshotSupport.BackdropStyle.decoded(rawStyle)
        backdropPresets = ScreenshotSupport.decodedBackdropPresets(
            defaults.string(forKey: DefaultsKey.screenshotBackdropPresets))
        watermarkStyle = flattened ? ScreenshotSupport.WatermarkStyle()
            : ScreenshotSupport.WatermarkStyle.decoded(
                defaults.string(forKey: DefaultsKey.screenshotWatermarkStyle))
        watermarkPresets = ScreenshotSupport.decodedWatermarkPresets(
            defaults.string(forKey: DefaultsKey.screenshotWatermarkPresets))
        pixelated = [:]
        reloadBackdropImageIfNeeded()
        reloadWatermarkImageIfNeeded()
        recordCleanState()
    }

    /// Backdrop margin in image pixels for the current settings; zero while
    /// the backdrop is off. The live canvas and the exporter share this.
    var backdropPaddingPixels: CGFloat {
        showsBackdrop
            ? ScreenshotSupport.backdropPadding(for: imageSize,
                                                factor: CGFloat(backdropStyle.padding))
            : 0
    }

    /// Corner rounding of the capture card in image pixels.
    var cardCornerPixels: CGFloat {
        ScreenshotSupport.cardCornerRadius(for: imageSize,
                                           factor: CGFloat(backdropStyle.cornerRadius))
    }

    /// True when something actually paints behind the capture (an image
    /// backdrop whose file vanished counts as nothing).
    var showsBackdrop: Bool {
        if case .none = backdropFill { return false }
        return true
    }

    /// The style resolved into what the renderer paints, shared by the live
    /// canvas and the exporter.
    var backdropFill: ScreenshotRenderer.BackdropFill {
        let style = backdropStyle.sanitized()
        switch style.kind {
        case .none:
            return .none
        case .preset:
            guard let id = style.presetID,
                  let preset = ScreenshotSupport.BackdropID(rawValue: id)
            else { return .none }
            return .colors(preset.stops)
        case .solid, .gradient:
            let colors = (style.colors ?? []).map {
                (red: $0[0], green: $0[1], blue: $0[2])
            }
            return colors.isEmpty ? .none : .colors(colors)
        case .image:
            guard let backdropImage else { return .none }
            return .image(backdropImage)
        }
    }

    func reloadBackdropImageIfNeeded() {
        guard backdropStyle.kind == .image, let path = backdropStyle.imagePath else {
            backdropImage = nil
            return
        }
        if backdropImage != nil, loadedBackdropPath == path { return }
        loadedBackdropPath = path
        backdropImage = Self.loadImageFile(path)
    }

    var loadedBackdropPath: String?

    /// True when a mark actually draws: text with something typed, or a
    /// picture that loaded.
    var showsWatermark: Bool {
        switch watermarkStyle.sanitized().kind {
        case .none: return false
        case .text: return true
        case .image: return watermarkImage != nil
        }
    }

    func reloadWatermarkImageIfNeeded() {
        guard watermarkStyle.kind == .image, let path = watermarkStyle.imagePath else {
            watermarkImage = nil
            return
        }
        if watermarkImage != nil, loadedWatermarkPath == path { return }
        loadedWatermarkPath = path
        watermarkImage = Self.loadImageFile(path)
    }

    var loadedWatermarkPath: String?

    /// Loads and caps a backdrop or watermark picture; wallpapers can be 6K
    /// and neither needs more than the export canvas.
    static func loadImageFile(_ path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - Backdrop presets

    /// Keeps the current custom backdrop (colors or image) in the presets
    /// row; duplicates are ignored.
    func saveCurrentBackdropAsPreset() {
        let style = backdropStyle.sanitized()
        guard style.kind != .none, style.kind != .preset else { return }
        var snapshot = style
        // A preset is the look, not this capture's sliders.
        snapshot.padding = 0.5
        snapshot.cornerRadius = 0.1
        snapshot.blur = 0
        guard !backdropPresets.contains(where: {
            var candidate = $0
            candidate.padding = 0.5
            candidate.cornerRadius = 0.1
            candidate.blur = 0
            return candidate == snapshot
        }) else { return }
        backdropPresets = Array((backdropPresets + [snapshot])
            .suffix(ScreenshotSupport.backdropPresetLimit))
    }

    func removeBackdropPreset(at index: Int) {
        guard backdropPresets.indices.contains(index) else { return }
        backdropPresets.remove(at: index)
    }

    // MARK: - Watermark presets

    /// Keeps the current mark, placement and all, in the presets row;
    /// duplicates are ignored.
    func saveCurrentWatermarkAsPreset() {
        let style = watermarkStyle.sanitized()
        guard style.kind != .none, !watermarkPresets.contains(style) else { return }
        watermarkPresets = Array((watermarkPresets + [style])
            .suffix(ScreenshotSupport.backdropPresetLimit))
    }

    func removeWatermarkPreset(at index: Int) {
        guard watermarkPresets.indices.contains(index) else { return }
        watermarkPresets.remove(at: index)
    }

    // MARK: - Selectable text on the canvas

    var selectedText: String {
        ScreenshotSupport.joinedWords(textWords, selected: selectedWordIndexes)
    }

    func clearTextSelection() {
        textSelectionAnchor = nil
        if !selectedWordIndexes.isEmpty { selectedWordIndexes = [] }
    }

    func wordIndex(at point: CGPoint) -> Int? {
        textWords.firstIndex { $0.rect.insetBy(dx: -2 * scale, dy: -2 * scale).contains(point) }
    }

    /// Word-level recognition of the base capture, off the main thread; the
    /// boxes land in image pixels with their line index.
    func recognizeText() {
        let image = baseImage
        let width = CGFloat(image.width)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var words: [ScreenshotSupport.RecognizedWord] = []
            let maximumTilePixels = 12_000_000
            let tileHeight = min(image.height,
                                 max(512, min(4096,
                                     maximumTilePixels / max(image.width, 1))))
            var tileY = 0
            var lineOffset = 0
            while tileY < image.height {
                guard let current = self, image === current.baseImage else { return }
                let currentHeight = min(tileHeight, image.height - tileY)
                guard let tile = image.cropping(to: CGRect(x: 0,
                                                           y: tileY,
                                                           width: image.width,
                                                           height: currentHeight))
                else { break }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                let handler = VNImageRequestHandler(cgImage: tile, options: [:])
                try? handler.perform([request])
                let observations = request.results ?? []
                for (line, observation) in observations.enumerated() {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let text = candidate.string
                    var searchStart = text.startIndex
                    for raw in text.split(separator: " ") {
                        let word = String(raw)
                        guard let range = text.range(of: word,
                                                   range: searchStart..<text.endIndex),
                              let box = try? candidate.boundingBox(for: range)?.boundingBox
                        else { continue }
                        searchStart = range.upperBound
                        let rect = CGRect(x: box.minX * width,
                                          y: CGFloat(tileY)
                                            + (1 - box.maxY) * CGFloat(currentHeight),
                                          width: box.width * width,
                                          height: box.height * CGFloat(currentHeight))
                        words.append(ScreenshotSupport.RecognizedWord(
                            text: word,
                            rect: rect,
                            line: lineOffset + line))
                    }
                }
                lineOffset += observations.count
                tileY += currentHeight
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, image === self.baseImage else { return }
                self.textWords = words
            }
        }
    }

    /// Scans the capture for a QR code off the main thread; the result drives
    /// the copy or open action in the toolbar. Re-run whenever the base image
    /// changes (crop, undo) so a cropped out code stops being offered.
    func recognizeQRCodes() {
        let image = baseImage
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let current = self, image === current.baseImage else { return }
            let reading = BarcodeDetector.read(image)
            DispatchQueue.main.async { [weak self] in
                guard let self, image === self.baseImage else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self.qrReading = reading
                }
            }
        }
    }

    // MARK: - Zoom

    static let zoomRange: ClosedRange<CGFloat> = 0.05...3

    /// Multiplies the current zoom (pinch, ⌃ scroll, ⌘ plus and minus).
    func adjustZoom(by factor: CGFloat) {
        let current = zoomOverride ?? currentDisplayZoom
        zoomOverride = min(max(current * factor, Self.zoomRange.lowerBound),
                           Self.zoomRange.upperBound)
    }

    /// Absolute zoom for pinch gestures anchored at the gesture's start.
    func setZoom(_ zoom: CGFloat) {
        zoomOverride = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    // MARK: - Undo

    func registerUndo() {
        undoStack.append((baseImage, annotations))
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        refreshUndoFlags()
        isDirty = true
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append((baseImage, annotations))
        restore(last)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append((baseImage, annotations))
        restore(next)
    }

    func restore(_ state: (image: CGImage, annotations: [ScreenshotSupport.Annotation])) {
        if state.image !== baseImage {
            baseImage = state.image
            pixelated = [:]
            clearTextSelection()
            recognizeText()
            recognizeQRCodes()
        }
        annotations = state.annotations
        ensurePixelatedForAnnotations()
        selectedID = nil
        editingTextID = nil
        newTextID = nil
        cropDraft = nil
        refreshUndoFlags()
        refreshDirtyState()
    }

    func refreshUndoFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func markExported() {
        recordCleanState()
    }

    func recordCleanState() {
        cleanImage = baseImage
        cleanAnnotations = annotations
        cleanBackdropStyle = backdropStyle.sanitized()
        cleanWatermarkStyle = watermarkStyle.sanitized()
        cleanAnnotationShadowsEnabled = annotationShadowsEnabled
        isDirty = false
    }

    func refreshDirtyState() {
        guard let cleanImage else { return }
        isDirty = baseImage !== cleanImage
            || annotations != cleanAnnotations
            || backdropStyle.sanitized() != cleanBackdropStyle
            || watermarkStyle.sanitized() != cleanWatermarkStyle
            || annotationShadowsEnabled != cleanAnnotationShadowsEnabled
    }

    // MARK: - Selection styling

    /// Applies color, thickness, text size, or arrow style changes to the
    /// selected annotation.
    func applyStyleToSelection() {
        guard let selectedID,
              let index = annotations.firstIndex(where: { $0.id == selectedID })
        else { return }
        let arrowStyleChanged = annotations[index].tool == .arrow
            && annotations[index].arrowStyle != arrowStyle
        let textSizeChanged = annotations[index].tool == .text
            && annotations[index].textSize != textSize
        // Marks without a thickness control keep theirs, so picking one never
        // records an edit nobody made.
        let usesStroke = ScreenshotSupport.selectionStyle(for: annotations[index]).stroke != nil
        let strokeChanged = usesStroke && annotations[index].stroke != stroke
        guard annotations[index].color != color
                || strokeChanged
                || arrowStyleChanged
                || textSizeChanged
        else { return }
        registerUndo()
        annotations[index].color = color
        if usesStroke { annotations[index].stroke = stroke }
        if annotations[index].tool == .arrow {
            if arrowStyleChanged, arrowStyle == .scribbly {
                annotations[index].scribbleSeed = ScreenshotSupport.randomScribbleSeed()
            }
            annotations[index].arrowStyle = arrowStyle
        }
        if annotations[index].tool == .text {
            annotations[index].textSize = textSize
            annotations[index].rect = ScreenshotRenderer.textBounds(
                annotations[index].text,
                at: annotations[index].rect.origin,
                textSize: textSize,
                scale: scale)
        }
    }

    func applyBlurLevelToSelection() {
        guard let selectedID,
              let index = annotations.firstIndex(where: { $0.id == selectedID }),
              annotations[index].tool == .pixelate,
              annotations[index].blurLevel != blurLevel
        else { return }
        // The mosaic must exist before the mark points at it, or the redraw
        // would show the area uncovered; without one the area keeps its level.
        ensurePixelated(level: blurLevel)
        guard pixelated[blurLevel] != nil else {
            blurLevel = annotations[index].blurLevel
            return
        }
        registerUndo()
        annotations[index].blurLevel = blurLevel
        ensurePixelatedForAnnotations()
    }

    func applyStickerToSelection() {
        guard let selectedID,
              let index = annotations.firstIndex(where: { $0.id == selectedID }),
              annotations[index].tool == .sticker,
              annotations[index].text != sticker.rawValue
        else { return }
        registerUndo()
        annotations[index].text = sticker.rawValue
    }

    /// Copies only the controls that have meaning for the picked annotation.
    /// Unused values remain available as defaults for the next new mark.
    func syncControls(to annotation: ScreenshotSupport.Annotation) {
        let style = ScreenshotSupport.selectionStyle(for: annotation)
        if let color = style.color { self.color = color }
        if let stroke = style.stroke { self.stroke = stroke }
        if let textSize = style.textSize { self.textSize = textSize }
        if let blurLevel = style.blurLevel { self.blurLevel = blurLevel }
        if let arrowStyle = style.arrowStyle { self.arrowStyle = arrowStyle }
        if annotation.tool == .sticker {
            sticker = ScreenshotSupport.StickerID.sanitized(annotation.text)
        }
    }

    // MARK: - Edits

    func deleteSelected() {
        guard let selectedID else { return }
        guard annotations.contains(where: { $0.id == selectedID }) else { return }
        registerUndo()
        annotations.removeAll { $0.id == selectedID }
        annotations = ScreenshotSupport.renumberingCounters(annotations)
        self.selectedID = nil
        editingTextID = nil
        if newTextID == selectedID { newTextID = nil }
    }

    /// Moves the selected annotation one step through the drawing order, so a
    /// box drawn last can sit behind text written first. Counters are numbered
    /// by their place in the array, so moving one past another renumbers both,
    /// the same way deleting one already does.
    func moveSelected(_ move: ScreenshotSupport.LayerMove) {
        guard let selectedID else { return }
        let reordered = ScreenshotSupport.reordering(annotations, moving: selectedID, move)
        guard reordered.map(\.id) != annotations.map(\.id) else { return }
        registerUndo()
        annotations = ScreenshotSupport.renumberingCounters(reordered)
    }

    func commitText(_ id: UUID, text: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        editingTextID = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNew = newTextID == id
        if isNew, trimmed.isEmpty {
            annotations.remove(at: index)
            if selectedID == id { selectedID = nil }
            while let last = undoStack.last,
                  last.annotations.contains(where: { $0.id == id }) {
                undoStack.removeLast()
            }
            if !undoStack.isEmpty { undoStack.removeLast() }
            newTextID = nil
            refreshUndoFlags()
            refreshDirtyState()
            return
        }
        guard annotations[index].text != trimmed else {
            newTextID = nil
            return
        }
        if !isNew { registerUndo() }
        guard !trimmed.isEmpty else {
            annotations.remove(at: index)
            if selectedID == id { selectedID = nil }
            return
        }
        annotations[index].text = trimmed
        annotations[index].rect = ScreenshotRenderer.textBounds(
            trimmed,
            at: annotations[index].rect.origin,
            textSize: annotations[index].textSize,
            scale: scale)
        newTextID = nil
    }

    func applyCrop() {
        guard let draft = cropDraft else {
            tool = .select
            return
        }
        let cropRect = ScreenshotSupport.pixelSnappedCropRect(
            draft,
            within: CGRect(origin: .zero, size: imageSize))
        guard cropRect.width >= 8, cropRect.height >= 8,
              let cropped = baseImage.cropping(to: cropRect)
        else {
            tool = .select
            return
        }
        registerUndo()
        baseImage = cropped
        pixelated = [:]
        clearTextSelection()
        textWords = textWords.compactMap { word in
            let moved = word.rect.offsetBy(dx: -cropRect.minX, dy: -cropRect.minY)
            guard moved.intersects(CGRect(origin: .zero, size: CGSize(width: cropped.width,
                                                                      height: cropped.height)))
            else { return nil }
            return ScreenshotSupport.RecognizedWord(text: word.text, rect: moved, line: word.line)
        }
        annotations = annotations.map { annotation in
            var moved = annotation
            moved.rect = annotation.rect.offsetBy(dx: -cropRect.minX, dy: -cropRect.minY)
            moved.points = annotation.points.map {
                CGPoint(x: $0.x - cropRect.minX, y: $0.y - cropRect.minY)
            }
            return moved
        }
        ensurePixelatedForAnnotations()
        cropDraft = nil
        selectedID = nil
        tool = .select
        recognizeText()
        recognizeQRCodes()
    }

    // MARK: - Output

    func exportImage(withBackdrop: Bool = true) -> ScreenshotRenderer.Export? {
        ensurePixelatedForAnnotations()
        let downscale = preferences.bool(forKey: DefaultsKey.screenshotDownscale)
        return ScreenshotRenderer.renderExport(
            baseImage: baseImage,
            annotations: annotations,
            pixelated: pixelated,
            scale: scale,
            annotationShadowsEnabled: annotationShadowsEnabled,
            watermark: watermarkStyle,
            watermarkImage: watermarkImage,
            style: backdropStyle.sanitized(),
            fill: withBackdrop ? backdropFill : .none,
            downscaleTo1x: downscale)
    }

    func ensurePixelated(level: Int) {
        guard pixelated[level] == nil,
              let mosaic = ScreenshotRenderer.pixelatedImage(from: baseImage, level: level)
        else { return }
        pixelated[level] = mosaic
    }

    /// Keeps a sampled mosaic for each level in use and drops the rest.
    func ensurePixelatedForAnnotations() {
        let levels = ScreenshotSupport.mosaicLevels(for: annotations)
        pixelated = pixelated.filter { levels.contains($0.key) }
        for level in levels { ensurePixelated(level: level) }
    }
}
