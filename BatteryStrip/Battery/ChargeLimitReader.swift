import Foundation

/// Reads macOS's own Charge Limit (macOS 26.4 and later: System Settings › Battery › Charging ⓘ).
///
/// It asks `pmset`, which any app may run; the call behind it answers only Apple's own tools. Battery Strip
/// only reads the limit: it's set in System Settings.
nonisolated enum ChargeLimitReader {
    /// The percentage charging stops at, 100 when there's no limit, or nil when it can't be told.
    static func read() -> Int? {
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

    /// The report isn't documented, so anything other than the two known forms counts as unknown.
    static func parse(_ output: String) -> Int? {
        if output.contains("No battery level limits set") { return 100 }
        guard let match = output.firstMatch(of: /chargeSocLimitSoc\s*=\s*(\d+)/),
              let limit = Int(match.1), (50...100).contains(limit)
        else { return nil }
        return limit
    }
}
