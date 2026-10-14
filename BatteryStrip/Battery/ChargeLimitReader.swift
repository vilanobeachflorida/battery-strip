import Foundation

/// Reads macOS's own charge limits: the Charge Limit set in System Settings › Battery › Charging ⓘ (macOS 26.4
/// and later), and where Optimized Battery Charging is holding the battery for now.
///
/// It asks `pmset`, which any app may run; the call behind it answers only Apple's own tools. Battery Strip
/// only reads the limits: they're set in System Settings.
nonisolated enum ChargeLimitReader {
    struct Limits: Equatable {
        /// The Charge Limit set in System Settings, or 100 when there's none.
        var manual: Int
        /// Where Optimized Battery Charging is holding the battery until it's needed, when it is.
        var optimizedHold: Int?
    }

    /// Nil when they can't be told.
    static func read() -> Limits? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "battlimit"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parse(output)
    }

    /// The report isn't documented, so anything that doesn't parse cleanly counts as unknown. It lists one
    /// entry per limit, such as `{ Terminated = 0; chargeSocLimitReason = manualChargeLimit; chargeSocLimitSoc = 95; }`.
    static func parse(_ output: String) -> Limits? {
        if output.contains("No battery level limits set") { return Limits(manual: 100, optimizedHold: nil) }
        var sawLimit = false
        var manual: Int?, optimizedHold: Int?, unlabeled: Int?
        for entry in output.split(separator: "}") {
            guard let soc = entry.firstMatch(of: /chargeSocLimitSoc\s*=\s*(\d+)/).flatMap({ Int($0.1) }),
                  (50...100).contains(soc)
            else { continue }
            sawLimit = true
            guard entry.firstMatch(of: /Terminated\s*=\s*1\b/) == nil else { continue }
            switch entry.firstMatch(of: /chargeSocLimitReason\s*=\s*"?(\w+)/).map({ String($0.1) }) {
            case "manualChargeLimit": manual = min(manual ?? 100, soc)
            case "optimizedBatteryCharging": optimizedHold = min(optimizedHold ?? 100, soc)
            case nil: unlabeled = min(unlabeled ?? 100, soc)
            default: break
            }
        }
        guard sawLimit else { return nil }
        // An older report without reasons lists only the Charge Limit.
        return Limits(manual: manual ?? unlabeled ?? 100, optimizedHold: optimizedHold)
    }
}
