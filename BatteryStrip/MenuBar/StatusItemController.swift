import AppKit
import SwiftUI

/// Owns the menu bar item: draws the battery and time, and opens the panel.
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let monitor: BatteryMonitor
    private let preferences: Preferences
    private let energy: AppEnergyMonitor
    private let suggestions: SuggestionEngine
    private let windows: WindowManager
    private let panel = PanelController()

    init(monitor: BatteryMonitor, preferences: Preferences, lowPowerMode: LowPowerModeController, setup: MenuBarSetup,
         energy: AppEnergyMonitor, suggestions: SuggestionEngine, updates: UpdateChecker, windows: WindowManager) {
        self.monitor = monitor
        self.preferences = preferences
        self.energy = energy
        self.suggestions = suggestions
        self.windows = windows
        super.init()

        let actions = PanelActions(
            openSettings: { [weak self] in
                self?.panel.close()
                windows.showSettings()
            },
            openBatterySettings: { [weak self] in
                self?.panel.close()
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
            },
            quit: { NSApp.terminate(nil) }
        )
        panel.setContent(PanelView(monitor: monitor, preferences: preferences, lowPowerMode: lowPowerMode, setup: setup,
                                   energy: energy, suggestions: suggestions, updates: updates, actions: actions))
        panel.onVisibilityChange = { [weak self] isVisible in
            self?.monitor.isPanelVisible = isVisible
            if isVisible {
                lowPowerMode.refreshHelperStatus()
                setup.refresh()
                energy.refresh()
                self?.updateSuggestion()
            }
        }

        statusItem.autosaveName = "BatteryStrip"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }
        render()
    }

    /// Redraws now, and again whenever anything it reads changes.
    private func render() {
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
    }

    private func update() {
        guard let button = statusItem.button else { return }
        guard let snapshot = monitor.snapshot else {
            button.image = NSImage(systemSymbolName: "battery.0percent", accessibilityDescription: "No battery")
            return
        }

        var fill: NSColor?
        if preferences.colorfulIcon {
            if !snapshot.isPluggedIn && snapshot.percent <= 10 {
                fill = .systemRed
            } else if monitor.isLowPowerModeEnabled {
                fill = .systemYellow
            } else if snapshot.isCharging {
                fill = .systemGreen
            }
        }
        let badge: BatteryIcon.Badge = snapshot.isCharging ? .charging : snapshot.isPluggedIn ? .pluggedIn : .none
        button.image = BatteryIcon.image(level: Double(snapshot.percent) / 100, text: iconText(for: snapshot), badge: badge, fill: fill)

        var description = "Battery \(snapshot.percent) percent"
        var tooltip = "\(snapshot.percent)%"
        switch monitor.estimate {
        case .untilEmpty(let minutes):
            description += ", \(Format.spokenDuration(minutes)) remaining"
            tooltip = "\(Format.duration(minutes)) left · " + tooltip
        case .untilFull(let minutes):
            description += ", \(Format.spokenDuration(minutes)) until full"
            tooltip = "\(Format.duration(minutes)) until full · " + tooltip
        case .charged:
            description += ", fully charged"
        case .notCharging:
            description += ", not charging"
            tooltip += " · not charging"
        case .calculating:
            break
        }
        button.toolTip = tooltip
        button.setAccessibilityLabel(description)
    }

    private func updateSuggestion() {
        guard preferences.showSuggestions, let snapshot = monitor.snapshot else { return }
        let facts = SuggestionFacts(
            percent: snapshot.percent,
            isPluggedIn: snapshot.isPluggedIn,
            isCharging: snapshot.isCharging,
            estimate: monitor.estimate,
            watts: snapshot.isPluggedIn ? snapshot.systemPower ?? 0 : abs(snapshot.batteryPower),
            averageWatts: monitor.sessionWatts,
            typicalWatts: monitor.typicalWatts,
            topApps: energy.topApps.map { ($0.name, $0.watts) },
            isLowPowerMode: monitor.isLowPowerModeEnabled,
            health: snapshot.maximumCapacityPercent,
            temperatureCelsius: snapshot.temperature,
            temperatureText: snapshot.temperature.map { Format.temperature($0, unit: preferences.temperatureUnit) }
        )
        suggestions.update(with: facts, useAppleIntelligence: preferences.useAppleIntelligence)
    }

    /// Inside the battery the units go without saying: "2:06" is time left, "85" a percentage.
    private func iconText(for snapshot: BatterySnapshot) -> String? {
        switch preferences.menuBarContent {
        case .empty: nil
        case .percentage: "\(snapshot.percent)"
        case .time: monitor.estimate.minutes.map(Format.clock) ?? "\(snapshot.percent)"
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard NSApp.currentEvent?.type == .rightMouseUp else {
            panel.toggle(relativeTo: sender)
            return
        }
        panel.close()
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Battery Strip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 5), in: sender)
    }

    @objc private func openSettings() {
        windows.showSettings()
    }
}
