import Charts
import SwiftUI

/// Opened from the Health tile: the battery's health since it was made, where it's heading at this Mac's pace,
/// and how long a full charge lasts, then and now.
struct HealthSection: View {
    let forecast: HealthForecast

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "heart.text.square")
                    .foregroundStyle(.pink)
                Text(Self.summary(for: forecast))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(.callout)

            HealthChart(forecast: forecast)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row("In a year", "about \(HealthForecast.percent(forecast.healthInAYear))%")
                crossingRow
                if let months = forecast.chargeLimitMonths {
                    row("80% Charge Limit", "adds about \(Self.span(months: months))",
                        help: "Set a Charge Limit in System Settings › Battery: click ⓘ next to Charging.")
                }
            }
            .font(.callout)

            fullCharge

            if forecast.isEarly {
                Text("An early estimate, from typical batteries and your use so far. It sharpens as readings build up.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12))
    }

    /// The forecast in two sentences: when the battery should reach 80%, then what's wearing it or would help.
    ///
    /// Written by rules rather than Apple Intelligence: in testing, the on-device model put real numbers in the
    /// wrong places, such as two years' time as now, and called a battery at 100% "at 80%".
    static func summary(for forecast: HealthForecast) -> String {
        let driver = driver(forecast)
        if forecast.isBelow80 {
            return "Your battery holds less than 80% of what it did when new, the level where Apple recommends a battery service. "
                + (forecast.fullCharge.map { "A full charge lasts about \(Format.duration($0.now)) at your typical use." } ?? driver)
        }
        let pace = forecast.isEarly ? "It's early, but at your pace" : "At your pace,"
        let headline = forecast.crossing80.map { "\(pace) your battery should reach 80% around \(describe($0).when)." }
            ?? "\(pace) your battery should stay above 80% for well over a decade."
        if let months = forecast.chargeLimitMonths {
            return headline + " An 80% Charge Limit would push that back by about \(span(months: months))."
        }
        if (forecast.averageCelsius ?? 0) >= 35 {
            return headline + " It runs warm, which speeds up its aging."
        }
        return headline + " " + driver
    }

    /// What most of the coming year's wear comes from.
    private static func driver(_ forecast: HealthForecast) -> String {
        if forecast.cycleShare >= 0.6 { return "Most of its wear now comes from charge cycles." }
        if forecast.cycleShare > 0.4 { return "Its wear now comes from age and charge cycles about equally." }
        if (forecast.nearFullShare ?? 0) >= 0.5 { return "Most of its wear now comes from age, sped up by long stretches at full charge." }
        return "Most of its wear now comes from age rather than use."
    }

    /// "Dec 2027" when the likely range is narrow, otherwise just the year, with the range in words.
    static func describe(_ crossing: HealthForecast.Crossing) -> (when: String, range: String) {
        let isNarrow = crossing.latest.map { $0.timeIntervalSince(crossing.earliest) < 18 * 30.44 * 86400 } ?? false
        let style = isNarrow ? Date.FormatStyle.dateTime.month(.abbreviated).year() : .dateTime.year()
        let when = crossing.date.formatted(style)
        guard let latest = crossing.latest else {
            return (when, "Likely \(crossing.earliest.formatted(style)) or later")
        }
        let earliest = crossing.earliest.formatted(style), last = latest.formatted(style)
        return (when, earliest == last ? "Likely \(earliest)" : "Likely between \(earliest) and \(last)")
    }

    /// "9 months", "2 years".
    static func span(months: Int) -> String {
        months < 24 ? "\(months) months" : "\(Int((Double(months) / 12).rounded())) years"
    }

    @ViewBuilder private var crossingRow: some View {
        if let crossing = forecast.crossing80 {
            let described = Self.describe(crossing)
            if forecast.isBelow80 {
                row("Reached 80%", "around \(described.when)", help: "Apple recommends a battery service below 80%.")
            } else {
                row("Reaches 80%", "around \(described.when)",
                    help: "\(described.range). "
                        + "Apple designs Mac batteries to keep up to 80% of their original capacity at "
                        + "\((forecast.designCycleCount ?? 1000).formatted()) charge cycles.")
            }
        } else {
            row("Reaches 80%", "after \((forecast.now + 15 * 365.25 * 86400).formatted(.dateTime.year()))")
        }
    }

    private func row(_ label: String, _ value: String, help: String = "") -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .help(help)
            Text(value)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .help(help)
        }
    }

    @ViewBuilder private var fullCharge: some View {
        if let full = forecast.fullCharge {
            VStack(alignment: .leading, spacing: 4) {
                Text("On a full charge, at your typical use")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    stat("When new", full.new)
                    stat("Now", full.now)
                    stat("In 2 years", full.inTwoYears)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("How long a full charge lasts shows here after a few hours on battery.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stat(_ label: String, _ minutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Format.duration(minutes))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Health from when the battery was made to the end of the forecast: fitted to the readings up to today, then
/// forecast at this Mac's pace with its likely range shaded. Hovering shows the health and full-charge time.
private struct HealthChart: View {
    let forecast: HealthForecast
    @State private var hovered: HealthForecast.Point?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hovered.map(readout) ?? "Health from new, and where it's heading")
                .font(.caption.weight(hovered == nil ? .semibold : .regular))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .help("The solid line is fitted to your battery's readings. The dashed line is the forecast at your pace, with its likely range shaded.")
            chart
        }
    }

    private var chart: some View {
        let past = forecast.curve.filter { !$0.isForecast }
        let future = forecast.curve.filter { $0.isForecast || $0.date == forecast.now }
        let years = forecast.end.timeIntervalSince(forecast.birth) / (365.25 * 86400)
        // From a little below the lowest point, in fives, down to 50% at most.
        let lowest = min(forecast.curve.map(\.low).min() ?? 0.8, forecast.readings.map(\.health).min() ?? 0.8)
        let bottom = max(50, min(75, ((lowest * 100 - 3) / 5).rounded(.down) * 5))
        // Health as the tile shows it, which tops out at 100%, kept inside the chart.
        func shown(_ health: Double) -> Double { min(100, max(bottom, health * 100)) }
        return Chart {
            ForEach(forecast.readings) { reading in
                PointMark(x: .value("Date", reading.date), y: .value("Health", shown(reading.health)))
                    .symbolSize(10)
                    .foregroundStyle(Color.primary.opacity(0.2))
            }
            ForEach(future) { point in
                AreaMark(x: .value("Date", point.date), yStart: .value("Low", shown(point.low)), yEnd: .value("High", shown(point.high)))
                    .foregroundStyle(Color.pink.opacity(0.14))
                    .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("80%", 80))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ForEach(past) { point in
                LineMark(x: .value("Date", point.date), y: .value("Health", shown(point.health)), series: .value("Part", "Past"))
                    .foregroundStyle(Color.pink)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            ForEach(future) { point in
                LineMark(x: .value("Date", point.date), y: .value("Health", shown(point.health)), series: .value("Part", "Forecast"))
                    .foregroundStyle(Color.pink.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 4]))
                    .interpolationMethod(.monotone)
            }
            PointMark(x: .value("Date", forecast.now), y: .value("Health", shown(forecast.health)))
                .symbolSize(40)
                .foregroundStyle(Color.pink)
            if let hovered {
                RuleMark(x: .value("Date", hovered.date))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Date", hovered.date), y: .value("Health", shown(hovered.health)))
                    .symbolSize(48)
                    .foregroundStyle(Color.primary)
            }
        }
        .chartXScale(domain: forecast.birth...forecast.end)
        .chartYScale(domain: bottom...102)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [80, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel {
                    if let percent = value.as(Int.self) { Text("\(percent)%") }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .year, count: max(1, Int((years / 4).rounded(.up))))) { _ in
                AxisValueLabel(format: .dateTime.year())
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame,
                                  let date: Date = proxy.value(atX: location.x - geometry[plotFrame].origin.x)
                            else { return }
                            hovered = forecast.curve.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .frame(height: 84)
        .accessibilityLabel(accessibilityText)
    }

    private func readout(_ point: HealthForecast.Point) -> String {
        var text = point.date.formatted(.dateTime.month(.abbreviated).year())
            + " · \(point.isForecast ? "about " : "")\(HealthForecast.percent(point.health))%"
        if let minutes = forecast.fullChargeMinutes(atHealth: point.health) {
            text += " · \(Format.duration(minutes)) a charge"
        }
        return text
    }

    private var accessibilityText: String {
        var text = "Battery health, \(HealthForecast.percent(forecast.health))% now"
        text += ", about \(HealthForecast.percent(forecast.healthInAYear))% in a year"
        if !forecast.isBelow80, let crossing = forecast.crossing80 {
            text += ", reaching 80% around \(HealthSection.describe(crossing).when)"
        }
        return text
    }
}
