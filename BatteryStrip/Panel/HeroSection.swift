import SwiftUI

/// The top of the panel: time remaining, percentage, the charge strip and current power.
struct HeroSection: View {
    let snapshot: BatterySnapshot
    let estimate: TimeEstimate
    let isLowPowerMode: Bool
    let sessionWatts: Double?
    let typicalWatts: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    headline
                    Spacer(minLength: 8)
                    Text("\(snapshot.percent)%")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(snapshot.percent)))
                }
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ChargeStrip(level: Double(snapshot.percent) / 100, tint: tint)
            Label {
                Text(powerText)
            } icon: {
                Image(systemName: "bolt.fill")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .animation(.smooth, value: estimate)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var headline: some View {
        if let minutes = estimate.minutes {
            DurationText(minutes: minutes)
        } else {
            Text(headlineText)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
        }
    }

    private var headlineText: String {
        switch estimate {
        case .charged: "Charged"
        case .notCharging: "Not charging"
        default: "Estimating…"
        }
    }

    private var caption: String {
        switch estimate {
        case .untilEmpty: isLowPowerMode ? "left on battery · Low Power Mode" : "left on battery"
        case .untilFull: "until fully charged"
        case .charged: "Fully charged and running on power."
        case .notCharging: "Plugged in and holding here. Optimized Battery Charging or a charge limit is protecting the battery."
        case .calculating: snapshot.isPluggedIn ? "Working out how long charging will take." : "Working out how long you have left."
        }
    }

    private var powerText: String {
        if snapshot.isPluggedIn {
            let adapter = snapshot.adapter?.watts.map { "\($0) W adapter" }
            if snapshot.isCharging, snapshot.batteryPower > 0.1 {
                let charging = "Charging at \(Format.watts(snapshot.batteryPower))"
                return adapter.map { "\(charging) from a \($0)" } ?? charging
            }
            let parts = [adapter, snapshot.systemPower.map { "Mac using \(Format.watts($0))" }].compactMap { $0 }
            return parts.isEmpty ? "On power adapter" : parts.joined(separator: " · ")
        }
        // What's draining the battery right now; the estimate follows the recent average.
        let now = abs(snapshot.batteryPower)
        var text = "Using \(Format.watts(now))"
        if let average = sessionWatts, average > 0, abs(now - average) / average > 0.25 {
            text += " · recent average \(Format.watts(average))"
        } else if let typical = typicalWatts, typical > 0, abs(typical - now) / typical > 0.25 {
            text += " · usually \(Format.watts(typical))"
        }
        return text
    }

    private var tint: Color {
        if snapshot.isPluggedIn && (snapshot.isCharging || snapshot.percent >= 100) { return .green }
        if isLowPowerMode { return .yellow }
        if snapshot.percent <= 10 { return .red }
        if snapshot.percent <= 20 { return .orange }
        return .primary
    }
}

/// "10h 48m" with the units set smaller than the numbers.
struct DurationText: View {
    let minutes: Int

    var body: some View {
        let hours = minutes / 60, remainder = minutes % 60
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if hours > 0 {
                number(hours)
                unit("h").padding(.trailing, 8)
            }
            if hours == 0 || remainder > 0 {
                number(remainder)
                unit("m")
            }
        }
        .accessibilityLabel(Format.spokenDuration(minutes))
    }

    private func number(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 40, weight: .semibold, design: .rounded))
            .contentTransition(.numericText(value: Double(value)))
    }

    private func unit(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }
}

/// The strip: a meter whose fill carries the battery's state, on a track of the same hue.
struct ChargeStrip: View {
    let level: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let fraction = min(max(level, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.14))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(proxy.size.height, proxy.size.width * fraction))
            }
        }
        .frame(height: 8)
        .animation(.smooth, value: level)
        .accessibilityHidden(true)
    }
}
