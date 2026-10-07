import AppKit
import SwiftUI

struct PanelActions {
    var openSettings: () -> Void
    var openBatterySettings: () -> Void
    var quit: () -> Void
}

/// The drop-down panel, fed live from the monitor.
struct PanelView: View {
    let monitor: BatteryMonitor
    let preferences: Preferences
    let lowPowerMode: LowPowerModeController
    let setup: MenuBarSetup
    let energy: AppEnergyMonitor
    let suggestions: SuggestionEngine
    let updates: UpdateChecker
    let actions: PanelActions

    var body: some View {
        if monitor.isPanelVisible {
            content
        } else {
            // Not built while closed, so the once-a-minute updates cost next to nothing.
            Color.clear.frame(width: PanelController.width, height: 0)
        }
    }

    private var content: some View {
        PanelContent(
            snapshot: monitor.snapshot,
            estimate: monitor.estimate,
            isLowPowerMode: monitor.isLowPowerModeEnabled,
            sessionWatts: monitor.sessionWatts,
            typicalWatts: monitor.typicalWatts,
            history: monitor.history.points,
            apps: energy.topApps,
            appIcon: energy.icon(for:),
            suggestion: preferences.showSuggestions ? suggestions.suggestion : nil,
            showsAppleIconReminder: setup.isAppleBatteryIconShown == true && !preferences.dismissedAppleIconReminder,
            update: updates.notice,
            dismissUpdate: updates.dismiss,
            preferences: preferences,
            lowPowerMode: lowPowerMode,
            actions: actions
        )
    }
}

/// Everything in the drop-down panel.
struct PanelContent: View {
    let snapshot: BatterySnapshot?
    let estimate: TimeEstimate
    let isLowPowerMode: Bool
    let sessionWatts: Double?
    let typicalWatts: Double?
    let history: [HistoryPoint]
    var apps: [AppEnergyMonitor.App] = []
    var appIcon: (String) -> NSImage? = { _ in nil }
    var suggestion: SuggestionEngine.Suggestion?
    var showsAppleIconReminder = false
    var update: UpdateChecker.Update?
    var dismissUpdate: () -> Void = {}
    @Bindable var preferences: Preferences
    let lowPowerMode: LowPowerModeController
    let actions: PanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let update {
                PanelNotice(systemImage: "arrow.down.circle", text: "Battery Strip \(update.version) is available.",
                            actionTitle: "Download", action: { NSWorkspace.shared.open(update.download) },
                            dismissHelp: "Hide until the next version", onDismiss: dismissUpdate)
            }
            if showsAppleIconReminder {
                // So people don't end up with two batteries in the menu bar.
                PanelNotice(systemImage: "rectangle.on.rectangle", text: "Apple's battery icon is still in your menu bar.",
                            actionTitle: "Hide It", action: SystemSettings.openMenuBar,
                            dismissHelp: "Don't show this again") { preferences.dismissedAppleIconReminder = true }
            }
            if let snapshot {
                HeroSection(
                    snapshot: snapshot,
                    estimate: estimate,
                    isLowPowerMode: isLowPowerMode,
                    sessionWatts: sessionWatts,
                    typicalWatts: typicalWatts
                )
                if let suggestion {
                    SuggestionCard(suggestion: suggestion)
                        .transition(.opacity)
                }
                StatTiles(snapshot: snapshot, temperatureUnit: preferences.temperatureUnit)
                EnergySection(apps: apps, icon: appIcon)
                HistoryChart(points: history)
                DetailsSection(snapshot: snapshot, isExpanded: $preferences.showDetails)
            } else {
                ContentUnavailableView(
                    "No Battery Found",
                    systemImage: "battery.0percent",
                    description: Text("Battery Strip shows the battery of a Mac laptop.")
                )
            }
            Divider()
            LowPowerModeSection(isOn: isLowPowerMode, controller: lowPowerMode)
            PanelFooter(actions: actions)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .frame(width: PanelController.width)
        .animation(.snappy, value: suggestion)
    }
}

/// A one-line note at the top of the panel, with one action and a close button.
struct PanelNotice: View {
    let systemImage: String
    let text: String
    let actionTitle: String
    let action: () -> Void
    let dismissHelp: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(actionTitle, action: action)
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(dismissHelp)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12))
    }
}

struct PanelFooter: View {
    let actions: PanelActions
    @State private var isConfirmingQuit = false

    var body: some View {
        HStack(spacing: 2) {
            if isConfirmingQuit {
                Text("Quit Battery Strip?")
                    .padding(.horizontal, 8)
                Spacer()
                Button("Quit", role: .destructive, action: actions.quit)
                // Cancel sits where the power button was, so a double click can't quit by accident.
                Button("Cancel") { isConfirmingQuit = false }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Battery Settings…", action: actions.openBatterySettings)
                Spacer()
                Button(action: actions.openSettings) {
                    Image(systemName: "gearshape")
                }
                .help("Battery Strip Settings")
                Button {
                    isConfirmingQuit = true
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit Battery Strip")
            }
        }
        .buttonStyle(HoverButtonStyle())
        .font(.callout)
        .padding(.horizontal, -8)
        .animation(.snappy, value: isConfirmingQuit)
        // Don't leave the question waiting for the next time the panel opens.
        .task(id: isConfirmingQuit) {
            guard isConfirmingQuit else { return }
            try? await Task.sleep(for: .seconds(5))
            isConfirmingQuit = false
        }
    }
}

/// A quiet button that shows a soft highlight on hover, like menu items. Destructive buttons are solid red.
struct HoverButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let isDestructive = configuration.role == .destructive
        configuration.label
            .fontWeight(isDestructive ? .semibold : nil)
            .foregroundStyle(isDestructive ? AnyShapeStyle(.white) : isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(background(isDestructive: isDestructive, isPressed: configuration.isPressed), in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
            .onHover { isHovered = $0 }
    }

    private func background(isDestructive: Bool, isPressed: Bool) -> AnyShapeStyle {
        if isDestructive { return AnyShapeStyle(Color.red.opacity(isPressed ? 0.7 : isHovered ? 1 : 0.85)) }
        return AnyShapeStyle(.quaternary.opacity(isPressed ? 1 : isHovered ? 0.7 : 0))
    }
}
