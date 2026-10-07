import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var preferences: Preferences
    let lowPowerMode: LowPowerModeController
    let updates: UpdateChecker
    let showWelcomeGuide: () -> Void
    @State private var openAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Menu Bar") {
                Picker("Inside the battery", selection: $preferences.menuBarContent) {
                    ForEach(MenuBarContent.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Color the battery when charging, low or in Low Power Mode", isOn: $preferences.colorfulIcon)
                LabeledContent("Apple's battery icon") {
                    Button("Hide in System Settings…") { SystemSettings.openMenuBar() }
                }
            }

            Section("Notifications") {
                Toggle("Low battery", isOn: $preferences.lowBatteryAlert)
                if preferences.lowBatteryAlert {
                    Picker("Notify at", selection: $preferences.lowBatteryThreshold) {
                        ForEach([5, 10, 15, 20, 25, 30], id: \.self) { Text("\($0)%").tag($0) }
                    }
                }
                Toggle("Remind me to unplug", isOn: $preferences.unplugAlert)
                if preferences.unplugAlert {
                    Picker("Remind at", selection: $preferences.unplugThreshold) {
                        ForEach([70, 75, 80, 85, 90, 95], id: \.self) { Text("\($0)%").tag($0) }
                    }
                }
                Toggle("Fully charged", isOn: $preferences.fullyChargedAlert)
            }

            Section {
                Toggle("Show suggestions", isOn: $preferences.showSuggestions)
                Toggle("Write them with Apple Intelligence", isOn: $preferences.useAppleIntelligence)
                    .disabled(!preferences.showSuggestions || !SuggestionEngine.isAppleIntelligenceAvailable)
            } header: {
                Text("Suggestions")
            } footer: {
                Text(SuggestionEngine.isAppleIntelligenceAvailable
                     ? "A suggestion appears only when something stands out, such as an app using far more energy than usual. Apple Intelligence writes it on your Mac from Battery Strip's own readings."
                     : "A suggestion appears only when something stands out, such as an app using far more energy than usual. Turn on Apple Intelligence in System Settings to have them written more naturally.")
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Open at login", isOn: $openAtLogin)
                LabeledContent("Setup") {
                    Button("Show Welcome Guide…", action: showWelcomeGuide)
                }
                Picker("Temperature", selection: $preferences.temperatureUnit) {
                    Text("Celsius").tag(TemperatureUnit.celsius)
                    Text("Fahrenheit").tag(TemperatureUnit.fahrenheit)
                }
            }

            Section {
                LabeledContent("Status", value: helperStatusText)
                if lowPowerMode.helperStatus != .notInstalled {
                    Button("Remove Helper") {
                        Task { await lowPowerMode.removeHelper() }
                    }
                }
            } header: {
                Text("Low Power Mode Helper")
            } footer: {
                Text("macOS only lets system-level tools change power settings, so Battery Strip uses a tiny helper that does nothing except switch Low Power Mode. It's set up the first time you use the switch in the panel.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                Toggle("Check for updates automatically", isOn: $preferences.checkForUpdates)
                LabeledContent {
                    if let update = updates.available {
                        Button("Download") { NSWorkspace.shared.open(update.download) }
                    } else {
                        Button("Check Now") { Task { await updates.check() } }
                            .disabled(updates.state == .checking)
                    }
                } label: {
                    Text(updateStatus)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Twice a week, Battery Strip asks GitHub whether there's a newer version. That's the only time it goes online.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 600)
        .onAppear {
            openAtLogin = LaunchAtLogin.isEnabled
            lowPowerMode.refreshHelperStatus()
        }
        .onChange(of: openAtLogin) { _, enabled in
            guard enabled != LaunchAtLogin.isEnabled else { return }
            LaunchAtLogin.setEnabled(enabled)
            openAtLogin = LaunchAtLogin.isEnabled
        }
        .onChange(of: alertsEnabled) { _, enabled in
            if enabled { Task { await AlertManager.requestPermission() } }
        }
    }

    private var alertsEnabled: Bool {
        preferences.lowBatteryAlert || preferences.unplugAlert || preferences.fullyChargedAlert
    }

    private var updateStatus: String {
        if let update = updates.available { return "Battery Strip \(update.version) is available" }
        switch updates.state {
        case .idle: return "Check for a new version"
        case .checking: return "Checking…"
        case .checked: return "Battery Strip is up to date"
        case .failed: return "Couldn't reach GitHub"
        }
    }

    private var helperStatusText: String {
        switch lowPowerMode.helperStatus {
        case .notInstalled: "Not set up"
        case .requiresApproval: "Waiting for approval in System Settings"
        case .ready: "Ready"
        }
    }
}

enum SystemSettings {
    /// Where the Battery menu bar item is switched on and off.
    static func openMenuBar() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
    }
}
