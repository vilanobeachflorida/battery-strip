import Foundation

nonisolated enum Format {
    /// "4:05", for the menu bar.
    static func clock(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// "4h 5m", "45m".
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    /// "4 hours, 5 minutes", for VoiceOver.
    static func spokenDuration(_ minutes: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute]
        return formatter.string(from: TimeInterval(minutes * 60)) ?? duration(minutes)
    }

    static func watts(_ watts: Double) -> String {
        let value = abs(watts)
        return value < 10 ? String(format: "%.1f W", value) : String(format: "%.0f W", value)
    }

    static func milliampHours(_ value: Int) -> String {
        "\(value.formatted()) mAh"
    }

    /// "7 weeks", "5 months", "2 years, 3 months".
    static func age(since date: Date, now: Date = .now) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date, to: now)
        let years = parts.year ?? 0, months = parts.month ?? 0
        func plural(_ count: Int, _ unit: String) -> String { "\(count) \(unit)\(count == 1 ? "" : "s")" }
        if years > 0 {
            return months > 0 ? "\(plural(years, "year")), \(plural(months, "month"))" : plural(years, "year")
        }
        if months >= 2 { return plural(months, "month") }
        let weeks = max(1, Int(now.timeIntervalSince(date) / (7 * 24 * 3600)))
        return plural(weeks, "week")
    }

    static func temperature(_ celsius: Double, unit: TemperatureUnit) -> String {
        switch unit {
        case .celsius: String(format: "%.0f°C", celsius)
        case .fahrenheit: String(format: "%.0f°F", celsius * 9 / 5 + 32)
        }
    }
}
