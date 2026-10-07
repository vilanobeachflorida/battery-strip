// Draws the disk image's window background: an arrow from the app to the Applications folder and a
// short instruction. Writes Design/DMG/background.tiff with 1x and 2x versions. Run from the repo root:
//
//     swift scripts/make-dmg-background.swift
//
// The icon positions here must match scripts/dmg-settings.py.
import AppKit

let size = NSSize(width: 640, height: 400)
let appCenter = NSPoint(x: 170, y: 190)
let applicationsCenter = NSPoint(x: 470, y: 190)
let output = URL(fileURLWithPath: "Design/DMG")

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    // Draw with the origin at the top left, the way Finder positions icons.
    context.cgContext.translateBy(x: 0, y: size.height)
    context.cgContext.scaleBy(x: 1, y: -1)

    NSGradient(colors: [NSColor(srgbRed: 0.985, green: 0.988, blue: 0.995, alpha: 1),
                        NSColor(srgbRed: 0.925, green: 0.935, blue: 0.955, alpha: 1)])!
        .draw(in: NSRect(origin: .zero, size: size), angle: 90)

    // The arrow, in the app icon's green.
    let start = NSPoint(x: appCenter.x + 88, y: appCenter.y)
    let end = NSPoint(x: applicationsCenter.x - 88, y: appCenter.y)
    let green = NSColor(srgbRed: 0.20, green: 0.78, blue: 0.40, alpha: 1)
    green.setStroke()
    let shaft = NSBezierPath()
    shaft.move(to: start)
    shaft.line(to: NSPoint(x: end.x - 10, y: end.y))
    shaft.lineWidth = 7
    shaft.lineCapStyle = .round
    shaft.stroke()
    green.setFill()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: end.x + 6, y: end.y))
    head.line(to: NSPoint(x: end.x - 18, y: end.y - 15))
    head.line(to: NSPoint(x: end.x - 18, y: end.y + 15))
    head.close()
    head.lineJoinStyle = .round
    head.lineWidth = 4
    head.fill()
    head.stroke()

    // The instruction, flipped back upright for text drawing.
    func draw(_ text: String, font: NSFont, color: NSColor, centerY: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        context.cgContext.saveGState()
        context.cgContext.translateBy(x: 0, y: centerY + textSize.height / 2)
        context.cgContext.scaleBy(x: 1, y: -1)
        string.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: 0))
        context.cgContext.restoreGState()
    }
    let rounded = NSFont.systemFont(ofSize: 17, weight: .semibold).fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 17) }
    draw("Drag Battery Strip into Applications", font: rounded ?? .systemFont(ofSize: 17, weight: .semibold),
         color: NSColor(white: 0.16, alpha: 1), centerY: 330)
    draw("Then open it from your Applications folder.", font: .systemFont(ofSize: 13),
         color: NSColor(white: 0.42, alpha: 1), centerY: 356)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let oneX = output.appending(path: "background.png"), twoX = output.appending(path: "background@2x.png")
try render(scale: 1).representation(using: .png, properties: [:])!.write(to: oneX)
try render(scale: 2).representation(using: .png, properties: [:])!.write(to: twoX)

// One TIFF holding both sizes, so Finder picks the sharp one on Retina displays.
let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", oneX.path, twoX.path, "-out", output.appending(path: "background.tiff").path]
try tiffutil.run()
tiffutil.waitUntilExit()
try FileManager.default.removeItem(at: oneX)
try FileManager.default.removeItem(at: twoX)
print("Wrote \(output.path)/background.tiff")
