import Foundation

/// Names shared by the app and its Low Power Mode helper.
nonisolated enum HelperConstants {
    static let machServiceName = "com.batterystrip.BatteryStrip.Helper3"
    static let launchDaemonPlistName = "com.batterystrip.BatteryStrip.Helper3.plist"
    static let appBundleIdentifier = "com.batterystrip.BatteryStrip"
}

/// The helper's whole interface. It deliberately does one thing.
@objc nonisolated protocol BatteryStripHelperProtocol {
    func setLowPowerMode(_ enabled: Bool, reply: @escaping @Sendable (_ success: Bool, _ message: String?) -> Void)
}
