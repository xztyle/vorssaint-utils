// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The panel stays on its display. Clipping the sliding content prevents it
/// from appearing on another display arranged below this one.
final class ClipboardDrawerPanel: OverlayPanel {
    private var drawerContent: NSView?
    private var displayFrame = NSRect.zero
    private var preferredHeight: Double? = ClipboardLibraryProbe.root == nil
        ? UserDefaults.standard.object(forKey: DefaultsKey.clipboardDrawerHeight) as? Double : nil

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var targetFrame: NSRect {
        ClipboardHistoryWindowSizing.frame(on: displayFrame, preferredHeight: preferredHeight)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    func place(on screen: NSRect) {
        displayFrame = screen
        let target = targetFrame
        if frame == target, drawerContent != nil { return }
        setFrame(target, display: false)
        if let drawerContent {
            contentView?.setFrameSize(target.size)
            drawerContent.setFrameSize(target.size)
            return
        }
        installContent(size: target.size)
    }

    private func installContent(size: NSSize) {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        let host = NSHostingView(rootView: ClipboardQuickPanelView()
            .overlay(alignment: .top) { ClipboardDrawerResizeEdge().frame(height: 6) })
        host.sizingOptions = []
        host.frame = container.bounds
        container.addSubview(host)
        contentView = container
        drawerContent = host
    }

    func resize(to height: Double, finished: Bool) {
        guard height.isFinite, displayFrame.height > 0 else { return }
        preferredHeight = max(1, height)
        place(on: displayFrame)
        if finished {
            preferredHeight = frame.height
            if ClipboardLibraryProbe.root == nil {
                UserDefaults.standard.set(frame.height, forKey: DefaultsKey.clipboardDrawerHeight)
            }
        }
        ClipboardLibraryProbe.recordState()
    }

    func reveal(reduceMotion: Bool) {
        guard let drawerContent else { return }
        if !isVisible {
            drawerContent.setFrameOrigin(ClipboardHistoryWindowSizing.contentOrigin(height: frame.height, presented: false))
        }
        orderFrontRegardless()
        animateContent(presented: true, reduceMotion: reduceMotion, completion: { ClipboardLibraryProbe.recordState() })
    }

    func dismiss(reduceMotion: Bool, completion: @escaping () -> Void) {
        animateContent(presented: false, reduceMotion: reduceMotion, completion: completion)
    }

    private func animateContent(presented: Bool, reduceMotion: Bool, completion: @escaping () -> Void) {
        guard let drawerContent else { completion(); return }
        let origin = ClipboardHistoryWindowSizing.contentOrigin(height: frame.height, presented: presented)
        let duration = ClipboardHistoryWindowSizing.duration(presented: presented, reduceMotion: reduceMotion)
        guard duration > 0 else { drawerContent.setFrameOrigin(origin); completion(); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: presented ? .easeOut : .easeIn)
            drawerContent.animator().setFrameOrigin(origin)
        } completionHandler: { completion() }
    }
}

/// An invisible top edge uses the native resize cursor without window chrome.
private struct ClipboardDrawerResizeEdge: NSViewRepresentable {
    @ObservedObject private var l10n = L10n.shared
    func makeNSView(context: Context) -> ClipboardDrawerResizeView { ClipboardDrawerResizeView() }
    func updateNSView(_ view: ClipboardDrawerResizeView, context: Context) {
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.splitter)
        view.setAccessibilityLabel(ClipboardLibraryStrings(language: l10n.language).resizeHeight)
    }
}

private final class ClipboardDrawerResizeView: NSView {
    private var startY: Double?
    private var startHeight = 0.0

    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }

    override func mouseDown(with event: NSEvent) {
        guard let panel = window as? ClipboardDrawerPanel else { return }
        startY = panel.convertPoint(toScreen: event.locationInWindow).y
        startHeight = panel.frame.height
    }

    override func mouseDragged(with event: NSEvent) { update(event, finished: false) }
    override func mouseUp(with event: NSEvent) { update(event, finished: true); startY = nil }

    override func accessibilityValue() -> Any? { (window as? ClipboardDrawerPanel)?.frame.height }

    override func setAccessibilityValue(_ value: Any?) {
        guard let number = value as? NSNumber, number.doubleValue.isFinite else { return }
        (window as? ClipboardDrawerPanel)?.resize(to: number.doubleValue, finished: true)
    }

    override func accessibilityPerformIncrement() -> Bool { adjustHeight(by: 32) }
    override func accessibilityPerformDecrement() -> Bool { adjustHeight(by: -32) }

    private func adjustHeight(by delta: Double) -> Bool {
        guard let panel = window as? ClipboardDrawerPanel else { return false }
        panel.resize(to: panel.frame.height + delta, finished: true)
        return true
    }

    private func update(_ event: NSEvent, finished: Bool) {
        guard let startY, let panel = window as? ClipboardDrawerPanel else { return }
        let height = startHeight + panel.convertPoint(toScreen: event.locationInWindow).y - startY
        panel.resize(to: height, finished: finished)
    }
}
