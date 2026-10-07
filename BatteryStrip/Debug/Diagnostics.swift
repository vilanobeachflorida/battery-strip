#if DEBUG
import AppKit
import Darwin
import FoundationModels
import IOKit.ps
import ServiceManagement

/// Prints which of Battery Strip's data sources this build can reach, then quits. Useful for checking
/// what still works inside the App Store sandbox. Debug builds only:
///
///     "Battery Strip.app/Contents/MacOS/Battery Strip" --diagnose
enum Diagnostics {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--diagnose") else { return }
        print("Sandboxed: \(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)")

        let snapshot = BatteryReader.read(includeTemperature: true)
        report("Battery readings (I/O Registry)", snapshot.map { "\($0.percent)%, \($0.cycleCount) cycles, \(Format.watts($0.batteryPower))" })
        report("Power source notifications (IOPowerSources)", IOPSCopyPowerSourcesInfo()?.takeRetainedValue() == nil ? nil : "ok")
        report("Battery temperature (SMC)", snapshot?.temperature.map { Format.temperature($0, unit: .celsius) })
        report("Manufacture date (SMC)", snapshot?.manufactureDate.map { $0.formatted(.dateTime.month(.wide).year()) })
        report("Apple's battery icon setting (Control Center preferences)", MenuBarSetup().isAppleBatteryIconShown.map { $0 ? "shown" : "hidden" })

        var pids = [pid_t](repeating: 0, count: 4096)
        let count = max(0, Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))))
        var energyReadable = 0, pathReadable = 0
        for pid in pids.prefix(count) where pid != getpid() {
            var info = rusage_info_v6()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
            }
            if result == 0 { energyReadable += 1 }
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if proc_pidpath(pid, &path, UInt32(path.count)) > 0 { pathReadable += 1 }
        }
        report("Other apps' energy (proc_pid_rusage)", energyReadable > 0 ? "\(energyReadable) of \(count) processes" : nil)
        report("Other apps' names (proc_pidpath)", pathReadable > 0 ? "\(pathReadable) of \(count) processes" : nil)
        report("Apple Intelligence", SystemLanguageModel.default.isAvailable ? "available" : nil)
        report("Open at login (SMAppService)", "status \(SMAppService.mainApp.status.rawValue)")
        exit(0)
    }

    private static func report(_ name: String, _ value: String?) {
        print((value == nil ? "✗ " : "✓ ") + name + ": " + (value ?? "not available"))
    }
}
#endif
