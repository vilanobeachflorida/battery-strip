import AppKit
import SwiftUI

/// The first-run guide: where Battery Strip lives, hiding Apple's battery icon, and opening at login.
struct OnboardingView: View {
    let setup: MenuBarSetup
    let onFinish: () -> Void
    @State private var openAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                Text("Welcome to Battery Strip")
                    .font(.largeTitle.weight(.semibold))
                Text("Time remaining, health and history, right in your menu bar.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 20) {
                Step(number: 1, isDone: false, title: "Find it in your menu bar",
                     detail: "The battery with the time inside is Battery Strip. Click it any time for health, temperature and history.") {
                    MenuBarPreview()
                }
                Step(number: 2, isDone: false, title: "Move it where you like",
                     detail: "Hold Command and drag the battery left or right along the menu bar. This works for any icon up there, so you can tidy the whole bar.") {
                    HStack(spacing: 6) {
                        KeyCap("⌘ Command")
                        Text("+ drag")
                            .foregroundStyle(.secondary)
                    }
                }
                Step(number: 3, isDone: setup.isAppleBatteryIconShown == false, title: "Hide Apple's battery icon",
                     detail: "So you don't see two batteries. In System Settings, open Menu Bar, then under Menu Bar Controls, turn off Battery.") {
                    if setup.isAppleBatteryIconShown == false {
                        Label("Done. Apple's battery icon is hidden.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open Menu Bar Settings") { SystemSettings.openMenuBar() }
                    }
                }
                Step(number: 4, isDone: openAtLogin, title: "Opens when you log in",
                     detail: "Battery Strip starts with your Mac, so it's always there. It uses next to no energy.") {
                    Toggle("Open at login", isOn: $openAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            Button("Done", action: onFinish)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 40)
        .padding(.top, 36)
        .padding(.bottom, 32)
        .frame(width: 520)
        .animation(.snappy, value: setup.isAppleBatteryIconShown)
        .onChange(of: openAtLogin) { _, enabled in
            guard enabled != LaunchAtLogin.isEnabled else { return }
            LaunchAtLogin.setEnabled(enabled)
            openAtLogin = LaunchAtLogin.isEnabled
        }
        // Notice when Apple's icon gets hidden in System Settings, for as long as this guide is open.
        .task {
            while !Task.isCancelled {
                setup.refresh()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }
}

/// A keyboard key, drawn the way macOS shows shortcuts.
private struct KeyCap: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.tertiary, lineWidth: 0.5))
    }
}

/// A slice of menu bar showing what Battery Strip's battery looks like.
private struct MenuBarPreview: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "wifi")
            Image(nsImage: BatteryIcon.image(level: 0.72, text: "4:32", badge: .none, fill: nil))
                .resizable()
                .interpolation(.high)
                .frame(width: 58, height: 26)
            Text("Tue 9:41 AM")
        }
        .font(.system(size: 15))
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.6), in: .capsule)
        .accessibilityLabel("Battery Strip in the menu bar, showing 4 hours 32 minutes left")
    }
}

private struct Step<Accessory: View>: View {
    let number: Int
    let isDone: Bool
    let title: String
    let detail: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(.green, in: .circle)
                } else {
                    Text("\(number)")
                        .font(.callout.weight(.semibold))
                        .frame(width: 26, height: 26)
                        .background(.quaternary, in: .circle)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory.padding(.top, 6)
            }
        }
    }
}
