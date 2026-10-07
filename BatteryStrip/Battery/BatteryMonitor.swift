import AppKit
import IOKit.ps
import Observation

/// Keeps the current battery reading and time estimate up to date.
///
/// The battery refreshes its numbers once a minute and macOS announces each refresh,
/// so this never polls: it reads only when macOS says something changed.
@Observable
final class BatteryMonitor {
    private(set) var snapshot: BatterySnapshot?
    private(set) var estimate: TimeEstimate = .calculating
    private(set) var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// This session's smoothed draw on battery, in watts.
    private(set) var sessionWatts: Double?
    /// What this Mac usually draws on battery, in watts.
    private(set) var typicalWatts: Double?

    /// While the panel is open, readings also include temperature.
    var isPanelVisible = false {
        didSet { if isPanelVisible && !oldValue { refresh() } }
    }

    /// Called after each new battery reading, with the one before it.
    @ObservationIgnored var onNewReading: ((_ previous: BatterySnapshot?, _ current: BatterySnapshot) -> Void)?

    @ObservationIgnored let history = HistoryStore()
    @ObservationIgnored private let estimator = TimeEstimator()
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var saveTimer: Timer?

    func start() {
        refresh()

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(powerSourcesChanged, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        }

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveState() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled }
        })

        let timer = Timer(timeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveState() }
        }
        timer.tolerance = 120
        RunLoop.main.add(timer, forMode: .common)
        saveTimer = timer
    }

    func refresh() {
        guard var reading = BatteryReader.read(includeTemperature: isPanelVisible) else {
            snapshot = nil
            return
        }
        let previous = snapshot
        if reading.temperature == nil { reading.temperature = previous?.temperature }
        let isNewReading = reading.date != previous?.date
            || reading.isPluggedIn != previous?.isPluggedIn
            || reading.isCharging != previous?.isCharging

        estimator.ingest(reading, isNewReading: isNewReading)
        if snapshot != reading { snapshot = reading }
        if estimate != estimator.estimate { estimate = estimator.estimate }

        let session = estimator.sessionDrawMA.map { $0 / 1000 * reading.voltage }
        if sessionWatts != session { sessionWatts = session }
        let typical = estimator.typicalDrawMA.map { $0 / 1000 * reading.voltage }
        if typicalWatts != typical { typicalWatts = typical }

        if isNewReading {
            history.record(reading)
            onNewReading?(previous, reading)
        }
    }

    func saveState() {
        history.save()
        estimator.save()
    }
}

/// macOS calls this whenever the power source changes, including every battery refresh.
private nonisolated func powerSourcesChanged(_ context: UnsafeMutableRawPointer?) {
    // The source is on the main run loop, so this already runs on the main thread.
    guard let address = context.map(UInt.init(bitPattern:)) else { return }
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<BatteryMonitor>.fromOpaque(pointer).takeUnretainedValue().refresh()
    }
}
