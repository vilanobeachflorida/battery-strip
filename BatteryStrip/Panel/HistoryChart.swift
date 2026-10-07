import Charts
import SwiftUI

/// Charge level over the last 24 hours, with charging periods shaded. Until there's a day of history,
/// it shows just the hours it has, so it's useful from the first few minutes.
struct HistoryChart: View {
    let points: [HistoryPoint]
    @State private var hovered: ChartPoint?

    /// Readings averaged into short buckets, so whole-percent steps don't make the line jagged.
    private struct ChartPoint: Identifiable {
        let date: Date
        let percent: Double
        var id: Date { date }
    }

    private struct Span: Identifiable {
        let start: Date
        let end: Date
        var id: Date { start }
    }

    var body: some View {
        let now = Date.now
        let recent = points.filter { $0.date >= now.addingTimeInterval(-24 * 3600) }
        let hours = visibleHours(of: recent, now: now)
        let start = now.addingTimeInterval(-Double(hours) * 3600)
        let spans = chargingSpans(in: recent, until: now)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(hours == 24 ? "Last 24 hours" : hours == 1 ? "Last hour" : "Last \(hours) hours")
                    .font(.caption.weight(.semibold))
                Spacer()
                if let hovered {
                    Text("\(Int(hovered.percent.rounded()))% at \(hovered.date.formatted(date: .omitted, time: .shortened))")
                        .monospacedDigit()
                } else if !spans.isEmpty {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green.opacity(0.3))
                        .frame(width: 10, height: 10)
                    Text("Charging")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if recent.count < 2 {
                Text("History starts now and fills in as you use your Mac.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                chart(smoothed(recent, bucket: max(60, Double(hours) * 25)), spans: spans, domain: start...now, hours: hours)
            }
        }
    }

    private func chart(_ line: [ChartPoint], spans: [Span], domain: ClosedRange<Date>, hours: Int) -> some View {
        Chart {
            ForEach(spans) { span in
                RectangleMark(xStart: .value("Start", max(span.start, domain.lowerBound)), xEnd: .value("End", span.end))
                    .foregroundStyle(Color.green.opacity(0.14))
            }
            ForEach(line) { point in
                AreaMark(x: .value("Time", point.date), y: .value("Charge", point.percent))
                    .foregroundStyle(Color.primary.opacity(0.08))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", point.date), y: .value("Charge", point.percent))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let hovered {
                RuleMark(x: .value("Time", hovered.date))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Time", hovered.date), y: .value("Charge", hovered.percent))
                    .symbolSize(64)
                    .foregroundStyle(Color.primary)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel {
                    if let percent = value.as(Int.self) { Text("\(percent)%") }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: hours <= 3 ? .dateTime.hour().minute() : .dateTime.hour())
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
                            hovered = line.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .frame(height: 72)
        .accessibilityLabel("Charge over the last \(hours == 1 ? "hour" : "\(hours) hours")")
    }

    /// Whole hours covered by the history so far, from 1 to 24.
    private func visibleHours(of points: [HistoryPoint], now: Date) -> Int {
        guard let first = points.first?.date else { return 1 }
        return min(24, max(1, Int((now.timeIntervalSince(first) / 3600).rounded(.up))))
    }

    private func smoothed(_ points: [HistoryPoint], bucket: TimeInterval) -> [ChartPoint] {
        let buckets = Dictionary(grouping: points) { Int($0.date.timeIntervalSince1970 / bucket) }
        return buckets.keys.sorted().compactMap { key in
            guard let bucket = buckets[key], !bucket.isEmpty else { return nil }
            let count = Double(bucket.count)
            let seconds = bucket.reduce(0) { $0 + $1.date.timeIntervalSince1970 } / count
            let percent = bucket.reduce(0) { $0 + Double($1.percent) } / count
            return ChartPoint(date: Date(timeIntervalSince1970: seconds), percent: percent)
        }
    }

    private func chargingSpans(in points: [HistoryPoint], until now: Date) -> [Span] {
        var spans: [Span] = []
        var spanStart: Date?
        for point in points {
            if point.isCharging, spanStart == nil {
                spanStart = point.date
            } else if !point.isCharging, let start = spanStart {
                spans.append(Span(start: start, end: point.date))
                spanStart = nil
            }
        }
        if let spanStart { spans.append(Span(start: spanStart, end: now)) }
        return spans
    }
}
