// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import AppKit

/// Pictures of the real macOS 27 menu bar icons, as Bartender shows them.
/// One capture of the menu bar strip is cut into per-icon images. Capture
/// runs only while no hiding pass is active: hidden icons keep stale frames,
/// so a cut-out there would show a neighbour. Images persist on disk so an
/// always-hidden icon keeps its picture across launches.
@MainActor
final class MenuBarNativeIconCache: ObservableObject {
    static let shared = MenuBarNativeIconCache()
    @Published private(set) var images: [MenuBarItemIdentity: NSImage] = [:]
    private var saved: [MenuBarItemIdentity: NSImage] = [:] // read during view updates; not published
    private var lastCapture = Date.distantPast
    private var capturing = false

    func image(for identity: MenuBarItemIdentity) -> NSImage? {
        if let image = images[identity] ?? saved[identity] { return image }
        guard let image = NSImage(contentsOf: file(for: identity)) else { return nil }
        saved[identity] = image
        return image
    }

    /// Throttled; a missing picture forces a capture sooner.
    func capture(_ items: [ManagedMenuBarItem]) {
        let usable = Self.capturable(items)
        let missing = usable.contains { image(for: $0.id) == nil }
        guard !capturing, !usable.isEmpty,
              Date().timeIntervalSince(lastCapture) > (missing ? 5 : 120) else { return }
        capturing = true
        Task { [weak self] in
            defer { self?.capturing = false; self?.lastCapture = Date() }
            guard let strip = await Self.captureStrip(usable) else { return }
            for item in usable { self?.store(strip.crop(item.frame), for: item.id) }
        }
    }

    /// Stable icons whose frame no other icon overlaps: overflowed icons are
    /// stacked behind the system arrow and have no picture of their own.
    static func capturable(_ items: [ManagedMenuBarItem]) -> [ManagedMenuBarItem] {
        items.filter { item in
            item.identityState == .stable && item.frame.width > 0
                && !items.contains { $0.id != item.id && $0.frame.intersects(item.frame.insetBy(dx: 1, dy: 0)) }
        }
    }

    private func store(_ image: CGImage?, for identity: MenuBarItemIdentity) {
        guard let image else { return }
        let picture = NSImage(cgImage: image, size: .zero)
        images[identity] = picture
        let url = file(for: identity)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }

    private func file(for identity: MenuBarItemIdentity) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "io.github.xztyle.Aster")
            .appendingPathComponent("MenuBarIcons")
            .appendingPathComponent(String(MenuBarNativeItemPolicy.slot(identity), radix: 16) + ".png")
    }

    private struct Strip {
        let image: CGImage
        let scale: CGFloat
        func crop(_ frame: CGRect) -> CGImage? {
            image.cropping(to: CGRect(x: frame.minX * scale, y: frame.minY * scale,
                                      width: frame.width * scale, height: frame.height * scale).integral)
        }
    }

    private static func captureStrip(_ items: [ManagedMenuBarItem]) async -> Strip? {
        let display = CGMainDisplayID()
        let scale = NSScreen.screens.first { $0.frame.origin == .zero }?.backingScaleFactor ?? 2
        let height = (items.map(\.frame.maxY).max() ?? 40) + 2
        let width = CGDisplayBounds(display).width
        guard let image = await ScreenshotCaptureEngine.captureDisplayRegion(
            displayID: display, pixelRect: CGRect(x: 0, y: 0, width: width * scale, height: height * scale),
            includePointer: false, hideVorssaintWindows: false, protectedWindowIDs: []) else { return nil }
        return Strip(image: image, scale: scale)
    }
}
