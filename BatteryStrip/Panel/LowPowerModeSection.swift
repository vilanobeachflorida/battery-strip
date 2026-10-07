import SwiftUI

struct LowPowerModeSection: View {
    let isOn: Bool
    let controller: LowPowerModeController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(isOn ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Low Power Mode")
                    Text(isOn ? "On, using less energy" : "Use less energy to last longer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if controller.isWorking {
                    ProgressView().controlSize(.small)
                }
                Toggle("Low Power Mode", isOn: Binding(get: { isOn }, set: { controller.requestChange(to: $0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            if controller.showsExplanation {
                HelperExplanation(controller: controller)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.snappy, value: controller.showsExplanation)
        .animation(.snappy, value: controller.helperStatus)
    }
}

/// Says why Battery Strip is about to ask for permission, before macOS asks.
struct HelperExplanation: View {
    let controller: LowPowerModeController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.helperStatus == .requiresApproval {
                Text("One more step")
                    .font(.callout.weight(.semibold))
                Text("In System Settings, under Allow in the Background, turn on Battery Strip. macOS will ask for your password. Then switch Low Power Mode here again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Login Items") { controller.openLoginItems() }
                        .buttonStyle(.borderedProminent)
                    Button("Not Now") { controller.dismissExplanation() }
                }
            } else {
                Text("Why Battery Strip needs your OK")
                    .font(.callout.weight(.semibold))
                Text("macOS only lets system-level tools switch Low Power Mode. Battery Strip includes a tiny helper that does exactly one thing: turn Low Power Mode on or off. You approve it in System Settings, and you can remove it any time in Battery Strip's settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Set Up Helper") { Task { await controller.installHelper() } }
                        .buttonStyle(.borderedProminent)
                    Button("Not Now") { controller.dismissExplanation() }
                }
            }
        }
        .controlSize(.small)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 14))
    }
}
