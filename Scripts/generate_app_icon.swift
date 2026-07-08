import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate_app_icon.swift <AppIcon.appiconset>\n", stderr)
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sizes = [16, 32, 64, 128, 256, 512, 1024]

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

for pixelSize in sizes {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let canvas = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    // Let macOS apply the icon mask exactly once. A transparent, pre-rounded
    // background is treated like legacy artwork and gets an extra Dock frame.
    NSColor.white.setFill()
    canvas.fill()

    guard let baseSymbol = NSImage(systemSymbolName: "eye", accessibilityDescription: nil) else {
        throw CocoaError(.fileReadUnknown)
    }
    let pointConfiguration = NSImage.SymbolConfiguration(
        pointSize: CGFloat(pixelSize) * 0.52,
        weight: .medium
    )
    let blackConfiguration = NSImage.SymbolConfiguration(paletteColors: [.black])
    let symbol = baseSymbol.withSymbolConfiguration(pointConfiguration.applying(blackConfiguration)) ?? baseSymbol
    let symbolWidth = CGFloat(pixelSize) * 0.72
    let aspectRatio = symbol.size.height / max(symbol.size.width, 1)
    let symbolHeight = symbolWidth * aspectRatio
    let symbolRect = NSRect(
        x: (CGFloat(pixelSize) - symbolWidth) / 2,
        y: (CGFloat(pixelSize) - symbolHeight) / 2,
        width: symbolWidth,
        height: symbolHeight
    )
    symbol.draw(in: symbolRect)

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: outputDirectory.appendingPathComponent("icon_\(pixelSize).png"))
}
