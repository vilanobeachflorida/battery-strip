import AppKit
import SwiftUI

/// Opens the Settings and Welcome windows. A menu bar app has no Dock icon, so these bring the app forward.
final class WindowManager: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private let lowPowerMode: LowPowerModeController
    private let setup: MenuBarSetup
    private let updates: UpdateChecker
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    init(preferences: Preferences, lowPowerMode: LowPowerModeController, setup: MenuBarSetup, updates: UpdateChecker) {
        self.preferences = preferences
        self.lowPowerMode = lowPowerMode
        self.setup = setup
        self.updates = updates
    }

    func showSettings() {
        let window = settingsWindow ?? makeWindow(
            title: "Battery Strip Settings",
            content: SettingsView(preferences: preferences, lowPowerMode: lowPowerMode, updates: updates) { [weak self] in
                self?.showOnboarding()
            }
        )
        settingsWindow = window
        present(window)
    }

    func showOnboarding() {
        let window = onboardingWindow ?? makeWindow(
            title: "Welcome to Battery Strip",
            content: OnboardingView(setup: setup) { [weak self] in
                self?.onboardingWindow?.close()
            }
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        // Released when closed, which also stops it watching the menu bar setting.
        window.delegate = self
        onboardingWindow = window
        // Don't greet again on the next launch, even if this window is simply closed.
        preferences.hasCompletedOnboarding = true
        present(window)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === onboardingWindow {
            onboardingWindow = nil
        }
    }

    private func makeWindow(title: String, content: some View) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
