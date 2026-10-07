import Foundation

nonisolated enum TimeEstimate: Equatable {
    case calculating
    case untilEmpty(minutes: Int)
    case untilFull(minutes: Int)
    /// Plugged in and full.
    case charged
    /// Plugged in but held below full, by Optimized Battery Charging or a charge limit.
    case notCharging

    var minutes: Int? {
        switch self {
        case .untilEmpty(let minutes), .untilFull(let minutes): minutes
        default: nil
        }
    }
}

/// What the estimator has learned about this Mac, kept across launches.
nonisolated struct LearnedBehavior: Codable {
    /// Long-run average draw on battery, in mA.
    var typicalDrawMA: Double?
    /// Hours of battery use the typical draw is based on.
    var batteryHours = 0.0
    /// How the percentage macOS shows maps onto the battery's real charge.
    var percentFit = LinearFit()
    /// Minutes each percent from 80 to 99 takes to charge. Charging slows as the battery fills.
    var topChargeMinutes: [Double?] = Array(repeating: nil, count: 20)
    /// The session's recent readings when last saved, so a relaunch on battery doesn't start cold.
    var sessionReadings: [Double]?
    var sessionSavedAt: Date?

    init() {}

    // Missing keys decode to their defaults, so adding a field never wipes what's been learned.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        typicalDrawMA = try container.decodeIfPresent(Double.self, forKey: .typicalDrawMA)
        batteryHours = try container.decodeIfPresent(Double.self, forKey: .batteryHours) ?? 0
        percentFit = try container.decodeIfPresent(LinearFit.self, forKey: .percentFit) ?? LinearFit()
        topChargeMinutes = try container.decodeIfPresent([Double?].self, forKey: .topChargeMinutes)
            ?? Array(repeating: nil, count: 20)
        sessionReadings = try container.decodeIfPresent([Double].self, forKey: .sessionReadings)
        sessionSavedAt = try container.decodeIfPresent(Date.self, forKey: .sessionSavedAt)
    }
}

/// A least-squares line that slowly forgets old points, so it follows the battery as it ages.
nonisolated struct LinearFit: Codable {
    private var n = 0.0, sumX = 0.0, sumY = 0.0, sumXX = 0.0, sumXY = 0.0

    mutating func add(x: Double, y: Double) {
        let keep = 0.998
        n = n * keep + 1
        sumX = sumX * keep + x
        sumY = sumY * keep + y
        sumXX = sumXX * keep + x * x
        sumXY = sumXY * keep + x * y
    }

    /// `y = slope * x + intercept`, once the points span enough range to trust.
    var line: (slope: Double, intercept: Double)? {
        guard n >= 20 else { return nil }
        let meanX = sumX / n, meanY = sumY / n
        let varianceX = sumXX / n - meanX * meanX
        guard varianceX > 0.0006 else { return nil }
        let slope = (sumXY / n - meanX * meanY) / varianceX
        guard (80...130).contains(slope) else { return nil }
        return (slope, meanY - slope * meanX)
    }
}

/// Turns once-a-minute battery readings into a steady time estimate.
///
/// macOS's own estimates swing with every spike in usage. This one follows the last ten minutes of
/// usage while ignoring brief spikes and dips, so it only moves when usage really changes. It also
/// learns how the displayed percentage maps onto real charge, and how slowly the last 20% charges.
final class TimeEstimator {
    private(set) var estimate: TimeEstimate = .calculating
    /// This session's recent draw on battery, in mA.
    var sessionDrawMA: Double? { Self.trimmedAverage(session.readings) }
    /// What this Mac usually draws on battery, once there's enough history to say.
    var typicalDrawMA: Double? { learned.batteryHours >= 3 ? learned.typicalDrawMA : nil }

    private var learned: LearnedBehavior
    private var session = Session()
    private var shown: Shown?
    private static let storageKey = "LearnedBehavior"

    private struct Session {
        var isDischarging = false
        /// Draw in mA from the last ten readings, about a minute apart.
        var readings: [Double] = []
        var lastReading: Date?
        var chargeMA: Double?
        var peakChargeMA = 0.0
        var lastPercent: Int?
        var percentReachedAt: Date?
    }

    private struct Shown {
        var isCharging: Bool
        var minutes: Double
        var at: Date
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(LearnedBehavior.self, from: data) {
            learned = saved
        } else {
            learned = LearnedBehavior()
        }
    }

