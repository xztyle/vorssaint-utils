// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

extension ScreenshotEditorModel {
    // MARK: - Gestures (image-pixel coordinates)

    func beginDrag(at point: CGPoint) {
        dragStart = point
        dragRegistered = false
        editingSelectedAnnotation = false
        if tool != .select, tool != .crop, selectedAnnotationOwns(point) {
            editingSelectedAnnotation = true
            beginSelectDrag(at: point)
            return
        }
        if tool != .select, tool != .crop {
            selectedID = nil
        }
        switch tool {
        case .select:
            beginSelectDrag(at: point)
        case .crop:
            let bounds = CGRect(origin: .zero, size: imageSize)
            if let draft = cropDraft,
               let handle = ScreenshotSupport.handle(at: point, rect: draft,
                                                     tolerance: 14 * scale) {
                activeHandle = handle
                cropResizeOrigin = draft
                cropLoupePoint = handle.position(in: draft)
            } else if let draft = cropDraft,
                      ScreenshotSupport.startsNewCropSelection(
                        at: point, draft: draft, within: bounds) {
                cropSelectionOrigin = draft
            } else if let draft = cropDraft, draft.contains(point) {
                cropMoveOrigin = draft
            }
        case .arrow, .line:
            registerUndo()
            dragRegistered = true
            let annotation = ScreenshotSupport.Annotation(
                tool: tool, points: [point, point], color: color, stroke: stroke,
                arrowStyle: arrowStyle)
            annotations.append(annotation)
            draftID = annotation.id
        case .freehand:
            registerUndo()
            dragRegistered = true
            let annotation = ScreenshotSupport.Annotation(
                tool: tool, points: [point], color: color, stroke: stroke)
            annotations.append(annotation)
            draftID = annotation.id
        case .rect, .ellipse, .highlight, .pixelate, .redact:
            if tool == .pixelate { ensurePixelated(level: blurLevel) }
            registerUndo()
            dragRegistered = true
            let annotation = ScreenshotSupport.Annotation(
                tool: tool, rect: CGRect(origin: point, size: .zero),
                color: color, stroke: stroke, blurLevel: blurLevel)
            annotations.append(annotation)
            draftID = annotation.id
        case .text, .sticker, .counter:
            break
        }
    }

    func beginSelectDrag(at point: CGPoint) {
        if let selectedID,
           let selected = annotations.first(where: { $0.id == selectedID }) {
            let tolerance = 12 * scale
            if selected.tool.resizesWithHandles,
               let handle = ScreenshotSupport.handle(at: point, rect: selected.rect,
                                                     tolerance: tolerance) {
                activeHandle = handle
                moveOrigin = selected.rect
                return
            }
            if selected.points.count >= 2 {
                if hypot(point.x - selected.points[0].x, point.y - selected.points[0].y) < tolerance {
                    activeHandle = .topLeft
                    movePoints = selected.points
                    return
                }
                if hypot(point.x - selected.points[1].x, point.y - selected.points[1].y) < tolerance {
                    activeHandle = .bottomRight
                    movePoints = selected.points
                    return
                }
            }
        }
        let hitID = hitTest(point)
        self.selectedID = nil
        if let hitID, let hit = annotations.first(where: { $0.id == hitID }) {
            syncControls(to: hit)
            self.selectedID = hitID
            moveOrigin = hit.rect
            movePoints = hit.points
            clearTextSelection()
        } else if let word = wordIndex(at: point) {
            // A drag over recognized text selects intersecting words.
            textSelectionAnchor = point
            selectedWordIndexes = [word]
        }
    }

    func continueDrag(to point: CGPoint) {
        if editingSelectedAnnotation {
            continueSelectDrag(to: point)
            return
        }
        switch tool {
        case .select:
            continueSelectDrag(to: point)
        case .crop:
            let bounds = CGRect(origin: .zero, size: imageSize)
            if let handle = activeHandle, let origin = cropResizeOrigin {
                let rect = ScreenshotSupport.resizedRect(origin, dragging: handle, to: point)
                let snapped = ScreenshotSupport.pixelSnappedCropRect(rect, within: bounds)
                cropDraft = snapped
                cropLoupePoint = handle.position(in: snapped)
            } else if cropSelectionOrigin != nil {
                cropDraft = ScreenshotSupport.pixelSnappedCropRect(
                    ScreenshotSupport.selectionRect(from: dragStart, to: point),
                    within: bounds)
            } else if let origin = cropMoveOrigin {
                let delta = CGPoint(x: point.x - dragStart.x, y: point.y - dragStart.y)
                cropDraft = ScreenshotSupport.pixelSnappedCropRect(
                    ScreenshotSupport.movedRect(origin, by: delta, within: bounds),
                    within: bounds)
            }
        case .arrow, .line:
            updateDraft { $0.points = [dragStart, point] }
        case .freehand:
            updateDraft { $0.points.append(point) }
        case .rect, .ellipse, .highlight, .pixelate, .redact:
            updateDraft { $0.rect = ScreenshotSupport.selectionRect(from: dragStart, to: point) }
        case .text, .sticker, .counter:
            break
        }
    }

