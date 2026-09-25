#!/usr/bin/env swift
// Builds Cadence/Assets.xcassets/AppIcon.appiconset from a square source image.
//
// The source is scaled onto Apple's macOS icon grid (824pt artwork on a
// 1024pt canvas) so it sits at the same visual size as other app icons.
//
// Usage: swift scripts/make-icons.swift Resources/AppIcon-source.png

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2, let source = NSImage(contentsOfFile: arguments[1]) else {
    FileHandle.standardError.write("usage: make-icons.swift <source.png>\n".data(using: .utf8)!)
    exit(1)
}

let iconSet = URL(fileURLWithPath: "Cadence/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

func render(pixels: Int, to url: URL) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let canvas = CGFloat(pixels)
    let artwork = canvas * 824 / 1024
    let inset = (canvas - artwork) / 2

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: NSRect(x: inset, y: inset, width: artwork, height: artwork))
    NSGraphicsContext.restoreGraphicsState()

    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

// (point size, scale)
let variants = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []

for (size, scale) in variants {
    let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
    try render(pixels: size * scale, to: iconSet.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appendingPathComponent("Contents.json"))

let catalog: [String: Any] = ["info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.deletingLastPathComponent().appendingPathComponent("Contents.json"))

// Smaller copy for the README.
try render(pixels: 256, to: URL(fileURLWithPath: "docs/icon.png"))

print("Wrote \(variants.count) icons to \(iconSet.path)")
