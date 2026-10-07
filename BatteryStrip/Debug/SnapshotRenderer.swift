#if DEBUG
import AppKit
import SwiftUI

/// Renders the panel in a range of battery states to PNGs, for checking layout without clicking around:
///
///     "Battery Strip.app/Contents/MacOS/Battery Strip" --render-snapshots <folder>
///
/// Debug builds only. The glass background can't be captured this way, so a flat fill stands in for it.
enum SnapshotRenderer {
    static func runIfRequested(lowPowerMode: LowPowerModeController) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--render-snapshots"), index + 1 < arguments.count else { return }
        let folder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        guard var live = BatteryReader.read(includeTemperature: true) else {
            print("No battery to render")
            exit(1)
        }
        live.temperature = live.temperature ?? 31
        let history = sampleHistory(endingAt: live.percent)
        let preferences = Preferences.shared
        let savedShowDetails = preferences.showDetails

        var charging = live
        charging.percent = 64
        charging.isPluggedIn = true
        charging.isCharging = true
        charging.amperage = 3.1
        charging.adapter = PowerAdapter(watts: 96, name: "96W USB-C Power Adapter", manufacturer: "Apple Inc.")
        charging.adapterPower = 52
        charging.systemPower = 11.4

        var low = live
        low.percent = 8
        low.amperage = -0.62

        var held = live
        held.percent = 80
        held.isPluggedIn = true
        held.isCharging = false
        held.amperage = 0
        held.adapter = PowerAdapter(watts: 70, name: nil, manufacturer: nil)

        var full = held
        full.percent = 100
        full.isFullyCharged = true

        let states: [(name: String, snapshot: BatterySnapshot, estimate: TimeEstimate, lowPower: Bool, details: Bool, history: [HistoryPoint])] = [
            ("battery", live, .untilEmpty(minutes: 648), false, false, history),
            ("battery-details", live, .untilEmpty(minutes: 648), false, true, history),
            ("charging", charging, .untilFull(minutes: 47), false, false, history),
            ("low-power", low, .untilEmpty(minutes: 38), true, false, history),
            ("held", held, .notCharging, false, false, history),
            ("full", full, .charged, false, false, history),
            ("estimating", live, .calculating, false, false, []),
            ("short-history", live, .untilEmpty(minutes: 412), false, false, Array(history.suffix(5))),
        ]

