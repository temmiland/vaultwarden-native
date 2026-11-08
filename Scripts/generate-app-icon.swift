#!/usr/bin/env swift
import AppKit
import Foundation

// Renders the preserved official Vaultwarden SVG into the existing Apple asset catalog.
// The glyph is unchanged. iOS gets an opaque white canvas; macOS gets a rounded white tile.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("App/Resources/Artwork/vaultwarden-icon.svg")
let output = root.appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset")
let document = try XMLDocument(data: Data(contentsOf: source))
// CoreSVG does not expand <use> consistently inside masks. Expand only those references in
// memory, preserving their original geometry/transforms and the upstream source bytes.
for mask in try document.nodes(forXPath: "//*[local-name()='mask']") {
    for node in mask.children ?? [] {
        guard let use = node as? XMLElement, use.localName == "use",
              let href = use.attribute(forName: "xlink:href")?.stringValue, href.hasPrefix("#"),
              let original = try document.nodes(forXPath: "//*[@id='\(href.dropFirst())']").first,
              let shape = original.copy() as? XMLElement else { continue }
        shape.removeAttribute(forName: "id")
        if let transform = use.attribute(forName: "transform")?.stringValue {
            shape.addAttribute(XMLNode.attribute(withName: "transform", stringValue: transform) as! XMLNode)
        }
        if let parent = use.parent as? XMLElement, let index = parent.children?.firstIndex(of: use) {
            parent.replaceChild(at: index, with: shape)
        }
    }
}

// Apply the circular cutouts as vector clipping. CoreSVG otherwise rasterizes the SVG mask
// at its original small size, producing visibly pixelated holes in the 1024px app icon.
let logo = try document.nodes(forXPath: "//*[@id='logo']").first as! XMLElement
let matrix = logo.attribute(forName: "transform")!.stringValue!
    .replacingOccurrences(of: "matrix(", with: "").replacingOccurrences(of: ")", with: "")
    .split(separator: ",").map { Double($0)! }
let mask = try document.nodes(forXPath: "//*[@id='holes']").first!
let cutouts: [(x: Double, y: Double, radius: Double)] = (mask.children ?? []).compactMap { node in
    guard let circle = node as? XMLElement, circle.localName == "circle" else { return nil }
    let x = Double(circle.attribute(forName: "cx")?.stringValue ?? "0")!
    let y = Double(circle.attribute(forName: "cy")?.stringValue ?? "0")!
    let radius = Double(circle.attribute(forName: "r")!.stringValue!)!
    let rotation = circle.attribute(forName: "transform")?.stringValue ?? "rotate(0)"
    let angle = Double(rotation.replacingOccurrences(of: "rotate(", with: "").replacingOccurrences(of: ")", with: ""))! * .pi / 180
    return (
        (matrix[0] * (x * cos(angle) - y * sin(angle)) + matrix[4]) / 256,
        (matrix[3] * (x * sin(angle) + y * cos(angle)) + matrix[5]) / 256,
        radius * abs(matrix[0]) / 256
    )
}

for node in try document.nodes(forXPath: "//*[@mask='url(#holes)']") {
    (node as? XMLElement)?.removeAttribute(forName: "mask")
}

for dimension in ["width", "height"] {
    document.rootElement()?.attribute(forName: dimension)?.stringValue = "1024"
}

guard let image = NSImage(data: document.xmlData) else { fatalError("Cannot read the official Vaultwarden SVG") }

func render(name: String, pixels: Int, macOS: Bool) throws {
    let alpha: CGImageAlphaInfo = macOS ? .premultipliedLast : .noneSkipLast
    guard let canvas = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: alpha.rawValue
    ) else { fatalError("Cannot allocate icon canvas") }
    let context = NSGraphicsContext(cgContext: canvas, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let side = CGFloat(pixels)
    NSColor.white.setFill()
    if macOS {
        NSBezierPath(
            roundedRect: NSRect(x: side * 0.035, y: side * 0.035, width: side * 0.93, height: side * 0.93),
            xRadius: side * 0.205, yRadius: side * 0.205
        ).fill()
    } else {
        NSRect(x: 0, y: 0, width: side, height: side).fill()
    }
    let glyph = NSRect(x: side * 0.105, y: side * 0.105, width: side * 0.79, height: side * 0.79)
    canvas.saveGState()
    let clipping = CGMutablePath()
    clipping.addRect(NSRect(x: 0, y: 0, width: side, height: side))
    for cutout in cutouts {
        let radius = glyph.width * cutout.radius
        clipping.addEllipse(in: CGRect(
            x: glyph.minX + glyph.width * cutout.x - radius,
            y: glyph.minY + glyph.height * (1 - cutout.y) - radius,
            width: 2 * radius, height: 2 * radius
        ))
    }
    canvas.addPath(clipping)
    canvas.clip(using: .evenOdd)
    image.draw(in: glyph)
    canvas.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    guard let rendered = canvas.makeImage(),
          let png = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode app icon")
    }
    try png.write(to: output.appendingPathComponent(name))
}

try render(name: "icon-1024.png", pixels: 1024, macOS: false)
for size in [16, 32, 128, 256, 512] {
    try render(name: "icon-\(size).png", pixels: size, macOS: true)
    try render(name: "icon-\(size)@2x.png", pixels: size * 2, macOS: true)
}

print("Rendered the official Vaultwarden icon for iOS/iPadOS and macOS.")
