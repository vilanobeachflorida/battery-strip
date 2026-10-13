import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private let monitor = BatteryMonitor()
    private lazy var lowPowerMode = LowPowerModeController()
    private let setup = MenuBarSetup()
    private let energy = AppEnergyMonitor()
    private let suggestions = SuggestionEngine()
    private lazy var updates = UpdateChecker(preferences: preferences)
    private lazy var windows = WindowManager(preferences: preferences, monitor: monitor, lowPowerMode: lowPowerMode, setup: setup,
                                                updates: updates)
    private var statusItem: StatusItemController?
    private var alerts: AlertManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        Diagnostics.runIfRequested()
        SnapshotRenderer.runIfRequested(lowPowerMode: lowPowerMode)
        ReadmeRenderer.runIfRequested()
        // Removes this build's open-at-login registration, for cleaning up after testing a build.
        if ProcessInfo.processInfo.arguments.contains("--disable-open-at-login") {
            LaunchAtLogin.setEnabled(false)
            print("Open at login is now \(LaunchAtLogin.isEnabled ? "on" : "off") for \(Bundle.main.bundlePath)")
            exit(0)
        }
        #endif
        // Before anything registers itself at this location, such as opening at login.
        if ApplicationsFolderMover.offerIfNeeded() { return }
        NSApp.mainMenu = MainMenu.make()
        monitor.start()
        energy.start()
        updates.start()
        alerts = AlertManager(monitor: monitor, preferences: preferences)
        // Each new battery reading, about once a minute, also checks the alerts and samples app energy,
        // so the app wakes once a minute rather than once per job.
        monitor.onNewReading = { [weak self] previous, current in
            self?.alerts?.evaluate(previous: previous, current: current)
            self?.energy.batteryDidUpdate()
        }
        statusItem = StatusItemController(monitor: monitor, preferences: preferences, lowPowerMode: lowPowerMode, setup: setup,
                                          energy: energy, suggestions: suggestions, updates: updates, windows: windows)
        if !preferences.hasCompletedOnboarding {
            // It stands in for a system icon, so it should be there after every restart. The welcome guide
            // shows this switched on, and it can be turned off there or in Settings. Not from the disk image
            // or Downloads, though, where a login item would stop working once the app is moved or ejected.
            if ApplicationsFolderMover.isRunningFromApplications {
                LaunchAtLogin.setEnabled(true)
            }
            windows.showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.saveState()
    }

    /// Opening the app again from Finder or Spotlight shows Settings, since there's no Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showSettings()
        return false
    }

    @objc func showSettings(_ sender: Any?) {
        windows.showSettings()
    }
}
