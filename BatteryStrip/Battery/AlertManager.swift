import Foundation
import UserNotifications

/// Sends the optional low-battery, unplug-reminder and fully-charged notifications.
final class AlertManager: NSObject, UNUserNotificationCenterDelegate {
    private let monitor: BatteryMonitor
    private let preferences: Preferences

    init(monitor: BatteryMonitor, preferences: Preferences) {
        self.monitor = monitor
        self.preferences = preferences
        super.init()
        UNUserNotificationCenter.current().delegate = self
        monitor.onNewReading = { [weak self] previous, current in
            self?.evaluate(previous: previous, current: current)
        }
    }

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private func evaluate(previous: BatterySnapshot?, current: BatterySnapshot) {
        guard let previous else { return }

        let low = preferences.lowBatteryThreshold
        if preferences.lowBatteryAlert, !current.isPluggedIn, current.percent <= low, previous.percent > low {
            var body = "Plug in soon."
            if case .untilEmpty(let minutes) = monitor.estimate {
                body = "About \(Format.duration(minutes)) left at your current usage."
            }
            post(id: "low-battery", title: "Battery at \(current.percent)%", body: body)
        }

        let unplug = preferences.unplugThreshold
        if preferences.unplugAlert, current.isPluggedIn, current.percent >= unplug, previous.percent < unplug {
            post(id: "unplug", title: "Charged to \(current.percent)%",
                 body: "You can unplug now. Not sitting at 100% helps the battery last longer.")
        }

        let isFull = current.isFullyCharged || current.percent >= 100
        let wasFull = previous.isFullyCharged || previous.percent >= 100
        if preferences.fullyChargedAlert, current.isPluggedIn, isFull, !wasFull {
            post(id: "fully-charged", title: "Fully charged", body: "Your Mac is at 100%.")
        }
    }

    private func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // Show banners even though a menu bar app counts as frontmost.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
