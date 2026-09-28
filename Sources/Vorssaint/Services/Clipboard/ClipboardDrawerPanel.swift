// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The panel stays on its display. Clipping the sliding content prevents it
/// from appearing on another display arranged below this one.
final class ClipboardDrawerPanel: OverlayPanel {
    private var drawerContent: NSView?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    func place(on screen: NSRect) {
        let target = ClipboardHistoryWindowSizing.frame(on: screen)
        if frame == target, drawerContent != nil { return }
        setFrame(target, display: false)
        let container = NSView(frame: NSRect(origin: .zero, size: target.size))
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        let host = NSHostingView(rootView: ClipboardQuickPanelView()
            .frame(width: target.width, height: target.height))
        host.sizingOptions = []
        host.frame = container.bounds
        container.addSubview(host)
        contentView = container
        drawerContent = host
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
