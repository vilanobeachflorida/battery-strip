import Foundation

/// One reading of the battery. The battery itself refreshes these numbers about once a minute.
nonisolated struct BatterySnapshot: Equatable {
    /// When the battery took this reading.
    var date: Date
    /// The percentage macOS shows.
    var percent: Int
    var isPluggedIn: Bool
    var isCharging: Bool
    var isFullyCharged: Bool
    /// Charge left right now, in mAh.
    var remainingCapacity: Int
    /// What the battery holds when full today, in mAh.
    var fullChargeCapacity: Int
    /// What the battery held when new, in mAh.
    var designCapacity: Int
    /// Apple's "Maximum Capacity", the health figure System Settings shows.
    var maximumCapacityPercent: Int
    var cycleCount: Int
    var designCycleCount: Int?
    /// Volts.
    var voltage: Double
    /// Amps; negative while discharging.
    var amperage: Double
    /// Watts the whole Mac is using, whether it's on battery or the adapter.
    var systemPower: Double?
    /// Watts coming in from the adapter.
    var adapterPower: Double?
    /// macOS's own estimates, in minutes.
    var systemTimeToEmpty: Int?
    var systemTimeToFull: Int?
    var adapter: PowerAdapter?
    /// °C. Only read while the panel is open.
    var temperature: Double?
    var serialNumber: String?
    var gaugeName: String?
    /// When the battery was built, to the week.
    var manufactureDate: Date?

    /// Watts flowing into (positive) or out of (negative) the battery.
    var batteryPower: Double { voltage * amperage }
}

nonisolated struct PowerAdapter: Equatable {
    var watts: Int?
    var name: String?
    var manufacturer: String?
}
