import SwiftUI

struct StatTiles: View {
    let snapshot: BatterySnapshot
    let temperatureUnit: TemperatureUnit

    var body: some View {
        HStack(spacing: 8) {
            StatTile(title: "Health", value: "\(snapshot.maximumCapacityPercent)%", symbol: "heart.fill", tint: .pink)
                .help("Maximum capacity, the same figure System Settings shows. The exact numbers are under Details.")
            StatTile(title: "Cycles", value: snapshot.cycleCount.formatted(), symbol: "arrow.triangle.2.circlepath", tint: .blue)
                .help(snapshot.designCycleCount.map { "Rated for \($0.formatted()) cycles." } ?? "")
            StatTile(
                title: "Temperature",
                value: snapshot.temperature.map { Format.temperature($0, unit: temperatureUnit) } ?? "–",
                symbol: "thermometer.medium",
                tint: .orange
            )
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .lineLimit(1)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
