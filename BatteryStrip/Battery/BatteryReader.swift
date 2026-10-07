import Foundation
import IOKit
import IOKit.ps

/// Reads the battery straight from the I/O Registry, the same source System Information uses.
nonisolated enum BatteryReader {
    static func read(includeTemperature: Bool) -> BatterySnapshot? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let battery = properties?.takeRetainedValue() as? [String: Any],
              bool(battery["BatteryInstalled"], default: true)
        else { return nil }

        let data = battery["BatteryData"] as? [String: Any] ?? [:]
        let telemetry = battery["PowerTelemetryData"] as? [String: Any] ?? [:]
        let isPluggedIn = bool(battery["ExternalConnected"])
        let systemLoad = int(telemetry["SystemLoad"]).map { Double($0) / 1000 }
        let powerIn = int(telemetry["SystemPowerIn"]).map { Double($0) / 1000 }

        return BatterySnapshot(
            date: int(battery["UpdateTime"]).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .now,
            percent: int(battery["CurrentCapacity"]) ?? 0,
            isPluggedIn: isPluggedIn,
            isCharging: bool(battery["IsCharging"]),
            isFullyCharged: bool(battery["FullyCharged"]),
            remainingCapacity: int(data["RemainingCapacity"]) ?? int(battery["AppleRawCurrentCapacity"]) ?? 0,
            fullChargeCapacity: int(data["FullChargeCapacity"]) ?? int(battery["AppleRawMaxCapacity"]) ?? 0,
            designCapacity: int(data["DesignCapacity"]) ?? int(battery["DesignCapacity"]) ?? 0,
            maximumCapacityPercent: int(battery["MaxCapacity"]) ?? 100,
            cycleCount: int(battery["CycleCount"]) ?? 0,
            designCycleCount: int(battery["DesignCycleCount9C"]),
            voltage: Double(int(battery["Voltage"]) ?? 0) / 1000,
            amperage: Double(int(battery["Amperage"]) ?? 0) / 1000,
            systemPower: systemLoad.flatMap { $0 > 0 ? $0 : nil },
            adapterPower: isPluggedIn ? powerIn.flatMap { $0 > 0 ? $0 : nil } : nil,
            systemTimeToEmpty: minutes(battery["AvgTimeToEmpty"]),
            systemTimeToFull: minutes(battery["AvgTimeToFull"]),
            adapter: isPluggedIn ? readAdapter() : nil,
            temperature: includeTemperature ? readTemperature() : nil,
            serialNumber: battery["Serial"] as? String,
            gaugeName: battery["DeviceName"] as? String,
            manufactureDate: manufactureDate
        )
    }

    /// Read once: it never changes.
    private static let manufactureDate: Date? = {
        var buffer = [CChar](repeating: 0, count: 33)
        guard BSReadSMCText("BMDT", &buffer, Int32(buffer.count)) > 0 else { return nil }
        return parseManufactureDate(String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
    }()

    /// The SMC holds the battery's build date as six digits, such as "340126": the week of the year,
    /// two more digits, then the year. It isn't documented, so anything that doesn't parse cleanly
    /// into a believable past date is ignored rather than shown.
    static func parseManufactureDate(_ text: String) -> Date? {
        let digits = Array(text.prefix(6))
        guard digits.count == 6, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
              let week = Int(String(digits[0...1])), let year = Int(String(digits[4...5])),
              (1...53).contains(week)
        else { return nil }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        guard let date = calendar.date(from: DateComponents(weekday: 2, weekOfYear: week, yearForWeekOfYear: 2000 + year)),
              date <= .now, date > Date.now.addingTimeInterval(-20 * 365 * 24 * 3600)
        else { return nil }
        return date
    }

    private static func readAdapter() -> PowerAdapter? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else { return nil }
        return PowerAdapter(
            watts: int(details["Watts"]),
            name: details["Name"] as? String,
            manufacturer: details["Manufacturer"] as? String
        )
    }

    private static func readTemperature() -> Double? {
        let value = BSReadBatteryTemperature()
        return value.isNaN ? nil : value
    }

    /// Registry numbers are 64-bit; negative values such as a discharging current arrive wrapped.
    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber).map { Int($0.int64Value) }
    }

    private static func bool(_ value: Any?, default fallback: Bool = false) -> Bool {
        (value as? NSNumber)?.boolValue ?? fallback
    }

    /// The battery reports 65535 when it has no estimate.
    private static func minutes(_ value: Any?) -> Int? {
        guard let minutes = int(value), minutes > 0, minutes < 65535 else { return nil }
        return minutes
    }
}