    func continueSelectDrag(to point: CGPoint) {
        if let anchor = textSelectionAnchor {
            selectedWordIndexes = ScreenshotSupport.wordSelection(
                anchor: anchor, current: point, boxes: textWords.map(\.rect))
            return
        }
        guard let selectedID,
              let index = annotations.firstIndex(where: { $0.id == selectedID })
        else { return }
        if !dragRegistered {
            registerUndo()
            dragRegistered = true
        }
        if let handle = activeHandle {
            if annotations[index].points.count >= 2 {
                var points = movePoints
                if handle == .topLeft { points[0] = point } else { points[1] = point }
                annotations[index].points = points
            } else {
                annotations[index].rect = ScreenshotSupport.resizedRect(
                    moveOrigin, dragging: handle, to: point)
            }
            return
        }
        let delta = CGPoint(x: point.x - dragStart.x, y: point.y - dragStart.y)
        if annotations[index].points.isEmpty {
            annotations[index].rect = moveOrigin.offsetBy(dx: delta.x, dy: delta.y)
        } else {
            annotations[index].points = movePoints.map {
                CGPoint(x: $0.x + delta.x, y: $0.y + delta.y)
            }
        }
    }

    /// `isTap` is decided by the view in screen points, so a click stays a
    /// click at any zoom level; deciding it here in image pixels made taps
    /// on zoomed-out Retina captures read as drags (the text tool bug).
    func endDrag(at point: CGPoint, isTap: Bool) {
        defer {
            draftID = nil
            activeHandle = nil
            cropResizeOrigin = nil
            cropMoveOrigin = nil
            cropSelectionOrigin = nil
            cropLoupePoint = nil
            dragRegistered = false
            editingSelectedAnnotation = false
        }
        if editingSelectedAnnotation {
            finishSelectDrag(at: point, isTap: isTap)
            return
        }
        switch tool {
        case .text:
            guard isTap else { return }
            if selectExistingAnnotation(at: point) { return }
            registerUndo()
            var annotation = ScreenshotSupport.Annotation(
                tool: .text, color: color, stroke: stroke, textSize: textSize)
            annotation.rect = ScreenshotRenderer.textBounds("", at: point, textSize: textSize,
                                                            scale: scale)
            annotations.append(annotation)
            newTextID = annotation.id
            selectedID = annotation.id
            editingTextID = annotation.id
        case .sticker:
            guard isTap else { return }
            if selectExistingAnnotation(at: point) { return }
            registerUndo()
            let bounds = CGRect(origin: .zero, size: imageSize)
            let side = ScreenshotSupport.stickerSide(for: imageSize, scale: scale)
            let annotation = ScreenshotSupport.Annotation(
                tool: .sticker,
                rect: ScreenshotSupport.stickerRect(centeredAt: point,
                                                     side: side,
                                                     within: bounds),
                text: sticker.rawValue,
                color: color,
                stroke: stroke)
            annotations.append(annotation)
            selectedID = annotation.id
        case .counter:
            guard isTap else { return }
            if selectExistingAnnotation(at: point) { return }
            registerUndo()
            let annotation = ScreenshotSupport.Annotation(
                tool: .counter,
                rect: CGRect(x: point.x, y: point.y, width: 0, height: 0),
                color: color, stroke: stroke, number: 1)
            annotations.append(annotation)
            annotations = ScreenshotSupport.renumberingCounters(annotations)
            selectedID = annotation.id
        case .arrow, .line, .rect, .ellipse, .highlight, .pixelate, .redact, .freehand:
            if isTap {
                // A tap never leaves a degenerate shape behind; treat it as
                // picking whatever is under the cursor instead.
                annotations.removeAll { $0.id == draftID }
                if !undoStack.isEmpty { undoStack.removeLast() }
                refreshUndoFlags()
                refreshDirtyState()
                _ = selectExistingAnnotation(at: point)
            } else if let draftID {
                selectedID = draftID
            }
        case .select:
            finishSelectDrag(at: point, isTap: isTap)
        case .crop:
            if isTap, let origin = cropSelectionOrigin {
                cropDraft = origin
            }
        }
    }

