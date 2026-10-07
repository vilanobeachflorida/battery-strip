#if DEBUG
import AppKit
import SwiftUI

/// Renders the README's screenshots: the menu bar and the panel on a wallpaper, in dark and light,
/// plus the menu bar battery in each of its states. Debug builds only:
///
///     "Battery Strip.app/Contents/MacOS/Battery Strip" --render-readme Design/Screenshots
///
/// Sample data stands in for this Mac's own, so no real app names appear. The glass can't be
/// captured offscreen, so a blurred copy of the wallpaper approximates it.
enum ReadmeRenderer {
    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--render-readme"), index + 1 < arguments.count else { return }
        let folder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        guard var snapshot = BatteryReader.read(includeTemperature: false) else {
            print("No battery to render")
            exit(1)
        }
        snapshot.percent = 76
        snapshot.isPluggedIn = false
        snapshot.isCharging = false
        snapshot.isFullyCharged = false
        snapshot.voltage = 12.3
        snapshot.amperage = -0.62
        snapshot.temperature = 31
        snapshot.maximumCapacityPercent = 98
        snapshot.cycleCount = 124
        snapshot.designCycleCount = 1000

        let apps = [
            AppEnergyMonitor.App(id: "/Applications/Xcode.app", name: "Xcode", watts: 4.6),
            AppEnergyMonitor.App(id: "/Applications/Safari.app", name: "Safari", watts: 1.3),
            AppEnergyMonitor.App(id: "/System/Applications/Music.app", name: "Music", watts: 0.4),
        ]
        var icons: [String: NSImage] = [:]
        for app in apps { icons[app.id] = bitmapIcon(app.id) }
        let suggestion = SuggestionEngine.Suggestion(
            text: "Xcode is using far more energy than your other apps. Quit it when you're done to stretch your battery.",
            isWrittenByAI: true
        )
        let history = SnapshotRenderer.sampleHistory(endingAt: snapshot.percent)

        for scheme in [ColorScheme.dark, .light] {
            let hero = Hero(scheme: scheme, snapshot: snapshot, history: history, apps: apps, icons: icons, suggestion: suggestion)
                .environment(\.colorScheme, scheme)
            write(hero, to: folder.appending(path: "panel-\(scheme == .dark ? "dark" : "light").jpg"))
        }
        SnapshotRenderer.renderMenuBarIcons(to: folder, prefix: "menu-bar-states")
        print("Rendered README images to \(folder.path)")
        exit(0)
    }

    /// JPEG, because the soft wallpaper gradients make PNGs several megabytes.
    private static func write(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let jpeg = NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return }
        try? jpeg.write(to: url)
    }

    /// App icons drawn to a plain bitmap first; drawn directly offscreen, they come out dimmed.
    private static func bitmapIcon(_ path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path),
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = NSSize(width: 32, height: 32)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSWorkspace.shared.icon(forFile: path).draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Views

    /// A slice of desktop: the menu bar with Battery Strip's battery, and its panel hanging below.
    private struct Hero: View {
        let scheme: ColorScheme
        let snapshot: BatterySnapshot
        let history: [HistoryPoint]
        let apps: [AppEnergyMonitor.App]
        let icons: [String: NSImage]
        let suggestion: SuggestionEngine.Suggestion

        var body: some View {
            VStack(alignment: .trailing, spacing: 10) {
                MenuBar(scheme: scheme, level: Double(snapshot.percent) / 100, time: "6:52")
                Panel(snapshot: snapshot, history: history, apps: apps, icons: icons, suggestion: suggestion)
                    .background {
                        Wallpaper(scheme: scheme)
                            .blur(radius: 40)
                            .overlay(scheme == .dark ? Color.black.opacity(0.34) : Color.white.opacity(0.52))
                    }
                    .clipShape(.rect(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(scheme == .dark ? 0.14 : 0.7), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 28, y: 14)
                    .padding(.trailing, 150)
            }
            .padding(.bottom, 60)
            .frame(width: 860)
            .background(Wallpaper(scheme: scheme))
        }
    }

    private struct MenuBar: View {
        let scheme: ColorScheme
        let level: Double
        let time: String

        var body: some View {
            HStack(spacing: 18) {
                Image(systemName: "applelogo")
                Text("Finder").fontWeight(.bold)
                ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) { Text($0) }
                Spacer()
                Image(nsImage: BatteryIcon.image(level: level, text: time, badge: .none, fill: nil))
                Image(systemName: "wifi")
                Image(systemName: "magnifyingglass")
                Image(systemName: "switch.2")
                Text("Tue Oct 7  9:41 AM")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(scheme == .dark ? Color.white : Color.black)
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(scheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.3))
        }
    }

    /// The panel's sections, as in PanelContent, with a drawn switch: the real one can't be drawn offscreen.
    private struct Panel: View {
        let snapshot: BatterySnapshot
        let history: [HistoryPoint]
        let apps: [AppEnergyMonitor.App]
        let icons: [String: NSImage]
        let suggestion: SuggestionEngine.Suggestion

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HeroSection(snapshot: snapshot, estimate: .untilEmpty(minutes: 412), isLowPowerMode: false, sessionWatts: 7.4, typicalWatts: 5.1)
                SuggestionCard(suggestion: suggestion)
                StatTiles(snapshot: snapshot, temperatureUnit: Preferences.shared.temperatureUnit)
                EnergySection(apps: apps, icon: { icons[$0] })
                HistoryChart(points: history)
                DetailsSection(snapshot: snapshot, isExpanded: .constant(false))
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: "leaf.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Low Power Mode")
                        Text("Use less energy to last longer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Capsule()
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 32, height: 18)
                        .overlay(alignment: .leading) {
                            Circle()
                                .fill(.white)
                                .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                                .padding(2)
                        }
                }
                PanelFooter(actions: PanelActions(openSettings: {}, openBatterySettings: {}, quit: {}))
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .frame(width: PanelController.width)
        }
    }

    private struct Wallpaper: View {
        let scheme: ColorScheme

        var body: some View {
            let dark = scheme == .dark
            ZStack {
                LinearGradient(
                    colors: dark
                        ? [Color(red: 0.05, green: 0.07, blue: 0.17), Color(red: 0.17, green: 0.08, blue: 0.31)]
                        : [Color(red: 0.60, green: 0.74, blue: 0.98), Color(red: 0.94, green: 0.81, blue: 0.95)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Circle()
                    .fill(dark ? Color(red: 0.96, green: 0.45, blue: 0.24) : Color(red: 1.0, green: 0.76, blue: 0.55))
                    .frame(width: 460, height: 460)
                    .blur(radius: 130)
                    .offset(x: -210, y: 260)
                Circle()
                    .fill(dark ? Color(red: 0.12, green: 0.62, blue: 0.74) : Color(red: 0.55, green: 0.86, blue: 0.96))
                    .frame(width: 420, height: 420)
                    .blur(radius: 130)
                    .offset(x: 240, y: -240)
            }
        }
    }
}
#endif
