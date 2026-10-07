import AppKit
import Observation

/// Asks GitHub twice a week whether there's a newer release, and remembers what it found until this copy is
/// updated. It only tells people about it: they download and install the new version themselves.
@Observable
final class UpdateChecker {
    nonisolated struct Update: Equatable {
        let version: String
        /// The release's disk image, or its page when there's no disk image attached.
        let download: URL
    }

    enum State: Equatable {
        case idle, checking, checked, failed
    }

    private(set) var available: Update?
    private(set) var state: State = .idle
    private var dismissedVersion: String?

    /// The new version to mention in the panel, unless it was dismissed or checking is turned off.
    var notice: Update? {
        guard preferences.checkForUpdates, let available, available.version != dismissedVersion else { return nil }
        return available
    }

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let scheduler = NSBackgroundActivityScheduler(identifier: "com.batterystrip.BatteryStrip.UpdateCheck")

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/vilanobeachflorida/battery-strip/releases/latest")!
    /// Twice a week.
    private static let checkInterval: TimeInterval = 3.5 * 24 * 60 * 60
    private static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    private enum Key {
        static let lastCheck = "LastUpdateCheck"
        static let availableVersion = "AvailableUpdateVersion"
        static let availableDownload = "AvailableUpdateDownload"
        static let dismissedVersion = "DismissedUpdateVersion"
    }

    init(preferences: Preferences) {
        self.preferences = preferences
        dismissedVersion = defaults.string(forKey: Key.dismissedVersion)
        // A version found by an earlier check, until this copy catches up with it.
        if let version = defaults.string(forKey: Key.availableVersion),
           let download = defaults.url(forKey: Key.availableDownload),
           Self.isNewer(version, than: Self.currentVersion) {
            available = Update(version: version, download: download)
        }
    }

    func start() {
        // A new install is already the latest version, so its first check waits like the rest.
        if defaults.object(forKey: Key.lastCheck) == nil {
            defaults.set(Date.now, forKey: Key.lastCheck)
        }
        // Twice a day, macOS picks an energy-efficient moment to see whether a check is due.
        scheduler.repeats = true
        scheduler.interval = 12 * 60 * 60
        scheduler.tolerance = 60 * 60
        scheduler.qualityOfService = .utility
        // The block runs on a background queue, so it hops to the main actor.
        scheduler.schedule { @Sendable [weak self] completion in
            Task { @MainActor in await self?.checkIfDue() }
            completion(.finished)
        }
        // Also shortly after launch, for Macs that restart more often than that.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            await self?.checkIfDue()
        }
    }

    func check() async {
        guard state != .checking else { return }
        state = .checking
        do {
            let latest = try await fetchLatestRelease()
            defaults.set(Date.now, forKey: Key.lastCheck)
            if let latest, Self.isNewer(latest.version, than: Self.currentVersion) {
                available = latest
                defaults.set(latest.version, forKey: Key.availableVersion)
                defaults.set(latest.download, forKey: Key.availableDownload)
            } else {
                available = nil
                defaults.removeObject(forKey: Key.availableVersion)
                defaults.removeObject(forKey: Key.availableDownload)
            }
            state = .checked
        } catch {
            state = .failed
        }
    }

    /// Hides the panel's note until there's an even newer version.
    func dismiss() {
        dismissedVersion = available?.version
        defaults.set(dismissedVersion, forKey: Key.dismissedVersion)
    }

    private func checkIfDue() async {
        let lastCheck = defaults.object(forKey: Key.lastCheck) as? Date ?? .distantPast
        guard preferences.checkForUpdates, Date.now.timeIntervalSince(lastCheck) >= Self.checkInterval else { return }
        await check()
    }

    /// The newest published release, or nil when there isn't one yet.
    private func fetchLatestRelease() async throws -> Update? {
        var request = URLRequest(url: Self.latestReleaseURL, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // No cookies or cache: the request carries nothing but the question.
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let release = try decoder.decode(Release.self, from: data)
            let diskImage = release.assets.first { $0.name.hasSuffix(".dmg") }?.browserDownloadUrl
            return Update(version: String(release.tagName.drop { !$0.isNumber }), download: diskImage ?? release.htmlUrl)
        case 404:
            return nil
        default:
            throw URLError(.badServerResponse)
        }
    }

    private nonisolated struct Release: Decodable {
        nonisolated struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }

        let tagName: String
        let htmlUrl: URL
        let assets: [Asset]
    }

    /// Compares dotted version numbers, such as 1.0.1 with 1.0.
    static func isNewer(_ version: String, than current: String) -> Bool {
        let numbers = { (text: String) in text.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let new = numbers(version), old = numbers(current)
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}
