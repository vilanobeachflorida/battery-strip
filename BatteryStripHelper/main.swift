import Foundation
import Security

// A tiny root helper with one job: switching Low Power Mode, which macOS only lets root do.
// launchd starts it when Battery Strip connects, and it exits again once it's idle.

final class HelperService: NSObject, NSXPCListenerDelegate, BatteryStripHelperProtocol, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.batterystrip.helper")
    private var idleExit: DispatchWorkItem?

    /// The signature a caller must have. When the helper is signed with a Developer ID, only the app
    /// signed by the same team gets through; a development build signed ad hoc can only check the app's identifier.
    private let clientRequirement: String = {
        let identifier = "identifier \"\(HelperConstants.appBundleIdentifier)\""
        guard let team = HelperService.ownTeamIdentifier() else { return identifier }
        return "anchor apple generic and \(identifier) and certificate leaf[subject.OU] = \"\(team)\""
    }()

    private static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess
        else { return nil }
        return (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: BatteryStripHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        scheduleIdleExit()
        return true
    }

    func setLowPowerMode(_ enabled: Bool, reply: @escaping @Sendable (Bool, String?) -> Void) {
        defer { scheduleIdleExit() }
        do {
            try PowerSettings.setLowPowerMode(enabled)
            reply(true, nil)
        } catch {
            reply(false, "\(error)")
        }
    }

    private func scheduleIdleExit() {
        queue.async { [self] in
            idleExit?.cancel()
            let work = DispatchWorkItem { exit(0) }
            idleExit = work
            queue.asyncAfter(deadline: .now() + 30, execute: work)
        }
    }
}

enum PowerSettings {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func setLowPowerMode(_ enabled: Bool) throws {
        let settings = try pmset(["-g", "custom"])
        // Newer Macs call the setting "powermode" (0 automatic, 1 low power, 2 high power); older ones "lowpowermode".
        let key = settings.contains(" powermode ") ? "powermode" : "lowpowermode"
        if enabled {
            try pmset(["-a", key, "1"])
        } else {
            // Only switch off the power sources that are in Low Power Mode, so a High Power setting survives.
            for (flag, section) in [("-b", "Battery Power:"), ("-c", "AC Power:")]
            where value(of: key, in: settings, section: section) == 1 {
                try pmset([flag, key, "0"])
            }
        }
    }

    /// Reads one setting from a section of `pmset -g custom` output.
    static func value(of key: String, in output: String, section: String) -> Int? {
        var inSection = false
        for line in output.split(separator: "\n") {
            if !line.hasPrefix(" ") {
                inSection = line.hasPrefix(section)
                continue
            }
            guard inSection else { continue }
            let parts = line.split(separator: " ")
            if parts.count >= 2, parts[0] == key {
                return Int(parts[1])
            }
        }
        return nil
    }

    @discardableResult
    static func pmset(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure(description: output.isEmpty ? "pmset exited with status \(process.terminationStatus)" : output)
        }
        return output
    }
}

let service = HelperService()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = service
listener.resume()
dispatchMain()
