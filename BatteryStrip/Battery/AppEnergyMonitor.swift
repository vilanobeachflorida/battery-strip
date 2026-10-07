import AppKit
import Darwin
import Observation

/// Which apps are using the most energy, from the processor energy macOS attributes to each process.
///
/// It samples once a minute, which takes a few milliseconds, and again whenever the panel opens.
/// Helper processes count toward the app they belong to, so Chrome's renderers show up as Chrome.
@Observable
final class AppEnergyMonitor {
    struct App: Identifiable, Equatable {
        /// The app bundle's path, an executable name, or "macOS" for system services.
        let id: String
        let name: String
        /// Average over the last few minutes.
        let watts: Double
    }

    /// Up to three apps averaging at least a quarter of a watt, busiest first.
    private(set) var topApps: [App] = []

    @ObservationIgnored private var counters: [pid_t: Counter] = [:]
    @ObservationIgnored private var lastSample: Date?
    @ObservationIgnored private var averages: [String: Double] = [:]
    @ObservationIgnored private var names: [String: String] = [:]
    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private var timer: Timer?

    private struct Counter {
        let start: UInt64
        let energy: UInt64
        let key: String
    }

    func start() {
        sample()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 20
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Takes a fresh sample unless one was taken in the last few seconds.
    func refresh() {
        if let lastSample, Date.now.timeIntervalSince(lastSample) < 5 { return }
        sample()
    }

    func icon(for id: String) -> NSImage? {
        guard id.hasSuffix(".app") else { return nil }
        if let icon = icons[id] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: id)
        icons[id] = icon
        return icon
    }

    private func sample(now: Date = .now) {
        let interval = lastSample.map { now.timeIntervalSince($0) } ?? 0
        var next: [pid_t: Counter] = [:]
        var joules: [String: Double] = [:]

        for pid in Self.allProcessIDs() {
            // Other users' processes, including the system's own, can't be read; that's fine.
            guard let usage = Self.usage(of: pid) else { continue }
            let key: String
            if let previous = counters[pid], previous.start == usage.start {
                key = previous.key
                if usage.energy >= previous.energy {
                    joules[key, default: 0] += Double(usage.energy - previous.energy) / 1e9
                }
            } else {
                key = Self.appKey(for: pid)
                // New since the last sample, so all of its energy is new too.
                if lastSample != nil {
                    joules[key, default: 0] += Double(usage.energy) / 1e9
                }
            }
            next[pid] = Counter(start: usage.start, energy: usage.energy, key: key)
        }
        counters = next
        lastSample = now
        guard interval > 1 else { return }

        // Average over a few minutes, so a brief burst doesn't top the list and a busy app stays visible.
        let weight = 1 - exp(-interval / 240)
        for key in Set(averages.keys).union(joules.keys) {
            let watts = (joules[key] ?? 0) / interval
            let average = averages[key].map { $0 + weight * (watts - $0) } ?? watts
            averages[key] = average < 0.005 ? nil : average
        }

        let top = averages
            .filter { $0.value >= 0.25 }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { App(id: $0.key, name: name(for: $0.key), watts: $0.value) }
        if top != topApps { topApps = top }
    }

    private func name(for key: String) -> String {
        if let name = names[key] { return name }
        let name: String
        if key == "macOS" {
            name = "macOS services"
        } else if key.hasSuffix(".app") {
            let bundle = Bundle(path: key)
            name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? URL(fileURLWithPath: key).deletingPathExtension().lastPathComponent
        } else {
            name = key
        }
        names[key] = name
        return name
    }

    // MARK: - Process information

    private static func allProcessIDs() -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 4096)
        let count = proc_listallpids(&buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        return Array(buffer.prefix(max(0, Int(count))))
    }

    private static func usage(of pid: pid_t) -> (start: UInt64, energy: UInt64)? {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
            }
        }
        return result == 0 ? (info.ri_proc_start_abstime, info.ri_energy_nj) : nil
    }

    /// Groups a process under the app people know: helpers live inside their app's bundle, so the
    /// outermost .app in the path is the one to show.
    private static func appKey(for pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "macOS" }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        if let range = path.range(of: ".app/") {
            return String(path[..<range.upperBound].dropLast())
        }
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/") || path.hasPrefix("/Library/Apple/") {
            return "macOS"
        }
        return (path as NSString).lastPathComponent
    }
}