        for state in states {
            preferences.showDetails = state.details
            for scheme in [ColorScheme.dark, .light] {
                let content = PanelContent(
                    snapshot: state.snapshot,
                    estimate: state.estimate,
                    isLowPowerMode: state.lowPower,
                    sessionWatts: 6.4,
                    typicalWatts: 7.9,
                    history: state.history,
                    apps: sampleApps,
                    // Real app icons come out dimmed when rendered offscreen, so these use the fallback symbols.
                    appIcon: { _ in nil },
                    suggestion: state.name == "battery" ? SuggestionEngine.Suggestion(
                        text: "Xcode is using most of your power right now. Quitting it would help your battery last.",
                        isWrittenByAI: true) : nil,
                    preferences: preferences,
                    lowPowerMode: lowPowerMode,
                    actions: PanelActions(openSettings: {}, openBatterySettings: {}, quit: {})
                )
                write(content, scheme: scheme, to: folder.appending(path: "\(state.name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }

        // The notes at the top of the panel (a new version, and Apple's battery icon still in the menu bar), and the welcome guide.
        write(PanelContent(snapshot: live, estimate: .untilEmpty(minutes: 648), isLowPowerMode: false, sessionWatts: 6.4,
                           typicalWatts: 7.9, history: history, showsAppleIconReminder: true,
                           update: UpdateChecker.Update(version: "1.1", download: URL(string: "https://github.com")!),
                           preferences: preferences, lowPowerMode: lowPowerMode,
                           actions: PanelActions(openSettings: {}, openBatterySettings: {}, quit: {})),
              scheme: .dark, to: folder.appending(path: "notices-dark.png"))
        for scheme in [ColorScheme.dark, .light] {
            write(OnboardingView(setup: MenuBarSetup(), onFinish: {}).background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.93)),
                  scheme: scheme, to: folder.appending(path: "welcome-\(scheme == .dark ? "dark" : "light").png"))
        }

        // The Low Power Mode explanation, as it appears before the helper is set up.
        if lowPowerMode.helperStatus != .ready {
            lowPowerMode.requestChange(to: true)
            write(LowPowerModeSection(isOn: false, controller: lowPowerMode).padding(20).frame(width: 340),
                  scheme: .dark, to: folder.appending(path: "helper-explanation-dark.png"))
            lowPowerMode.dismissExplanation()
        }

        renderMenuBarIcons(to: folder)
        preferences.showDetails = savedShowDetails
        print("Rendered snapshots to \(folder.path)")
        exit(0)
    }

    /// Every menu bar battery state side by side, on a dark and a light menu bar, at 6× for inspection.
    static func renderMenuBarIcons(to folder: URL, prefix: String = "menubar") {
        let icons: [NSImage] = [
            BatteryIcon.image(level: 0.93, text: "10:48", badge: .none, fill: nil),
            BatteryIcon.image(level: 0.62, text: "5:12", badge: .none, fill: nil),
            BatteryIcon.image(level: 0.18, text: "0:42", badge: .none, fill: nil),
            BatteryIcon.image(level: 0.06, text: "0:09", badge: .none, fill: .systemRed),
            BatteryIcon.image(level: 0.64, text: "0:47", badge: .charging, fill: .systemGreen),
            BatteryIcon.image(level: 0.35, text: "3:05", badge: .none, fill: .systemYellow),
            BatteryIcon.image(level: 0.80, text: "80", badge: .pluggedIn, fill: nil),
            BatteryIcon.image(level: 0.85, text: "85", badge: .none, fill: nil),
            BatteryIcon.image(level: 0.55, text: nil, badge: .none, fill: nil),
        ]
        let spacing: CGFloat = 10, margin: CGFloat = 8, scale: CGFloat = 6
        let width = icons.reduce(margin * 2) { $0 + $1.size.width } + spacing * CGFloat(icons.count - 1)
        let height: CGFloat = 24

        for (name, appearance, background, ink) in [
            ("dark", NSAppearance(named: .darkAqua)!, NSColor(white: 0.13, alpha: 1), NSColor.white),
            ("light", NSAppearance(named: .aqua)!, NSColor(white: 0.9, alpha: 1), NSColor.black),
        ] {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = NSSize(width: width, height: height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            appearance.performAsCurrentDrawingAppearance {
                background.setFill()
                NSRect(x: 0, y: 0, width: width, height: height).fill()
                var x = margin
                for icon in icons {
                    let rect = NSRect(x: x, y: (height - icon.size.height) / 2, width: icon.size.width, height: icon.size.height)
                    if icon.isTemplate {
                        // What the menu bar does with a template: keep the shape, paint it in the bar's ink.
                        NSImage(size: icon.size, flipped: false) { bounds in
                            icon.draw(in: bounds)
                            ink.set()
                            bounds.fill(using: .sourceAtop)
                            return true
                        }.draw(in: rect)
                    } else {
                        icon.draw(in: rect)
                    }
                    x += icon.size.width + spacing
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appending(path: "\(prefix)-\(name).png"))
        }
    }

    private static let sampleApps = [
        AppEnergyMonitor.App(id: "/Applications/Xcode.app", name: "Xcode", watts: 6.1),
        AppEnergyMonitor.App(id: "/Applications/Safari.app", name: "Safari", watts: 1.4),
        AppEnergyMonitor.App(id: "macOS", name: "macOS services", watts: 0.6),
    ]

    private static func write(_ content: some View, scheme: ColorScheme, to url: URL) {
        let fill = scheme == .dark ? Color(white: 0.16) : Color(white: 0.93)
        let view = content
            .background(fill, in: .rect(cornerRadius: 26))
            .padding(24)
            .background(scheme == .dark ? Color(white: 0.05) : Color(white: 0.7))
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    /// A plausible day: two charges, a long unplugged stretch and a pause held at 80%.
    static func sampleHistory(endingAt finalPercent: Int) -> [HistoryPoint] {
        let segments: [(hours: Double, from: Double, to: Double, charging: Bool, pluggedIn: Bool)] = [
            (1.5, 38, 92, true, true),
            (5.0, 92, 47, false, false),
            (1.0, 47, 80, true, true),
            (3.0, 80, 80, false, true),
            (6.5, 80, 31, false, false),
            (2.0, 31, 100, true, true),
            (5.0, 100, Double(finalPercent), false, false),
        ]
        var points: [HistoryPoint] = []
        var time = Date.now.addingTimeInterval(-24 * 3600)
        for segment in segments {
            let steps = Int(segment.hours * 12)
            for step in 0..<steps {
                let progress = Double(step) / Double(steps)
                points.append(HistoryPoint(
                    date: time.addingTimeInterval(Double(step) * 300),
                    percent: Int((segment.from + (segment.to - segment.from) * progress).rounded()),
                    isCharging: segment.charging,
                    isPluggedIn: segment.pluggedIn,
                    watts: nil
                ))
            }
            time = time.addingTimeInterval(segment.hours * 3600)
        }
        return points
    }
}
#endif
