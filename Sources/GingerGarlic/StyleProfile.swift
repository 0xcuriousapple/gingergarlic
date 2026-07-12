import Foundation

/// Content-free personalization. Instead of storing what the user writes,
/// this keeps aggregate counters: which shorthand they use (from a fixed
/// lexicon, so arbitrary words can never leak into the file), how long their
/// messages run, punctuation habits. The profile turns into a short "author
/// habits" block in the prompt. No message is reconstructable from it.
actor StyleProfile {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/gingergarlic/profile.json")

    struct Stats: Codable {
        var drafts = 0
        var totalWords = 0
        var shorthandCounts: [String: Int] = [:]
        var endsWithPeriod = 0
        var exclamations = 0
        var questions = 0
    }

    /// Only these tokens may ever be counted — the privacy boundary.
    private static let lexicon: Set<String> = [
        "u", "ur", "r", "tmrw", "tho", "thru", "cuz", "bc", "pls", "plz",
        "ppl", "msg", "idk", "ngl", "lol", "lmao", "lmaooo", "imo", "btw",
        "rn", "tbh", "fr", "omg", "wtf", "af", "gonna", "gotta", "wanna",
        "kinda", "sorta", "dunno", "yeah", "yo", "nah", "hmm", "bruh",
        "lowkey", "highkey", "deadass", "sus", "based", "goated", "fam",
    ]

    private let fileURL: URL
    private var stats: Stats
    private var loaded = false

    init(fileURL: URL = StyleProfile.defaultURL) {
        self.fileURL = fileURL
        self.stats = Stats()
    }

    func update(with draft: String) {
        ensureLoaded()
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let words = trimmed.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        stats.drafts += 1
        stats.totalWords += words.count
        for word in words {
            let token = word.trimmingCharacters(in: .punctuationCharacters)
            if Self.lexicon.contains(token) {
                stats.shorthandCounts[token, default: 0] += 1
            }
        }
        if trimmed.hasSuffix(".") { stats.endsWithPeriod += 1 }
        if trimmed.contains("!") { stats.exclamations += 1 }
        if trimmed.contains("?") { stats.questions += 1 }
        save()
    }

    func draftCount() -> Int {
        ensureLoaded()
        return stats.drafts
    }

    /// Prompt block describing observed habits; nil until there's enough
    /// signal to say anything meaningful.
    func promptBlock() -> String? {
        ensureLoaded()
        guard stats.drafts >= 5 else { return nil }

        var lines = ["Observed habits of this author (aggregate stats):"]
        let favorites = stats.shorthandCounts.sorted { $0.value > $1.value }
            .prefix(8).map(\.key)
        if !favorites.isEmpty {
            lines.append("- shorthand they actually use (keep these): \(favorites.joined(separator: ", "))")
        }
        let avgWords = stats.totalWords / max(stats.drafts, 1)
        lines.append("- typical message length: about \(avgWords) words — don't pad beyond it")
        lines.append("- ends messages with a period: \(Self.frequencyLabel(stats.endsWithPeriod, stats.drafts))")
        lines.append("- uses exclamation marks: \(Self.frequencyLabel(stats.exclamations, stats.drafts))")
        return lines.joined(separator: "\n")
    }

    private static func frequencyLabel(_ count: Int, _ total: Int) -> String {
        guard total > 0 else { return "rarely" }
        let rate = Double(count) / Double(total)
        switch rate {
        case ..<0.15: return "rarely — don't add them"
        case ..<0.5: return "sometimes"
        default: return "usually — keep them"
        }
    }

    // MARK: - Persistence (aggregates only, never content)

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Stats.self, from: data) {
            stats = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: fileURL)
    }
}