    /// The visible selection remains directly editable after creation. A new
    /// tool or a gesture outside it ends that priority and creates normally.
    func selectedAnnotationOwns(_ point: CGPoint) -> Bool {
        guard let selectedID,
              let selected = annotations.first(where: { $0.id == selectedID })
        else { return false }
        let tolerance = 12 * scale
        if selected.tool.resizesWithHandles,
           ScreenshotSupport.handle(at: point, rect: selected.rect,
                                    tolerance: tolerance) != nil {
            return true
        }
        if selected.points.prefix(2).contains(where: {
            hypot(point.x - $0.x, point.y - $0.y) < tolerance
        }) {
            return true
        }
        return hitTest(point) == selectedID
    }

    func finishSelectDrag(at point: CGPoint, isTap: Bool) {
        textSelectionAnchor = nil
        guard isTap, !dragRegistered else { return }
        let hitID = hitTest(point)
        self.selectedID = nil
        if let hitID, let hit = annotations.first(where: { $0.id == hitID }) {
            syncControls(to: hit)
            self.selectedID = hitID
            editingTextID = hit.tool == .text ? hitID : nil
            clearTextSelection()
        } else if let word = wordIndex(at: point) {
            selectedWordIndexes = [word]
        } else {
            clearTextSelection()
        }
    }

    /// A click on an existing mark always means "edit this", even while a
    /// creation tool is active. Real drags still create with the active tool.
    /// Sticker selection updates the style picker without mutating the mark;
    /// text enters its inline editor immediately.
    @discardableResult
    func selectExistingAnnotation(at point: CGPoint) -> Bool {
        guard let hitID = hitTest(point, includeShapeInteriors: false),
              let hit = annotations.first(where: { $0.id == hitID })
        else {
            selectedID = nil
            return false
        }
        self.selectedID = nil
        syncControls(to: hit)
        selectedID = hitID
        editingTextID = hit.tool == .text ? hitID : nil
        clearTextSelection()
        tool = .select
        return true
    }

    func updateDraft(_ mutate: (inout ScreenshotSupport.Annotation) -> Void) {
        guard let draftID,
              let index = annotations.firstIndex(where: { $0.id == draftID })
        else { return }
        mutate(&annotations[index])
    }

    /// `includeShapeInteriors: false` is the creation-tap variant: area
    /// shapes (boxes, ellipses, highlights, censors) only answer near their
    /// edge, so their inside stays free for placing a new text, sticker or
    /// counter — the tap that used to create one there must keep doing so.
    func hitTest(_ point: CGPoint, includeShapeInteriors: Bool = true) -> UUID? {
        let tolerance = 10 * scale
        for annotation in annotations.reversed() {
            switch annotation.tool {
            case .arrow, .line:
                guard annotation.points.count >= 2 else { continue }
                if ScreenshotSupport.distance(from: point,
                                              toSegment: annotation.points[0],
                                              annotation.points[1])
                    <= tolerance + annotation.stroke.width * scale / 2 {
                    return annotation.id
                }
            case .freehand:
                for pathPoint in annotation.points
                where hypot(point.x - pathPoint.x, point.y - pathPoint.y) <= tolerance {
                    return annotation.id
                }
            case .counter:
                let radius = ScreenshotSupport.counterDiameter(for: imageSize, scale: 1) / 2
                if hypot(point.x - annotation.rect.midX, point.y - annotation.rect.midY)
                    <= radius + 4 * scale {
                    return annotation.id
                }
        case .rect, .ellipse, .highlight, .pixelate, .redact:
                let outer = annotation.rect.insetBy(dx: -tolerance / 2, dy: -tolerance / 2)
                guard outer.contains(point) else { continue }
                if includeShapeInteriors {
                    return annotation.id
                }
                // Edge ring only: a shape too small to have a meaningful
                // interior stays fully tappable.
                let inner = annotation.rect.insetBy(dx: tolerance, dy: tolerance)
                if inner.isEmpty || inner.width <= 0 || inner.height <= 0
                    || !inner.contains(point) {
                    return annotation.id
                }
            case .text, .sticker:
                if annotation.rect.insetBy(dx: -tolerance / 2, dy: -tolerance / 2)
                    .contains(point) {
                    return annotation.id
                }
            case .select, .crop:
                continue
            }
        }
        return nil
    }

}
