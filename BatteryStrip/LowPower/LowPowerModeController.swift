import Foundation
import Observation
import ServiceManagement

/// Switches Low Power Mode through the privileged helper, since macOS only lets root change power settings.
@Observable
final class LowPowerModeController {
    enum HelperStatus: Equatable {
        case notInstalled, requiresApproval, ready
    }

    private(set) var helperStatus: HelperStatus = .notInstalled
    private(set) var showsExplanation = false
    private(set) var isWorking = false
    private(set) var lastError: String?

    /// An earlier version's helper was set up, under a name this version replaced (see scripts/rename-helper.sh).
    @ObservationIgnored private var replacesOlderHelper = false
    @ObservationIgnored private var pendingValue: Bool?
    @ObservationIgnored private let service = SMAppService.daemon(plistName: HelperConstants.launchDaemonPlistName)
    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private var timeout: Task<Void, Never>?

    private static let setUpHelperKey = "SetUpHelper"

    init() {
        let setUpHelper = UserDefaults.standard.string(forKey: Self.setUpHelperKey)
        replacesOlderHelper = setUpHelper != nil && setUpHelper != HelperConstants.machServiceName
        refreshHelperStatus()
    }

    func refreshHelperStatus() {
        switch service.status {
        case .enabled: helperStatus = .ready
        case .requiresApproval: helperStatus = .requiresApproval
        default: helperStatus = .notInstalled
        }
        // Finish the switch the person asked for before approving the helper.
        if helperStatus == .ready, let value = pendingValue {
            pendingValue = nil
            showsExplanation = false
            send(value)
        }
    }

    func requestChange(to value: Bool) {
        lastError = nil
        refreshHelperStatus()
        if helperStatus == .ready {
            send(value)
        } else if helperStatus == .notInstalled, replacesOlderHelper {
            // Approved before under an older name, so there's nothing new to explain, and macOS remembers
            // that Battery Strip is allowed in the background.
            pendingValue = value
            Task { await installHelper() }
        } else {
            pendingValue = value
            showsExplanation = true
        }
    }

    func installHelper() async {
        lastError = nil
        var failure = register()
        if failure != nil, service.status == .notRegistered {
            // Just after the helper was removed, macOS can refuse to register it again for a moment.
            try? await Task.sleep(for: .seconds(1.5))
            failure = register()
        }
        refreshHelperStatus()
        if helperStatus != .notInstalled {
            UserDefaults.standard.set(HelperConstants.machServiceName, forKey: Self.setUpHelperKey)
            replacesOlderHelper = false
        }
        if helperStatus != .ready {
            showsExplanation = true
        }
        if helperStatus == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        } else if helperStatus == .notInstalled, let failure {
            lastError = "Couldn't set up the helper: \(failure.localizedDescription)"
        }
    }

    func removeHelper() async {
        connection?.invalidate()
        connection = nil
        try? await service.unregister()
        UserDefaults.standard.removeObject(forKey: Self.setUpHelperKey)
        replacesOlderHelper = false
        refreshHelperStatus()
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func dismissExplanation() {
        showsExplanation = false
        pendingValue = nil
    }

    /// Registering also throws while approval is still needed, so callers go by the status afterwards.
    private func register() -> Error? {
        do {
            try service.register()
            return nil
        } catch {
            return error
        }
    }

    private func send(_ value: Bool) {
        isWorking = true
        // Both handlers run on the connection's own queue, so they hop back to the main actor.
        let proxy = (connection ?? makeConnection()).remoteObjectProxyWithErrorHandler { @Sendable [weak self] error in
            let message = "Couldn't reach the helper: \(error.localizedDescription)"
            Task { @MainActor in self?.finish(error: message) }
        } as? BatteryStripHelperProtocol
        proxy?.setLowPowerMode(value) { @Sendable [weak self] success, message in
            Task { @MainActor in self?.finish(error: success ? nil : message ?? "Low Power Mode didn't change.") }
        }
        // The helper answers within a second. When macOS won't start it, the request would wait forever.
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled { await self?.helperDidNotStart(retrying: value) }
        }
    }

    /// Removing the helper also stops launchd retrying the waiting request every few seconds.
    private func helperDidNotStart(retrying value: Bool) async {
        guard isWorking else { return }
        isWorking = false
        connection?.invalidate()
        connection = nil
        try? await service.unregister()
        refreshHelperStatus()
        pendingValue = value
        showsExplanation = true
        lastError = "The helper didn't start. Set it up again to use Low Power Mode."
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: BatteryStripHelperProtocol.self)
        connection.invalidationHandler = { @Sendable [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func finish(error: String?) {
        // A late answer to a request that already timed out.
        guard isWorking else { return }
        timeout?.cancel()
        timeout = nil
        isWorking = false
        lastError = error
    }
}
