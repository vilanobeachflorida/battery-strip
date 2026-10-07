import SwiftUI

/// The exact numbers, tucked away until asked for.
struct DetailsSection: View {
    let snapshot: BatterySnapshot
    @Binding var isExpanded: Bool

    private struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("Details")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.label)
                                .foregroundStyle(.secondary)
                            Text(row.value)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
                .font(.callout)
                // Slide out from under the header, so the rows never pass over the sections below.
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .clipped()
    }

    private var rows: [Row] {
        var rows = [
            Row(label: "Charge", value: "\(snapshot.remainingCapacity.formatted()) of \(Format.milliampHours(snapshot.fullChargeCapacity))"),
        ]
        if snapshot.designCapacity > 0 {
            let ratio = Double(snapshot.fullChargeCapacity) / Double(snapshot.designCapacity)
            rows.append(Row(label: "Full charge", value: "\(Format.milliampHours(snapshot.fullChargeCapacity)) (\(ratio.formatted(.percent.precision(.fractionLength(0)))) of new)"))
            rows.append(Row(label: "When new", value: Format.milliampHours(snapshot.designCapacity)))
        }
        if let rated = snapshot.designCycleCount {
            rows.append(Row(label: "Cycles", value: "\(snapshot.cycleCount.formatted()) of \(rated.formatted()) rated"))
        }
        if let built = snapshot.manufactureDate {
            rows.append(Row(label: "Manufactured", value: built.formatted(.dateTime.month(.wide).year())))
            rows.append(Row(label: "Age", value: Format.age(since: built)))
        }
        rows.append(Row(label: "Voltage", value: String(format: "%.2f V", snapshot.voltage)))
        rows.append(Row(label: "Current", value: String(format: "%+.2f A", snapshot.amperage)))
        rows.append(Row(label: "Battery power", value: (snapshot.batteryPower >= 0 ? "+" : "−") + Format.watts(snapshot.batteryPower)))
        if let system = snapshot.systemPower {
            rows.append(Row(label: "Mac power use", value: Format.watts(system)))
        }
        if let adapter = snapshot.adapter {
            let name = [adapter.watts.map { "\($0) W" }, adapter.name].compactMap { $0 }.joined(separator: " ")
            rows.append(Row(label: "Adapter", value: name.isEmpty ? "Connected" : name))
        }
        if let input = snapshot.adapterPower {
            rows.append(Row(label: "From adapter", value: Format.watts(input)))
        }
        if let estimate = snapshot.isPluggedIn ? snapshot.systemTimeToFull : snapshot.systemTimeToEmpty {
            rows.append(Row(label: "macOS estimate", value: Format.duration(estimate)))
        }
        return rows
    }
}
