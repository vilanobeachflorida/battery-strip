import AppKit
import CoreText

/// Draws the menu bar battery: a solid charge level on a translucent body, with the time remaining
/// or percentage set inside it, like the battery on iPhone.
enum BatteryIcon {
    enum Badge {
        case none, charging, pluggedIn

        var symbolName: String? {
            switch self {
            case .none: nil
            case .charging: "bolt.fill"
            case .pluggedIn: "powerplug.fill"
            }
        }
    }

    private static let bodyHeight: CGFloat = 13
    private static let horizontalPadding: CGFloat = 3.5
    private static let capSize = NSSize(width: 1.5, height: 4.5)

    /// Condensed, bold and with fixed-width digits, so the battery doesn't change width as the time counts down.
    private static let font: NSFont = {
        let base = NSFont.systemFont(ofSize: 10.5, weight: .bold, width: .condensed)
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]],
        ])
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }()

    /// The narrowest the body gets with text, sized for "0:00".
    private static let minimumTextWidth = ceil(NSAttributedString(string: "0:00", attributes: [.font: font]).size().width)

    /// With no `fill` color the image is a template, so macOS tints it to match the menu bar.
    static func image(level: Double, text: String?, badge: Badge, fill: NSColor?) -> NSImage {
        let textWidth = text.map { ceil(NSAttributedString(string: $0, attributes: [.font: font]).size().width) } ?? 0
        let bodyWidth = text == nil ? 24 : max(minimumTextWidth, textWidth) + horizontalPadding * 2
        let badgeWidth: CGFloat = badge == .none ? 0 : 9
        let size = NSSize(width: bodyWidth + 1 + capSize.width + badgeWidth, height: 15)

        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let ink = fill == nil ? NSColor.black : NSColor.labelColor
            let body = NSRect(x: 0, y: (size.height - bodyHeight) / 2, width: bodyWidth, height: bodyHeight)
            let bodyPath = NSBezierPath(roundedRect: body, xRadius: 4, yRadius: 4)

            ink.withAlphaComponent(0.35).setFill()
            bodyPath.fill()
            let cap = NSRect(x: body.maxX + 1, y: body.midY - capSize.height / 2, width: capSize.width, height: capSize.height)
            NSBezierPath(roundedRect: cap, xRadius: 0.75, yRadius: 0.75).fill()

            let charged = NSRect(x: body.minX, y: body.minY, width: body.width * min(max(level, 0), 1), height: body.height)
            NSGraphicsContext.saveGraphicsState()
            bodyPath.addClip()
            (fill ?? ink).setFill()
            charged.fill()
            NSGraphicsContext.restoreGraphicsState()

            if let text {
                // Baseline placed so the digits sit centered in the body.
                let baseline = (body.midY - font.capHeight / 2).rounded(.toNearestOrEven)
                let origin = NSPoint(x: body.midX - textWidth / 2, y: baseline + font.descender)

                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: charged).addClip()
                if fill == nil {
                    // Cut the digits out of the charge, so the menu bar shows through them.
                    context.setBlendMode(.destinationOut)
                    NSAttributedString(string: text, attributes: [.font: font]).draw(at: origin)
                } else {
                    // On a colored charge, dark digits read best in both light and dark menu bars, as on iPhone.
                    NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black.withAlphaComponent(0.85)]).draw(at: origin)
                }
                NSGraphicsContext.restoreGraphicsState()

                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: charged.maxX, y: body.minY, width: body.maxX - charged.maxX, height: body.height)).addClip()
                NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink]).draw(at: origin)
                NSGraphicsContext.restoreGraphicsState()
            }

            if let symbolName = badge.symbolName {
                drawBadge(symbolName, in: NSRect(x: cap.maxX + 1.5, y: 0, width: badgeWidth - 1.5, height: size.height), color: ink)
            }
            return true
        }
        image.isTemplate = fill == nil
        return image
    }

    private static func drawBadge(_ symbolName: String, in rect: NSRect, color: NSColor) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let size = symbol.size
        symbol.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
    }
}
