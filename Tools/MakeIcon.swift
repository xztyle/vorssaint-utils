// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Copyright (C) 2026 Aster contributors

// Original vector artwork, rendered at every required macOS icon resolution.
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let iconSizes: [(String, Int, String?)] = [
    ("icon_16x16", 16, nil), ("icon_16x16@2x", 32, "ic11"),
    ("icon_32x32", 32, nil), ("icon_32x32@2x", 64, "ic12"),
    ("icon_128x128", 128, "ic07"), ("icon_128x128@2x", 256, "ic13"),
    ("icon_256x256", 256, "ic08"), ("icon_256x256@2x", 512, "ic14"),
    ("icon_512x512", 512, "ic09"), ("icon_512x512@2x", 1024, "ic10")
]

func drawMark(in rect: CGRect, color: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let transform = AffineTransform(translationByX: rect.midX, byY: rect.midY)
    (transform as NSAffineTransform).concat()
    color.setFill()
    for petal in 0..<6 {
        NSGraphicsContext.saveGraphicsState()
        let rotation = NSAffineTransform()
        rotation.rotate(byDegrees: CGFloat(petal) * 60)
        rotation.concat()
        NSBezierPath(roundedRect: CGRect(x: -rect.width * 0.087, y: rect.height * 0.075,
            width: rect.width * 0.174, height: rect.height * 0.40),
            xRadius: rect.width * 0.087, yRadius: rect.width * 0.087).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    NSBezierPath(ovalIn: CGRect(x: -rect.width * 0.055, y: -rect.height * 0.055,
        width: rect.width * 0.11, height: rect.height * 0.11)).fill()
    NSGraphicsContext.restoreGraphicsState()
}

func render(width: Int, height: Int, draw: () -> Void) -> Data? {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width,
        pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

func appIcon(_ pixels: Int) -> Data? {
    let size = CGFloat(pixels)
    return render(width: pixels, height: pixels) {
        let background = NSBezierPath(roundedRect: CGRect(x: size * 0.075, y: size * 0.075,
            width: size * 0.85, height: size * 0.85), xRadius: size * 0.19, yRadius: size * 0.19)
        NSGradient(starting: NSColor(srgbRed: 0.23, green: 0.14, blue: 0.49, alpha: 1),
            ending: NSColor(srgbRed: 0.51, green: 0.35, blue: 0.87, alpha: 1))?
            .draw(in: background, angle: 65)
        drawMark(in: CGRect(x: size * 0.19, y: size * 0.19,
            width: size * 0.62, height: size * 0.62), color: .white)
    }
}

func appendUInt32(_ value: Int, to data: inout Data) {
    for shift in stride(from: 24, through: 0, by: -8) {
        data.append(UInt8((UInt32(value) >> shift) & 255))
    }
}

func writeICNS(_ entries: [(String, Data)]) throws {
    var result = Data("icns".utf8)
    appendUInt32(8 + entries.reduce(0) { $0 + 8 + $1.1.count }, to: &result)
    for (type, data) in entries {
        result.append(contentsOf: type.utf8)
        appendUInt32(8 + data.count, to: &result)
        result.append(data)
    }
    try result.write(to: URL(fileURLWithPath: "\(outDir)/../AppIcon.icns"))
}

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
var entries: [(String, Data)] = []
for (name, size, type) in iconSizes {
    guard let data = appIcon(size) else { fatalError("Cannot render \(name)") }
    try data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    if let type { entries.append((type, data)) }
}
try writeICNS(entries)
for scale in [1, 2] {
    let data = render(width: 26 * scale, height: 20 * scale) {
        drawMark(in: CGRect(x: 5 * scale, y: 2 * scale, width: 16 * scale, height: 16 * scale), color: .black)
    }
    let suffix = scale == 1 ? "" : "@2x"
    try data?.write(to: URL(fileURLWithPath: "\(outDir)/../MenuBarIcon\(suffix).png"))
}
let mark = render(width: 640, height: 640) {
    drawMark(in: CGRect(x: 0, y: 0, width: 640, height: 640), color: .black)
}
try mark?.write(to: URL(fileURLWithPath: "\(outDir)/../BrandMark.png"))
print("Aster icons written to \(outDir)")
