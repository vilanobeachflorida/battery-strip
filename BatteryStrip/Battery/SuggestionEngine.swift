import Foundation
import FoundationModels
import Observation

/// What the suggestion is based on, gathered when the panel opens.
nonisolated struct SuggestionFacts {
    var percent: Int
    var isPluggedIn: Bool
    var isCharging: Bool
    var estimate: TimeEstimate
    var watts: Double
    var averageWatts: Double?
    var typicalWatts: Double?
    var topApps: [(name: String, watts: Double)]
    var isLowPowerMode: Bool
    var health: Int
    var temperatureCelsius: Double?
    /// Already in the person's chosen unit.
    var temperatureText: String?

    /// The facts as plain sentences, which is also what the model is given.
    var summary: String {
        var lines: [String] = []
        switch estimate {
        case .untilEmpty(let minutes): lines.append("Battery at \(percent)%, on battery, about \(Format.duration(minutes)) left at recent usage.")
        case .untilFull(let minutes): lines.append("Battery at \(percent)%, charging, about \(Format.duration(minutes)) until full.")
        case .charged: lines.append("Battery at \(percent)%, plugged in and fully charged.")
        case .notCharging: lines.append("Battery at \(percent)%, plugged in but holding instead of charging.")
        case .calculating: lines.append("Battery at \(percent)%, \(isPluggedIn ? "plugged in" : "on battery").")
        }
        var power = "Power now: \(Format.watts(watts))."
        if let averageWatts { power += " Recent average: \(Format.watts(averageWatts))." }
        if let typicalWatts { power += " Usual on battery: \(Format.watts(typicalWatts))." }
        lines.append(power)
        if topApps.isEmpty {
            lines.append("No app is using much energy.")
        } else {
            lines.append("Apps using the most energy: " + topApps.map { "\($0.name) \(Format.watts($0.watts))" }.joined(separator: ", ") + ".")
        }
        lines.append("Low Power Mode: \(isLowPowerMode ? "on" : "off").")
        lines.append("Battery health: \(health)%." + (temperatureText.map { " Battery temperature: \($0)." } ?? ""))
        return lines.joined(separator: "\n")
    }

    /// The one thing most worth mentioning, or nil when nothing stands out.
    var finding: Finding? {
        if !isPluggedIn, percent <= 20 {
            return Finding(
                key: "low-\(percent / 5)",
                focus: isLowPowerMode
                    ? "The battery is low and Low Power Mode is already on. Best step: plug in soon."
                    : "The battery is low and Low Power Mode is off. Best step: turn on Low Power Mode.",
                fallback: isLowPowerMode ? "Battery is low. Plug in soon to keep going." : "Battery is low. Low Power Mode can stretch the time you have left."
            )
        }
        if let top = topApps.first, top.watts >= 2, topApps.count == 1 || top.watts >= 2 * topApps[1].watts {
            return Finding(
                key: "app-\(top.name)",
                focus: "\(top.name) is using far more energy than any other app. Best step: quit \(top.name) when it's not needed.",
                fallback: isPluggedIn
                    ? "\(top.name) is using far more energy than your other apps right now."
                    : "\(top.name) is using far more energy than your other apps. Quitting it when you're done would help your battery last."
            )
        }
        if !isPluggedIn, let typicalWatts, let averageWatts, averageWatts >= 1.6 * typicalWatts {
            let ratio = Int((averageWatts / typicalWatts).rounded())
            return Finding(
                key: "draw-\(ratio)",
                focus: "Power use is about \(ratio) times this Mac's usual."
                    + (topApps.first.map { " Best step: quit \($0.name) if it isn't needed." } ?? ""),
                fallback: "You're using about \(ratio) times your usual power, so the battery will run down faster than usual."
            )
        }
        if let temperatureCelsius, temperatureCelsius >= 40 {
            return Finding(
                key: "warm",
                focus: "The battery is warm. Best step: let the Mac cool down, away from heat and soft surfaces.",
                fallback: "Your battery is warm. Batteries last longer when they're kept cool."
            )
        }
        if health < 80 {
            return Finding(
                key: "health",
                focus: "Battery health is below 80%. Best step: consider a battery service.",
                fallback: "Battery health is below 80%, the level where Apple recommends a battery service."
            )
        }
        return nil
    }

    struct Finding {
        /// Identifies the situation, so the same one isn't rewritten every time the panel opens.
        let key: String
        /// What the model is asked to write about.
        let focus: String
        /// Used when Apple Intelligence isn't available.
        let fallback: String
    }
}

/// A one-line suggestion about the battery, shown only when something stands out.
///
/// Plain rules decide whether anything is worth saying. When Apple Intelligence is available, the
/// on-device model words it from the same facts, and any reply with a number that isn't in the facts
/// is thrown out. The model only runs when there's something to say, and the wording is kept for a
/// while, so it costs next to no energy.
@Observable
final class SuggestionEngine {
    struct Suggestion: Equatable {
        let text: String
        let isWrittenByAI: Bool
    }

    private(set) var suggestion: Suggestion?

    @ObservationIgnored private var currentKey: String?
    @ObservationIgnored private var writtenAt: Date?
    @ObservationIgnored private var task: Task<Void, Never>?

    static var isAppleIntelligenceAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    func update(with facts: SuggestionFacts, useAppleIntelligence: Bool) {
        guard let finding = facts.finding else {
            task?.cancel()
            currentKey = nil
            if suggestion != nil { suggestion = nil }
            return
        }
        // Keep the wording while the same thing stands out, rewriting it at most every ten minutes.
        if finding.key == currentKey, let writtenAt, Date.now.timeIntervalSince(writtenAt) < 600, suggestion != nil { return }
        currentKey = finding.key
        writtenAt = .now
        task?.cancel()

        guard useAppleIntelligence, Self.isAppleIntelligenceAvailable else {
            suggestion = Suggestion(text: finding.fallback, isWrittenByAI: false)
            return
        }
        let facts = facts.summary
        let key = finding.key
        task = Task { [weak self] in
            let written = await Self.write(about: finding.focus, facts: facts)
            guard let self, !Task.isCancelled, currentKey == key else { return }
            suggestion = written.map { Suggestion(text: $0, isWrittenByAI: true) }
                ?? Suggestion(text: finding.fallback, isWrittenByAI: false)
        }
    }

    private static let instructions = """
        You write a single short sentence, at most 22 words, for the owner of a MacBook about its battery. \
        Use only the facts provided. Don't quote any numbers, because the owner can already see them. \
        Write about what stands out and suggest the best step you're given, in your own words. \
        Plain, friendly language. No greetings, emoji or quotation marks.
        """

    private static func write(about focus: String, facts: String) async -> String? {
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(
                to: "\(facts)\nWhat stands out: \(focus)",
                options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 60)
            )
            return validated(response.content, facts: facts + "\n" + focus)
        } catch {
            return nil
        }
    }

    /// Rejects anything empty, rambling, or quoting a number that isn't in the facts.
    nonisolated static func validated(_ text: String, facts: String) -> String? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'"))
        guard !cleaned.isEmpty, cleaned.count <= 160 else { return nil }
        let numbers = cleaned.matches(of: /\d+(?:\.\d+)?/).map { String($0.output) }
        guard numbers.allSatisfy({ facts.contains($0) }) else { return nil }
        return cleaned
    }
}
