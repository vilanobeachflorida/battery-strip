import Foundation

/// How fast a battery ages at a given charge and temperature.
nonisolated enum HealthModel {
    /// A sleeping Mac's battery cools to about room temperature.
    static let restingCelsius = 25.0
    /// Assumed for a Mac in use until its battery temperature has been read.
    static let awakeCelsius = 30.0
    /// `fullness × heat` for typical laptop use: plugged in near full for a good part of the day, at about 30°C in use.
    private static let typicalRate = 1.5

    /// How fast the battery ages with time alone, at this charge (0 to 1) and temperature, where typical laptop
    /// use is 1.
    ///
    /// A fuller battery sits at a higher voltage, which wears it faster, most of all near full. Heat speeds up
    /// the same chemistry, following the Arrhenius law: at 35°C a battery ages about 1.5 times as fast as at 25°C.
    static func agingRate(charge: Double, celsius: Double) -> Double {
        let charge = min(max(charge, 0), 1)
        let fullness = 0.6 + 0.8 * charge + 1.6 * pow(max(0, charge - 0.5), 2)
        let kelvin = min(max(celsius, 0), 60) + 273.15
        let heat = exp(4000 * (1 / 298.15 - 1 / kelvin))
        return fullness * heat / typicalRate
    }
}

/// Where the battery's health is heading, worked out from how batteries wear and from this battery's own readings.
///
/// A lithium-ion battery wears out in two ways. Age wears it, faster when it's warm or sitting near full, and
/// that wear slows as the battery gets older: it grows with the square root of time. And each charge cycle
/// wears it a little more. So health is modeled as
///
///     health = starting capacity − a × √(effective age) − b × cycles
///
/// where the effective age counts each hour by how hard heat and charge level pushed the battery during it
/// (`DailyUsage`). The starting capacity and the two rates begin at typical values for a Mac battery and are
/// fitted to this battery's readings by Bayesian regression, so the more history there is, the more the forecast
/// is this battery's own, and the narrower its likely range. Going forward, it follows this Mac's own recent
/// pace of cycles, heat and charge.
nonisolated struct HealthForecast {
    struct Point: Identifiable {
        let date: Date
        /// Health as a fraction of the design capacity, which can start a little above 1 when new.
        let health: Double
        /// The likely range: 80% of outcomes fall inside it. The same as `health` up to today.
        let low: Double
        let high: Double
        var isForecast: Bool
        var id: Date { date }
    }

    /// Health as measured, one point a week.
    struct Reading: Identifiable {
        let date: Date
        let health: Double
        var id: Date { date }
    }

    struct Crossing: Equatable {
        let date: Date
        let earliest: Date
        /// Nil when the likely range runs past the end of the forecast.
        let latest: Date?
    }

    struct FullCharge: Equatable {
        /// Minutes a full charge lasts at this Mac's typical use.
        let new: Int
        let now: Int
        let inTwoYears: Int
    }

    /// When the battery was made, or a guess from its cycle count if the Mac doesn't say.
    let birth: Date
    let isBirthKnown: Bool
    let now: Date
    /// Health from when the battery was made to the end of the forecast, monthly.
    let curve: [Point]
    let readings: [Reading]
    /// Health as measured now.
    let health: Double
    /// Health now, as fitted: what the forecast continues from.
    let fittedHealth: Double
    let healthInAYear: Double
    /// When health falls to 80%, or fell. Nil when that's beyond the forecast, 15 years out.
    let crossing80: Crossing?
    let isBelow80: Bool
    /// How many months later it would reach 80% if charging stopped at 80%, when that's worth mentioning.
    let chargeLimitMonths: Int?
    let fullCharge: FullCharge?
    let cycleCount: Int
    let designCycleCount: Int?
    let cyclesPerWeek: Double
    /// The share of the coming year's wear that comes from charge cycles, rather than age.
    let cycleShare: Double
    /// Lately, the share of time spent at 95% or more, once there's a day to go on.
    let nearFullShare: Double?
    /// Lately, the average battery temperature while the Mac was in use, in °C.
    let averageCelsius: Double?
    /// Under three months of readings, so the forecast still leans on typical values.
    let isEarly: Bool

    /// The end of the chart.
    var end: Date { curve.last?.date ?? now }

    /// `minutesPerMAh` is how long each mAh of a full charge lasts at this Mac's typical use, once that's known.
    /// `chargeLimit` is macOS's Charge Limit (100 for none).
    static func make(records: [HealthRecord], snapshot: BatterySnapshot, minutesPerMAh: Double?, chargeLimit: Int?,
                     now: Date = .now) -> HealthForecast? {
        let design = Double(snapshot.designCapacity)
        guard design > 0, snapshot.nominalChargeCapacity > 0 else { return nil }
        let day = 86400.0, year = 365.25 * 86400
        let today = Calendar.current.startOfDay(for: now)

        // This battery's records only. A replaced battery starts its cycle count over.
        var battery: [HealthRecord] = []
        var laterCycles = snapshot.cycleCount
        for record in records.reversed() where record.day < now {
            guard record.designCapacity == snapshot.designCapacity, record.cycleCount <= laterCycles else { break }
            battery.append(record)
            laterCycles = record.cycleCount
        }
        battery.reverse()

        let guessedAge = max(30, Double(snapshot.cycleCount) / typicalCyclesPerDay) * day
        let birth = min(snapshot.manufactureDate ?? min(battery.first?.day ?? now, now - guessedAge), now - day)
        battery.removeAll { $0.day < birth - 7 * day }

        // Weekly medians of the daily readings, with today's from the live reading.
        var daily = battery.compactMap { record -> Observation? in
            guard let nominal = record.nominalChargeCapacity, nominal > 0, record.day < today else { return nil }
            return Observation(date: record.day + day / 2, health: Double(nominal) / design, cycles: Double(record.cycleCount))
        }
        let health = Double(snapshot.nominalChargeCapacity) / design
        daily.append(Observation(date: now, health: health, cycles: Double(snapshot.cycleCount)))
        let weeks = Dictionary(grouping: daily) { Int(floor($0.date.timeIntervalSince(birth) / (7 * day))) }
        let observations = weeks.keys.sorted().map { key -> Observation in
            let week = weeks[key]!
            let dates = week.map(\.date.timeIntervalSinceReferenceDate)
            return Observation(date: Date(timeIntervalSinceReferenceDate: dates.reduce(0, +) / Double(dates.count)),
                               health: median(week.map(\.health)), cycles: week.map(\.cycles).max()!)
        }

        // Pace of cycles: the last three months, starting from two weeks at the lifetime pace so a short span can't
        // swing it, or at a typical pace for a battery under six months old, which may have sat in a warehouse.
        let ageInDays = now.timeIntervalSince(birth) / day
        let longRunPace = ageInDays >= 180 ? Double(snapshot.cycleCount) / ageInDays : typicalCyclesPerDay
        let window = battery.first { $0.day >= today - 90 * day }
        let span = window.map { now.timeIntervalSince($0.day) / day } ?? 0
        let added = window.map { Double(max(0, snapshot.cycleCount - $0.cycleCount)) } ?? 0
        let cyclesPerDay = (added + longRunPace * 14) / (span + 14)

        // How hard heat and charge level push this battery: over its tracked life for the past, the last month going forward.
        let recent = battery.filter { $0.day >= today - 30 * day }
        let recentUsage = recent.compactMap(\.usage)
        let recentHours = recentUsage.reduce(0) { $0 + $1.hours }
        let pastRate = agingRate(battery.compactMap(\.usage))
        let futureRate = agingRate(recentUsage)

        var cycleHistory = [(date: birth, cycles: 0.0)]
        for record in battery where record.day > birth {
            cycleHistory.append((record.day + day / 2, max(cycleHistory.last!.cycles, Double(record.cycleCount))))
        }
        cycleHistory.removeAll { $0.date >= now }
        cycleHistory.append((now, Double(snapshot.cycleCount)))

        var model = Model(birth: birth, now: now, pastRate: pastRate, futureRate: futureRate,
                          cycles: Double(snapshot.cycleCount), cyclesPerDay: cyclesPerDay, cycleHistory: cycleHistory)
        let ratedCycles = Double(snapshot.designCycleCount ?? 1000)
        model.fit(observations, prior: Prior(
            // New batteries usually hold a little more than their design capacity. Age takes about 3.5% in the first
            // year of typical use, and cycling the rest of Apple's rating: 80% after 1,000 cycles.
            mean: SIMD3(1.015, 0.035, 0.14 * 1000 / ratedCycles),
            sd: SIMD3(0.015, 0.0175, 0.07 * 1000 / ratedCycles)
        ))

        let horizon = now + 15 * year
        let fittedHealth = model.predict(at: now).health
        let isBelow80 = health < 0.8
        var crossing80: Crossing?
        if isBelow80 {
            let date = firstDate(from: birth, until: now) { model.predict(at: $0).health <= 0.8 } ?? now
            crossing80 = Crossing(date: date, earliest: date, latest: date)
        } else if let date = firstDate(from: now, until: horizon, where: { model.predict(at: $0).health <= 0.8 }) {
            let earliest = firstDate(from: now, until: date) { model.predict(at: $0).bounds.low <= 0.8 } ?? date
            let latest = firstDate(from: date, until: horizon) { model.predict(at: $0).bounds.high <= 0.8 }
            crossing80 = Crossing(date: date, earliest: earliest, latest: latest)
        }

        // What an 80% Charge Limit would change: the same days, with the battery held at 80% instead of above it.
        var chargeLimitMonths: Int?
        if (chargeLimit ?? 100) > 80, recentHours >= 72, !isBelow80, let date = crossing80?.date {
            var limited = model
            limited.futureRate = agingRate(recentUsage, at80: true)
            let later = firstDate(from: now, until: horizon + 5 * year) { limited.predict(at: $0).health <= 0.8 } ?? horizon + 5 * year
            let months = Int((later.timeIntervalSince(date) / (year / 12)).rounded())
            // Only when it's a real difference: at least two months, and a twentieth of the time left.
            if months >= max(2, Int(date.timeIntervalSince(now) / (year / 12) / 20)) { chargeLimitMonths = months }
        }

        // The next year's wear, by cause.
        let fromAge = model.mean.y * (model.effectiveAge(at: now + year).squareRoot() - model.effectiveAge(at: now).squareRoot())
        let fromCycles = model.mean.z * cyclesPerDay * 365.25 / 1000
        let cycleShare = fromAge + fromCycles > 0 ? fromCycles / (fromAge + fromCycles) : 0.5

        let fullCharge = minutesPerMAh.map { perMAh -> FullCharge in
            let minutesNow = Double(snapshot.fullChargeCapacity) * perMAh
            func minutes(_ health: Double) -> Int { Int((minutesNow * health / fittedHealth).rounded()) }
            return FullCharge(new: minutes(model.mean.x), now: Int(minutesNow.rounded()),
                              inTwoYears: minutes(model.predict(at: now + 2 * year).health))
        }

        // Monthly from new, through today, to a year past reaching 80%: at least three years ahead, at most twelve.
        let end = min(max((crossing80.map { max($0.date, now) } ?? now + 10 * year) + year, now + 3 * year), now + 12 * year)
        var dates = Array(stride(from: birth, to: end, by: year / 12))
        dates.removeAll { abs($0.timeIntervalSince(now)) < 5 * day }
        dates.append(contentsOf: [now, end])
        dates.sort()
        let curve = dates.map { date in
            let prediction = model.predict(at: date)
            let isForecast = date > now
            return Point(date: date, health: prediction.health,
                         low: isForecast ? prediction.bounds.low : prediction.health,
                         high: isForecast ? prediction.bounds.high : prediction.health,
                         isForecast: isForecast)
        }

        let measured = recentUsage.reduce(0) { $0 + $1.measuredHours }
        return HealthForecast(
            birth: birth,
            isBirthKnown: snapshot.manufactureDate != nil,
            now: now,
            curve: curve,
            readings: observations.map { Reading(date: $0.date, health: $0.health) },
            health: health,
            fittedHealth: fittedHealth,
            healthInAYear: model.predict(at: now + year).health,
            crossing80: crossing80,
            isBelow80: isBelow80,
            chargeLimitMonths: chargeLimitMonths,
            fullCharge: fullCharge,
            cycleCount: snapshot.cycleCount,
            designCycleCount: snapshot.designCycleCount,
            cyclesPerWeek: cyclesPerDay * 7,
            cycleShare: cycleShare,
            nearFullShare: recentHours >= 24 ? recentUsage.reduce(0) { $0 + $1.hoursNearFull } / recentHours : nil,
            averageCelsius: measured >= 2 ? recentUsage.reduce(0) { $0 + $1.degreeHours } / measured : nil,
            isEarly: now.timeIntervalSince(observations.first?.date ?? now) < 90 * day
        )
    }

    /// How long a full charge lasts at this Mac's typical use, for a battery at `health`.
    func fullChargeMinutes(atHealth health: Double) -> Int? {
        fullCharge.map { Int((Double($0.now) * health / fittedHealth).rounded()) }
    }

    /// Health as the panel shows it: a whole percentage, at most 100.
    static func percent(_ health: Double) -> Int {
        min(100, Int((health * 100).rounded()))
    }

    // MARK: - Model

    private static let typicalCyclesPerDay = 0.4

    private struct Observation {
        var date: Date
        var health: Double
        var cycles: Double
    }

    private struct Prior {
        var mean: SIMD3<Double>
        var sd: SIMD3<Double>
    }

    /// `health = start − a × √(effective age in years) − b × cycles / 1000`, with `mean` holding (start, a, b).
    private struct Model {
        let birth: Date
        let now: Date
        /// Aging speed against typical use, before and after today.
        let pastRate: Double
        var futureRate: Double
        let cycles: Double
        let cyclesPerDay: Double
        let cycleHistory: [(date: Date, cycles: Double)]
        var mean = SIMD3<Double>(1, 0, 0)
        var covariance = Matrix3()

        private static let year = 365.25 * 86400.0
        /// A reading's error, after the weekly median.
        private static let noise = 0.007

        func effectiveAge(at date: Date) -> Double {
            if date <= now { return pastRate * max(0, date.timeIntervalSince(birth)) / Self.year }
            return (pastRate * now.timeIntervalSince(birth) + futureRate * date.timeIntervalSince(now)) / Self.year
        }

        /// Ahead, at the current pace. Before today, between the counts on record.
        func cycleCount(at date: Date) -> Double {
            if date >= now { return cycles + cyclesPerDay * date.timeIntervalSince(now) / 86400 }
            guard let index = cycleHistory.firstIndex(where: { $0.date >= date }) else { return cycles }
            guard index > 0 else { return cycleHistory[0].cycles }
            let before = cycleHistory[index - 1], after = cycleHistory[index]
            let span = after.date.timeIntervalSince(before.date)
            let progress = span > 0 ? date.timeIntervalSince(before.date) / span : 1
            return before.cycles + (after.cycles - before.cycles) * progress
        }

        func features(at date: Date, cycles: Double? = nil) -> SIMD3<Double> {
            SIMD3(1, -effectiveAge(at: date).squareRoot(), -(cycles ?? cycleCount(at: date)) / 1000)
        }

        /// The expected health and its likely range. Ahead of today the range also allows for the model itself
        /// being off, more so the further out it looks.
        func predict(at date: Date) -> (health: Double, bounds: (low: Double, high: Double)) {
            let x = features(at: date)
            let health = (mean * x).sum()
            let yearsAhead = max(0, date.timeIntervalSince(now)) / Self.year
            let modelError = date > now ? 0.004 + 0.008 * yearsAhead : 0
            let spread = 1.28 * (max(0, covariance.quadratic(x)) + modelError * modelError).squareRoot()
            return (health, (health - spread, health + spread))
        }

        /// Bayesian linear regression from the prior, reweighted so readings far off the line count for less
        /// (a Huber loss), such as one taken just as the battery recalibrated.
        ///
        /// The battery's gauge errs in runs: after it recalibrates, its readings can sit a percent high or low for
        /// weeks. So the weeks count as one independent reading per eight weeks of history, rather than one each,
        /// which keeps the fit from being surer of itself than the readings allow.
        mutating func fit(_ observations: [Observation], prior: Prior) {
            let priorPrecision = 1 / (prior.sd * prior.sd)
            var weights = [Double](repeating: 1, count: observations.count)
            let weeks = (observations.last?.date.timeIntervalSince(observations.first?.date ?? now) ?? 0) / (7 * 86400)
            let independent = min(Double(observations.count), 1 + weeks / 8)
            let share = observations.isEmpty ? 1 : independent / Double(observations.count)
            for _ in 0..<6 {
                var precision = Matrix3(diagonal: priorPrecision)
                var information = priorPrecision * prior.mean
                for (observation, weight) in zip(observations, weights) {
                    let x = features(at: observation.date, cycles: observation.cycles)
                    let w = share * weight / (Self.noise * Self.noise)
                    precision.add(x, weight: w)
                    information += w * observation.health * x
                }
                guard let inverse = precision.inverse else { return }
                covariance = inverse
                mean = inverse * information
                weights = observations.map { observation in
                    let x = features(at: observation.date, cycles: observation.cycles)
                    let residual = abs(observation.health - (mean * x).sum())
                    return residual <= 2 * Self.noise ? 1 : 2 * Self.noise / residual
                }
            }
            // Batteries don't heal: neither kind of wear can run backward.
            mean.y = max(mean.y, prior.mean.y * 0.1)
            mean.z = max(mean.z, prior.mean.z * 0.1)
        }
    }

    /// Aging speed against typical use, starting from two days of typical use so a few hours can't swing it.
    private static func agingRate(_ usage: [DailyUsage], at80: Bool = false) -> Double {
        let hours = usage.reduce(0) { $0 + $1.hours }
        let aging = usage.reduce(0) { $0 + (at80 ? $1.agingHoursAt80 : $1.agingHours) }
        return (aging + 48) / (hours + 48)
    }

    /// The first date from `start` to `end` when `reached` is true: month by month, then to the day.
    private static func firstDate(from start: Date, until end: Date, where reached: (Date) -> Bool) -> Date? {
        if reached(start) { return start }
        var before = start
        while before < end {
            let after = min(end, before + 30.44 * 86400)
            if reached(after) {
                var low = before, high = after
                while high.timeIntervalSince(low) > 86400 {
                    let middle = low + high.timeIntervalSince(low) / 2
                    if reached(middle) { high = middle } else { low = middle }
                }
                return high
            }
            before = after
        }
        return nil
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}

/// A 3×3 matrix, enough for the model's three parameters.
nonisolated private struct Matrix3 {
    private var rows = [SIMD3<Double>](repeating: .zero, count: 3)

    init() {}

    init(diagonal: SIMD3<Double>) {
        for i in 0..<3 { rows[i][i] = diagonal[i] }
    }

    /// Adds `weight × x xᵀ`.
    mutating func add(_ x: SIMD3<Double>, weight: Double) {
        for i in 0..<3 { rows[i] += weight * x[i] * x }
    }

    /// `xᵀ M x`.
    func quadratic(_ x: SIMD3<Double>) -> Double {
        (x * (self * x)).sum()
    }

    static func * (matrix: Matrix3, x: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3((matrix.rows[0] * x).sum(), (matrix.rows[1] * x).sum(), (matrix.rows[2] * x).sum())
    }

    var inverse: Matrix3? {
        let a = rows[0], b = rows[1], c = rows[2]
        // The inverse's columns are the cross products of pairs of rows, over the determinant.
        let ab = cross(a, b), bc = cross(b, c), ca = cross(c, a)
        let determinant = (a * bc).sum()
        guard abs(determinant) > 1e-300, determinant.isFinite else { return nil }
        var inverse = Matrix3()
        for i in 0..<3 {
            inverse.rows[i] = SIMD3(bc[i], ca[i], ab[i]) / determinant
        }
        return inverse
    }

    private func cross(_ u: SIMD3<Double>, _ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
    }
}
