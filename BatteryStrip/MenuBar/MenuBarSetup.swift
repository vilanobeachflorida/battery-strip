import Foundation
import Observation

/// Whether Apple's own battery icon is still in the menu bar next to Battery Strip's.
@Observable
final class MenuBarSetup {
    /// Nil when it can't be told. There's no public setting for this, so it reads Control Center's
    /// preferences, which only hold the items someone has changed.
    private(set) var isAppleBatteryIconShown: Bool?

    init() {
        refresh()
    }

    func refresh() {
        let shown = Self.readAppleBatteryIconShown()
        if shown != isAppleBatteryIconShown { isAppleBatteryIconShown = shown }
    }

    private static func readAppleBatteryIconShown() -> Bool? {
        let domain = "com.apple.controlcenter" as CFString
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        guard let flags = CFPreferencesCopyValue("Battery" as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Int
        else { return nil }
        // Control Center stores each item's placement as flags; 2 means it's shown in the menu bar.
        return flags & 2 != 0
    }
}
