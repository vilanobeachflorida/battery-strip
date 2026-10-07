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
    var maximumCapacityPercent: Int
    var cycleCount: Int
}

/// A week of charge history plus a daily health log, saved in Application Support.
@Observable
final class HistoryStore {
    private(set) var points: [HistoryPoint] = []
    private(set) var healthLog: [HealthRecord] = []

    @ObservationIgnored private var isDirty = false
    @ObservationIgnored private let fileURL: URL

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
        recordHealth(snapshot)
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
            cycleCount: snapshot.cycleCount
        ))
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
