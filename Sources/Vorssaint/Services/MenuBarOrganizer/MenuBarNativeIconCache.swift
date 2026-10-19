// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import AppKit
import ScreenCaptureKit

/// Pictures of the real macOS 27 menu bar icons, as Bartender shows them.
/// macOS 27 draws every status icon into one MenuBarAgent window, separate
/// from the wallpaper and the bar background. Capturing that window alone
/// gives the icons on a transparent background; each icon is cut at its
/// frame. Hidden icons are not drawn, so an empty cut keeps the last good
/// picture. Pictures persist so always-hidden icons keep theirs.
@MainActor
final class MenuBarNativeIconCache: ObservableObject {
    static let shared = MenuBarNativeIconCache()
    @Published private(set) var images: [MenuBarItemIdentity: NSImage] = [:]
    private var saved: [MenuBarItemIdentity: NSImage] = [:] // read during view updates; not published
    private var persisted: [MenuBarItemIdentity: Date] = [:]
    private var lastCapture = Date.distantPast
    private var capturing = false
    /// Frames from the previous capture call; only settled icons are cut.
    private var lastFrames: [MenuBarItemIdentity: CGRect] = [:]
    private var liveTimer: Timer?
    private var liveItems: () -> (items: [ManagedMenuBarItem], hidden: Set<String>) = { ([], []) }

    func image(for identity: MenuBarItemIdentity) -> NSImage? {
        if let image = images[identity] ?? saved[identity] { return image }
        guard let image = NSImage(contentsOf: file(for: identity)) else { return nil }
        saved[identity] = image
        return image
    }

    /// Background refresh from the organizer; throttled unless a picture is missing.
    func capture(_ items: [ManagedMenuBarItem], hidden: Set<String>) {
        let missing = items.contains { $0.identityState == .stable && image(for: $0.id) == nil }
        guard Date().timeIntervalSince(lastCapture) > (missing ? 5 : 60) else { return }
        Task { await snapshot(items, hidden: hidden) }
    }

    /// Before the first hiding pass every icon is drawn, including apps that
    /// any pass hides as a side effect (iStat Menus, Setapp); picture them now.
    func captureBeforeHiding(_ items: [ManagedMenuBarItem]) async {
        lastFrames = Dictionary(items.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        try? await Task.sleep(for: .seconds(1)) // let launch-time reflow settle
        let fresh = await MenuBarNativeAXProvider.snapshot()
        await snapshot(fresh.enumerationSucceeded ? fresh.items : items, hidden: [])
    }

    /// Live pictures while the editor is on screen, like Bartender's
    /// updateImagesTimer. Stops by itself after ten minutes.
    func startLive(_ items: @escaping () -> (items: [ManagedMenuBarItem], hidden: Set<String>)) {
        liveItems = items
        liveTimer?.invalidate()
        let started = Date()
        liveTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, Date().timeIntervalSince(started) < 600 else { timer.invalidate(); return }
                let current = self.liveItems()
                Task { await self.snapshot(current.items, hidden: current.hidden) }
            }
        }
        let current = items()
        Task { await snapshot(current.items, hidden: current.hidden) }
    }

    func stopLive() { liveTimer?.invalidate(); liveTimer = nil }

    private func snapshot(_ items: [ManagedMenuBarItem], hidden: Set<String>) async {
        // Reported frames lag a reflow (Aster's own stats resizing, apps
        // launching); an icon must report the same frame twice in a row.
        let settled = items.filter { lastFrames[$0.id] == $0.frame }
        lastFrames = Dictionary(items.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        let usable = Self.capturable(settled, hidden: hidden)
        guard !capturing, !usable.isEmpty else { return }
        capturing = true
        lastCapture = Date()
        defer { capturing = false }
        guard let strip = await Self.captureIconWindow() else { return }
        for item in usable { store(strip.crop(item.frame), for: item.id) }
    }

    private func store(_ image: CGImage?, for identity: MenuBarItemIdentity) {
        guard let image, !Self.isEmpty(image) else { return }
        images[identity] = NSImage(cgImage: image, size: .zero)
        // Re-save at most once a minute, so a later good picture replaces a bad one.
        guard Date().timeIntervalSince(persisted[identity] ?? .distantPast) > 60 else { return }
        persisted[identity] = Date()
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

    /// Undrawn icons keep a stale frame where another icon may now be drawn.
    /// `hidden` names what is undrawn: bundle IDs, publisher names or item
    /// titles. Any icon overlapping another one is stacked in the overflow.
    static func capturable(_ items: [ManagedMenuBarItem], hidden: Set<String>) -> [ManagedMenuBarItem] {
        let own = ownStatusFrames()
        return items.filter { item in
            let inner = item.frame.insetBy(dx: 3, dy: 0)
            return item.identityState == .stable && item.frame.width > 0
                && hidden.isDisjoint(with: [item.bundleIdentifier, item.sourceName, item.id.title])
                && !items.contains { $0.id != item.id && $0.frame.intersects(inner) }
                && !own.contains { $0.intersects(inner) }
        }
    }

    /// Aster's own status items, top-left screen coordinates. Inventories
    /// leave them out, yet a neighbour's stale frame can lie over them.
    static func ownStatusFrames() -> [CGRect] {
        let top = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.maxY ?? 0
        return NSApp.windows.filter { $0.className.contains("StatusBarWindow") && $0.isVisible }.map {
            CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
        }
    }

    /// A hidden icon's area is undrawn. The crop is drawn into a gray+alpha
    /// buffer, so any source pixel layout reads alike.
    static func isEmpty(_ image: CGImage) -> Bool {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 2, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return false }
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 2) // gray, alpha
        return !stride(from: 1, to: width * height * 2, by: 2).contains { bytes[$0] > 24 }
    }

    private struct Strip {
        let image: CGImage
        let frame: CGRect
        /// Every icon is cut from the same 24-point band at the bar's centre.
        /// Apple's icons report the full bar height, app icons 24 points, so
        /// per-frame heights would shrink Apple's icons when shown side by side.
        func crop(_ item: CGRect) -> CGImage? {
            let scale = CGFloat(image.width) / frame.width
            return image.cropping(to: CGRect(x: (item.minX - frame.minX) * scale, y: (frame.height / 2 - 12) * scale,
                                             width: item.width * scale, height: 24 * scale).integral)
        }
    }

    /// MenuBarAgent's own menu-bar-height window on the main display.
    private static func captureIconWindow() async -> Strip? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let window = content.windows.first(where: {
                  $0.owningApplication?.bundleIdentifier == "com.apple.MenuBarAgent"
                      && $0.frame.minY == 0 && $0.frame.height <= 60 && $0.frame.width > 400 }) else { return nil }
        let configuration = SCStreamConfiguration()
        let scale = NSScreen.screens.first { $0.frame.origin == .zero }?.backingScaleFactor ?? 2
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration) else { return nil }
        return Strip(image: image, frame: window.frame)
    }
}
