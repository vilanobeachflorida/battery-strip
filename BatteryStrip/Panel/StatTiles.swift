import SwiftUI

struct StatTiles: View {
    let snapshot: BatterySnapshot
    let temperatureUnit: TemperatureUnit
    /// Whether the health section below is open, when there's a forecast to show.
    var isHealthExpanded: Binding<Bool>?

    var body: some View {
        HStack(spacing: 8) {
            if let isHealthExpanded {
                Button {
                    withAnimation(.snappy) { isHealthExpanded.wrappedValue.toggle() }
                } label: {
                    StatTile(title: "Health", value: "\(snapshot.maximumCapacityPercent)%", symbol: "heart.fill", tint: .pink,
                             isExpanded: isHealthExpanded.wrappedValue)
                }
                .buttonStyle(TileButtonStyle(isSelected: isHealthExpanded.wrappedValue))
                .help("How much the battery holds compared with when it was new, within a percent or two of System Settings' Maximum Capacity. Click for its history and forecast.")
            } else {
                StatTile(title: "Health", value: "\(snapshot.maximumCapacityPercent)%", symbol: "heart.fill", tint: .pink)
                    .help("How much the battery holds compared with when it was new, within a percent or two of System Settings' Maximum Capacity.")
            }
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
    /// For a tile that opens a section: whether it's open.
    var isExpanded: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title)
                    .foregroundStyle(.secondary)
                if let isExpanded {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
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
        .contentShape(.rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// A tile that opens a section: a soft highlight on hover, and an outline while its section is open.
struct TileButtonStyle: ButtonStyle {
    let isSelected: Bool
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.1 : isHovered ? 0.05 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.pink.opacity(isSelected ? 0.55 : 0), lineWidth: 1)
            }
            .onHover { isHovered = $0 }
            .accessibilityValue(isSelected ? "Forecast shown" : "")
    }
}
