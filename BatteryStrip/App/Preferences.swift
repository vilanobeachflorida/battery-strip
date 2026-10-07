import Foundation
import Observation

/// What the menu bar battery shows inside it.
enum MenuBarContent: String, CaseIterable, Identifiable {
    case time, percentage, empty

    var id: Self { self }

    var title: String {
        switch self {
        case .time: "Time remaining"
        case .percentage: "Percentage"
        case .empty: "Nothing"
        }
    }
}

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit

    var id: Self { self }
}

/// Settings, saved to UserDefaults as they change.
@Observable
final class Preferences {
    static let shared = Preferences()

    var menuBarContent: MenuBarContent { didSet { save(menuBarContent.rawValue, Key.menuBarContent) } }
    var colorfulIcon: Bool { didSet { save(colorfulIcon, Key.colorfulIcon) } }
    var temperatureUnit: TemperatureUnit { didSet { save(temperatureUnit.rawValue, Key.temperatureUnit) } }
    var showDetails: Bool { didSet { save(showDetails, Key.showDetails) } }
    var lowBatteryAlert: Bool { didSet { save(lowBatteryAlert, Key.lowBatteryAlert) } }
    var lowBatteryThreshold: Int { didSet { save(lowBatteryThreshold, Key.lowBatteryThreshold) } }
    var unplugAlert: Bool { didSet { save(unplugAlert, Key.unplugAlert) } }
    var unplugThreshold: Int { didSet { save(unplugThreshold, Key.unplugThreshold) } }
    var fullyChargedAlert: Bool { didSet { save(fullyChargedAlert, Key.fullyChargedAlert) } }
    var hasCompletedOnboarding: Bool { didSet { save(hasCompletedOnboarding, Key.hasCompletedOnboarding) } }
    var dismissedAppleIconReminder: Bool { didSet { save(dismissedAppleIconReminder, Key.dismissedAppleIconReminder) } }
    var showSuggestions: Bool { didSet { save(showSuggestions, Key.showSuggestions) } }
    var useAppleIntelligence: Bool { didSet { save(useAppleIntelligence, Key.useAppleIntelligence) } }
    var checkForUpdates: Bool { didSet { save(checkForUpdates, Key.checkForUpdates) } }

    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Key {
        static let menuBarContent = "MenuBarContent"
        static let colorfulIcon = "ColorfulIcon"
        static let temperatureUnit = "TemperatureUnit"
        static let showDetails = "ShowDetails"
        static let lowBatteryAlert = "LowBatteryAlert"
        static let lowBatteryThreshold = "LowBatteryThreshold"
        static let unplugAlert = "UnplugAlert"
        static let unplugThreshold = "UnplugThreshold"
        static let fullyChargedAlert = "FullyChargedAlert"
        static let hasCompletedOnboarding = "HasCompletedOnboarding"
        static let dismissedAppleIconReminder = "DismissedAppleIconReminder"
        static let showSuggestions = "ShowSuggestions"
        static let useAppleIntelligence = "UseAppleIntelligence"
        static let checkForUpdates = "CheckForUpdates"
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.colorfulIcon: true,
            Key.showSuggestions: true,
            Key.useAppleIntelligence: true,
            Key.checkForUpdates: true,
            Key.lowBatteryThreshold: 20,
            Key.unplugThreshold: 80,
        ])
        menuBarContent = defaults.string(forKey: Key.menuBarContent).flatMap(MenuBarContent.init) ?? .time
        colorfulIcon = defaults.bool(forKey: Key.colorfulIcon)
        temperatureUnit = defaults.string(forKey: Key.temperatureUnit).flatMap(TemperatureUnit.init)
            ?? (Locale.current.measurementSystem == .us ? .fahrenheit : .celsius)
        showDetails = defaults.bool(forKey: Key.showDetails)
        lowBatteryAlert = defaults.bool(forKey: Key.lowBatteryAlert)
        lowBatteryThreshold = defaults.integer(forKey: Key.lowBatteryThreshold)
        unplugAlert = defaults.bool(forKey: Key.unplugAlert)
        unplugThreshold = defaults.integer(forKey: Key.unplugThreshold)
        fullyChargedAlert = defaults.bool(forKey: Key.fullyChargedAlert)
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        dismissedAppleIconReminder = defaults.bool(forKey: Key.dismissedAppleIconReminder)
        showSuggestions = defaults.bool(forKey: Key.showSuggestions)
        useAppleIntelligence = defaults.bool(forKey: Key.useAppleIntelligence)
        checkForUpdates = defaults.bool(forKey: Key.checkForUpdates)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
