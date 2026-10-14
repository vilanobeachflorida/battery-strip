import Foundation
import Observation

nonisolated struct HistoryPoint: Codable, Equatable, Identifiable {
    var date: Date
    var percent: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    /// Whole-Mac power use, in watts.
    var watts: Double?

    var id: Date { date }
}

/// One entry per day, so health can be charted over the battery's life.
nonisolated struct HealthRecord: Codable, Equatable {
    var day: Date
    var fullChargeCapacity: Int
    var designCapacity: Int
    /// Before 1.0.2 this was always 100, so the health forecast works from `nominalChargeCapacity` instead.
    var maximumCapacityPercent: Int
    var cycleCount: Int
    /// What the battery could hold when full, in mAh, which health is worked out from. Missing before 1.0.2.
    var nominalChargeCapacity: Int?
    /// How the battery spent the day, for the health forecast. Missing before 1.0.2.
    var usage: DailyUsage?
}

/// How long the battery spent at what charge and temperature over a day, which sets how fast it aged.
nonisolated struct DailyUsage: Codable, Equatable {
    var hours = 0.0
    /// Those hours weighted by how fast the battery ages at its charge and temperature, so an hour of typical
    /// use counts as one (see `HealthModel.agingRate`).
    var agingHours = 0.0
    /// The same, had charging stopped at 80%.
    var agingHoursAt80 = 0.0
    /// Hours spent at 95% or more.
    var hoursNearFull = 0.0
    /// Hours awake with a measured temperature, and their total in °C × hours, for the average.
    var measuredHours = 0.0
    var degreeHours = 0.0

    mutating func add(hours: Double, percent: Int, celsius: Double, isMeasured: Bool) {
        let charge = Double(percent) / 100
        self.hours += hours
        agingHours += hours * HealthModel.agingRate(charge: charge, celsius: celsius)
        agingHoursAt80 += hours * HealthModel.agingRate(charge: min(charge, 0.8), celsius: celsius)
        if percent >= 95 { hoursNearFull += hours }
        if isMeasured {
            measuredHours += hours
            degreeHours += hours * celsius
        }
    }
}

/// A week of charge history plus a daily health log, saved in Application Support.
@Observable
final class HistoryStore {
    private(set) var points: [HistoryPoint] = []
    private(set) var healthLog: [HealthRecord] = []

    @ObservationIgnored private var isDirty = false
    @ObservationIgnored private let fileURL: URL
    /// The reading before this one, for timing how long the battery spent at its charge and temperature.
    @ObservationIgnored private var lastReading: BatterySnapshot?

    private nonisolated struct Archive: Codable {
        var points: [HistoryPoint]
        var healthLog: [HealthRecord]
    }

    init() {
        let folder = URL.applicationSupportDirectory.appending(path: "Battery Strip", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appending(path: "history.json")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let data = try? Data(contentsOf: fileURL), let archive = try? decoder.decode(Archive.self, from: data) {
            points = archive.points
            healthLog = archive.healthLog
        }
    }

    func record(_ snapshot: BatterySnapshot) {
        recordHealth(snapshot)
        trackUsage(snapshot)
        let point = HistoryPoint(
            date: snapshot.date,
            percent: snapshot.percent,
            isCharging: snapshot.isCharging,
            isPluggedIn: snapshot.isPluggedIn,
            watts: snapshot.systemPower
        )
        // Only keep a point when something changed, plus one every few minutes.
        if let last = points.last,
           last.percent == point.percent,
           last.isCharging == point.isCharging,
           last.isPluggedIn == point.isPluggedIn,
           point.date.timeIntervalSince(last.date) < 300 {
            return
        }
        points.append(point)
        let cutoff = snapshot.date.addingTimeInterval(-7 * 24 * 3600)
        if let first = points.first, first.date < cutoff {
            points.removeAll { $0.date < cutoff }
        }
        isDirty = true
    }

    private func recordHealth(_ snapshot: BatterySnapshot) {
        let day = Calendar.current.startOfDay(for: snapshot.date)
        guard healthLog.last?.day != day, snapshot.fullChargeCapacity > 0 else { return }
        healthLog.append(HealthRecord(
            day: day,
            fullChargeCapacity: snapshot.fullChargeCapacity,
            designCapacity: snapshot.designCapacity,
            maximumCapacityPercent: snapshot.maximumCapacityPercent,
            cycleCount: snapshot.cycleCount,
            nominalChargeCapacity: snapshot.nominalChargeCapacity
        ))
        isDirty = true
    }

    /// Adds the time since the last reading to today's usage.
    private func trackUsage(_ snapshot: BatterySnapshot) {
        defer { lastReading = snapshot }
        guard let last = lastReading, let today = healthLog.indices.last,
              healthLog[today].day == Calendar.current.startOfDay(for: snapshot.date)
        else { return }
        let seconds = snapshot.date.timeIntervalSince(last.date)
        guard seconds > 0 else { return }
        var usage = healthLog[today].usage ?? DailyUsage()
        if seconds <= 15 * 60 {
            // Awake: the battery spent the time at the last reading's charge and temperature.
            usage.add(hours: seconds / 3600, percent: last.percent, celsius: last.temperature ?? HealthModel.awakeCelsius,
                      isMeasured: last.temperature != nil)
        } else {
            // A gap: the Mac was asleep, or Battery Strip wasn't running. The battery cooled to room temperature and
            // stayed at about the same charge, or charged early on and held there if it was plugged in throughout.
            let percent = last.isPluggedIn && snapshot.isPluggedIn ? snapshot.percent : (last.percent + snapshot.percent) / 2
            usage.add(hours: min(seconds, 30 * 24 * 3600) / 3600, percent: percent, celsius: HealthModel.restingCelsius,
                      isMeasured: false)
        }
        healthLog[today].usage = usage
        isDirty = true
    }

    func save() {
        guard isDirty else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            try encoder.encode(Archive(points: points, healthLog: healthLog)).write(to: fileURL, options: .atomic)
            isDirty = false
        } catch {
            NSLog("Battery Strip: couldn't save history: \(error)")
        }
    }
}
