import AppKit
import SwiftUI

/// The apps using the most energy over the last few minutes.
struct EnergySection: View {
    let apps: [AppEnergyMonitor.App]
    let icon: (String) -> NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Using the most energy")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if apps.isEmpty {
                Text("No apps are using significant energy.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(apps) { app in
                    HStack(spacing: 8) {
                        appIcon(app)
                            .frame(width: 18, height: 18)
                        Text(app.name)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Format.watts(app.watts))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
        .help("Processor energy each app has used over the last few minutes")
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func appIcon(_ app: AppEnergyMonitor.App) -> some View {
        if let image = icon(app.id) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: app.id == "macOS" ? "applelogo" : app.id.hasSuffix(".app") ? "app" : "terminal")
                .foregroundStyle(.secondary)
        }
    }
}
