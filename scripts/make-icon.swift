// Builds the app icon set from Design/AppIcon.png.
//
// Fits the artwork into the macOS icon grid (an 824 px rounded square on a 1024 px canvas, with the
// standard drop shadow) and writes every size the asset catalog needs. Run from the repo root:
//
//     swift scripts/make-icon.swift
import AppKit

let source = URL(fileURLWithPath: "Design/AppIcon.png")
let output = URL(fileURLWithPath: "BatteryStrip/Assets.xcassets/AppIcon.appiconset")

guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    fatalError("Couldn't read \(source.path)")
}

// Read the pixels to find the opaque tile and the colors along its top and bottom edges.
let width = artwork.width, height = artwork.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let reader = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
reader.draw(artwork, in: CGRect(x: 0, y: 0, width: width, height: height))

func pixel(_ x: Int, _ y: Int) -> [UInt8] {
    let index = (y * width + x) * 4
    return Array(pixels[index..<index + 4])
}

var minX = width, maxX = 0, minY = height, maxY = 0
for y in 0..<height {
    for x in 0..<width where pixel(x, y)[3] > 200 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}
// Bitmap rows run top to bottom; CGImage cropping uses the same orientation.
let tileRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
let tile = artwork.cropping(to: tileRect)!

func color(atX x: Int, y: Int) -> CGColor {
    let p = pixel(x, y)
    return CGColor(red: CGFloat(p[0]) / 255, green: CGFloat(p[1]) / 255, blue: CGFloat(p[2]) / 255, alpha: 1)
}
let inset = Int(tileRect.height * 0.04)
let topColor = color(atX: Int(tileRect.midX), y: minY + inset)
let bottomColor = color(atX: Int(tileRect.midX), y: maxY - inset)

func render(size: Int) -> Data {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let shape = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Shadow, as on Apple's icon template.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(shape)
    context.setFillColor(bottomColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    // Backfill with the tile's own edge colors, so its rounder corners blend into the grid's shape.
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [bottomColor, topColor] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
    // Fill the square with the artwork, trimming whichever side is longer.
    let scale = max(824 / tileRect.width, 824 / tileRect.height)
    let drawn = CGSize(width: tileRect.width * scale, height: tileRect.height * scale)
    context.draw(tile, in: CGRect(x: 512 - drawn.width / 2, y: 512 - drawn.height / 2, width: drawn.width, height: drawn.height))
    context.restoreGState()

    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    try! render(size: size).write(to: output.appending(path: "icon_\(size).png"))
}
print("Wrote app icons from a \(Int(tileRect.width))x\(Int(tileRect.height)) tile")