    func save() {
        learned.sessionReadings = session.readings.isEmpty ? nil : session.readings
        learned.sessionSavedAt = session.readings.isEmpty ? nil : .now
        if let data = try? JSONEncoder().encode(learned) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    func ingest(_ snapshot: BatterySnapshot, isNewReading: Bool, now: Date = .now) {
        guard snapshot.fullChargeCapacity > 0 else {
            estimate = .calculating
            return
        }
        let charge = Double(snapshot.remainingCapacity) / Double(snapshot.fullChargeCapacity)
        var elapsed: TimeInterval = 60
        if isNewReading {
            if let last = session.lastReading { elapsed = now.timeIntervalSince(last) }
            session.lastReading = now
            if (3...97).contains(snapshot.percent) {
                learned.percentFit.add(x: charge, y: Double(snapshot.percent))
            }
        }
        // A long gap means the Mac was asleep; don't let one reading carry that much weight.
        let dt = elapsed > 600 ? 60 : max(elapsed, 1)

        if snapshot.isPluggedIn {
            session.isDischarging = false
            session.readings = []
            estimate = chargingEstimate(snapshot, charge: charge, isNewReading: isNewReading, dt: dt, now: now)
        } else {
            session.chargeMA = nil
            session.peakChargeMA = 0
            session.lastPercent = nil
            session.percentReachedAt = nil
            estimate = dischargingEstimate(snapshot, charge: charge, isNewReading: isNewReading, dt: dt, now: now)
        }
    }

    // MARK: - On battery

    private func dischargingEstimate(_ snapshot: BatterySnapshot, charge: Double, isNewReading: Bool, dt: Double, now: Date) -> TimeEstimate {
        if !session.isDischarging {
            session.isDischarging = true
            // Picking up right after a relaunch: carry on from the saved readings rather than starting cold.
            if let saved = learned.sessionReadings, let savedAt = learned.sessionSavedAt, now.timeIntervalSince(savedAt) < 15 * 60 {
                session.readings = saved
            }
        }

        let reading = -snapshot.amperage * 1000
        if isNewReading, reading > 0 {
            session.readings = Array((session.readings + [reading]).suffix(10))
            // A plain running average at first, so a few early minutes can't dominate it,
            // then a slow-moving one that follows how this Mac gets used over time.
            learned.batteryHours += dt / 3600
            let weight = max(dt / (learned.batteryHours * 3600), 1 - exp(-dt / (4 * 3600)))
            learned.typicalDrawMA = learned.typicalDrawMA.map { $0 + weight * (reading - $0) } ?? reading
        }

        // Recent usage drives the estimate. What's typical only fills in before the session's first reading.
        guard let draw = sessionDrawMA ?? typicalDrawMA, draw > 10 else {
            return snapshot.systemTimeToEmpty.map { .untilEmpty(minutes: stabilize($0, isCharging: false, now: now)) } ?? .calculating
        }
        let reserve = min(0.15, chargeFraction(atPercent: 0, snapshot, charge: charge))
        let usable = max(0, charge - reserve) * Double(snapshot.fullChargeCapacity)
        return .untilEmpty(minutes: stabilize(Int((usable / draw * 60).rounded()), isCharging: false, now: now))
    }

    /// The average of the readings without the highest and lowest few, so a brief spike or dip
    /// doesn't move it, while a change that lasts a few minutes does.
    static func trimmedAverage(_ readings: [Double]) -> Double? {
        guard !readings.isEmpty else { return nil }
        let trim = readings.count >= 6 ? 2 : readings.count >= 3 ? 1 : 0
        let kept = readings.sorted().dropFirst(trim).dropLast(trim)
        return kept.reduce(0, +) / Double(kept.count)
    }

    // MARK: - Plugged in

    private func chargingEstimate(_ snapshot: BatterySnapshot, charge: Double, isNewReading: Bool, dt: Double, now: Date) -> TimeEstimate {
        if snapshot.isFullyCharged || snapshot.percent >= 100 {
            shown = nil
            return .charged
        }
        guard snapshot.isCharging else {
            session.lastPercent = nil
            shown = nil
            return .notCharging
        }

        let reading = snapshot.amperage * 1000
        if isNewReading, reading > 0 {
            session.chargeMA = smooth(session.chargeMA, toward: reading, dt: dt, tau: 120)
            session.peakChargeMA = max(session.peakChargeMA, reading)
        }
        learnTopCharge(percent: snapshot.percent, now: now)

        guard let chargeMA = session.chargeMA, chargeMA > 50 else {
            return snapshot.systemTimeToFull.map { .untilFull(minutes: stabilize($0, isCharging: true, now: now)) } ?? .calculating
        }

        let capacity = Double(snapshot.fullChargeCapacity)
        let mAhPerPercent = (chargeFraction(atPercent: 100, snapshot, charge: charge)
            - chargeFraction(atPercent: 0, snapshot, charge: charge)) / 100 * capacity
        let progress = progressThroughCurrentPercent(snapshot, charge: charge)
        var minutes = 0.0
        for percent in snapshot.percent..<100 {
            var stepMinutes: Double
            if percent < 80 {
                stepMinutes = mAhPerPercent / chargeMA * 60
            } else if let learnedMinutes = learned.topChargeMinutes[percent - 80] {
                stepMinutes = learnedMinutes
            } else {
                // No history yet: charging tapers as the battery fills, roughly doubling the time for the last 20%.
                let depth = Double(percent - 79) / 20
                stepMinutes = mAhPerPercent / max(chargeMA, session.peakChargeMA) * 60 * (1 + 4 * depth * depth)
            }
            if percent == snapshot.percent { stepMinutes *= 1 - progress }
            minutes += stepMinutes
        }
        return .untilFull(minutes: stabilize(Int(minutes.rounded()), isCharging: true, now: now))
    }

    /// Times how long each percent from 80 up takes, so later estimates know this battery's slow finish.
    private func learnTopCharge(percent: Int, now: Date) {
        defer { session.lastPercent = percent }
        guard let last = session.lastPercent, percent != last else { return }
        guard percent == last + 1 else {
            session.percentReachedAt = nil
            return
        }
        if let reachedAt = session.percentReachedAt, (80...99).contains(last) {
            let minutes = now.timeIntervalSince(reachedAt) / 60
            if (0.3...30).contains(minutes) {
                let index = last - 80
                learned.topChargeMinutes[index] = learned.topChargeMinutes[index].map { 0.7 * $0 + 0.3 * minutes } ?? minutes
            }
        }
        session.percentReachedAt = now
    }

    // MARK: - Helpers

    /// The real charge fraction at which macOS shows `percent`.
    private func chargeFraction(atPercent percent: Double, _ snapshot: BatterySnapshot, charge: Double) -> Double {
        if let line = learned.percentFit.line {
            return max(0, (percent - line.intercept) / line.slope)
        }
        // Until there's history to learn from, assume the displayed percentage scales from empty.
        return snapshot.percent > 0 ? charge * percent / Double(snapshot.percent) : percent / 100
    }

    /// How far through the current whole percent the battery is, from 0 to 1.
    private func progressThroughCurrentPercent(_ snapshot: BatterySnapshot, charge: Double) -> Double {
        guard let line = learned.percentFit.line else { return 0.5 }
        return min(1, max(0, line.slope * charge + line.intercept - Double(snapshot.percent)))
    }

    /// Keeps the shown number steady. While the estimate stays close, the number counts down a minute
    /// per minute and drifts gently toward the estimate; it only jumps when usage has really changed.
    private func stabilize(_ minutes: Int, isCharging: Bool, now: Date) -> Int {
        let target = Double(minutes)
        if let shown, shown.isCharging == isCharging {
            let elapsed = now.timeIntervalSince(shown.at)
            let expected = shown.minutes - elapsed / 60
            if expected > 0, abs(target - expected) <= max(3, expected * 0.04) {
                // Close about a third of the gap per minute.
                let eased = expected + (target - expected) * 0.3 * min(elapsed / 60, 1)
                self.shown = Shown(isCharging: isCharging, minutes: eased, at: now)
                return Int(eased.rounded())
            }
        }
        shown = Shown(isCharging: isCharging, minutes: target, at: now)
        return minutes
    }

    private func smooth(_ value: Double?, toward sample: Double, dt: Double, tau: Double) -> Double {
        guard let value else { return sample }
        return value + (1 - exp(-dt / tau)) * (sample - value)
    }
}
