import Foundation
import FoundationModels

final class Rewriter {
    enum RewriterError: LocalizedError {
        case modelUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .modelUnavailable(let reason): return "model unavailable: \(reason)"
            }
        }
    }

    static let recordingDefaultsKey = "recordCorpus"

    let corpus = Corpus(
        persistToDisk: UserDefaults.standard.bool(forKey: Rewriter.recordingDefaultsKey)
    )
    let profile = StyleProfile()

    /// Corpus retrieval loads an NLEmbedding model into memory. That's fine in
    /// the Mac app and the iOS container app, but a keyboard extension has a
    /// tight memory budget, so it sets this false and relies on the base
    /// prompt + the cheap aggregate style profile instead.
    var useRetrieval = true

    /// A personal LoRA adapter trained with Apple's adapter toolkit, if the
    /// user has installed one (see scripts/export_training_data.py). Loaded
    /// once at launch; relaunch after dropping the file in.
    static let adapterURL = AppPaths.file("adapter.fmadapter")

    static let model: SystemLanguageModel = {
        if FileManager.default.fileExists(atPath: adapterURL.path),
           let adapter = try? SystemLanguageModel.Adapter(fileURL: adapterURL) {
            return SystemLanguageModel(adapter: adapter)
        }
        return .default
    }()

    static var usingAdapter: Bool {
        FileManager.default.fileExists(atPath: adapterURL.path)
    }

    static func availabilityIssue() -> String? {
        switch model.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            return "\(reason)"
        }
    }

    /// Loads model resources ahead of the first hotkey press.
    func prewarm() {
        let session = LanguageModelSession(model: Self.model, instructions: Style.load())
        session.prewarm()
    }

    /// The spellchecker proposes; the model disposes. Concrete accept/reject
    /// examples matter more than the rule for a small model — "aws" reads as
    /// a typo of "was" without them.
    private static let adjudicateInstructions = """


    You may also get SPELLING SUGGESTIONS from a dictionary as word->suggestion. The dictionary is context-blind and flags names, brands, and acronyms it doesn't recognize. Apply a suggestion ONLY when it is clearly a real typo. If the original looks like a name, brand, tech term, or acronym (vpn, aws, api, ssh, mullvad, tailscale), keep the original even if the suggestion is a common word. Never mention the suggestions.

    example — draft: the aws api is down again
    spelling suggestions: aws->was, api->apt
    rewrite: the aws api is down again

    example — draft: did u recieve teh msg
    spelling suggestions: recieve->receive, teh->the
    rewrite: did u receive the msg
    """

    /// Style prompt + content-free habit profile + retrieved few-shot pairs
    /// from this session's accepted rewrites — the "learns from usage" part.
    private func instructions(for text: String) async -> String {
        var instructions = Style.load()
        if let habits = await profile.promptBlock() {
            instructions += "\n\n" + habits
        }
        let examples = useRetrieval ? await corpus.similar(to: text) : []
        if !examples.isEmpty {
            instructions += "\n\nMore examples of this author's accepted rewrites (match this voice):\n"
            for example in examples {
                instructions += "\ndraft: \(example.draft)\nrewrite: \(example.rewrite)\n"
            }
        }
        return instructions + Self.adjudicateInstructions
    }

    func rewrite(_ text: String) async throws -> String {
        if let issue = Self.availabilityIssue() {
            throw RewriterError.modelUnavailable(issue)
        }
        // Fresh session per rewrite: no context bleed between messages,
        // and the style file can be edited live between presses.
        let suggestions = await SpellFix.suggestions(for: text)
        let suggestionLine = suggestions.isEmpty ? "" :
            "\nspelling suggestions: " +
            suggestions.map { "\($0.word)->\($0.guess)" }.joined(separator: ", ")
        let session = LanguageModelSession(model: Self.model, instructions: await instructions(for: text))
        // "draft:/rewrite:" framing matches the few-shot examples, so the model
        // treats the text as material to rewrite instead of a message to answer
        // (a bare "hello i am abhi" used to get a chatbot reply). Greedy
        // sampling: same draft in, same rewrite out, every time. The model
        // sees the RAW draft plus suggestions, so it keeps "vpn"/"mullvad"
        // that a blind spell-fix would have mangled.
        let response = try await session.respond(
            to: "draft: \(text)\(suggestionLine)\nrewrite:",
            options: GenerationOptions(sampling: .greedy)
        )
        var output = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.lowercased().hasPrefix("rewrite:") {
            output = String(output.dropFirst("rewrite:".count))
                .trimmingCharacters(in: .whitespaces)
        }
        let result = Self.restoreShorthand(original: text, output: output)
        await profile.update(with: text)
        if result != text {
            await corpus.log(draft: text, rewrite: result)
        }
        return result
    }

    // MARK: - Shorthand protection

    // The model can't reliably resist expanding shorthand ("see u tmrw" ->
    // "see u tomorrow") no matter how the prompt is worded, so this is
    // enforced deterministically: any shorthand present in the original gets
    // its expansion swapped back in the output. Skipped when the original
    // also contains the expansion, since the mapping is ambiguous then.
    private static let shorthandExpansions: [(short: String, expansions: [String])] = [
        ("u", ["you"]),
        ("ur", ["your", "you're", "youre"]),
        ("r", ["are"]),
        ("tmrw", ["tomorrow"]),
        ("tho", ["though"]),
        ("thru", ["through"]),
        ("cuz", ["because"]),
        ("bc", ["because"]),
        ("pls", ["please"]),
        ("plz", ["please"]),
        ("ppl", ["people"]),
        ("msg", ["message"]),
        ("idk", ["i don't know", "i dont know"]),
        ("ngl", ["not gonna lie"]),
        ("rn", ["right now"]),
    ]

    static var protectedShorthand: Set<String> {
        Set(shorthandExpansions.map(\.short))
    }

    static func restoreShorthand(original: String, output: String) -> String {
        var result = output
        for (short, expansions) in shorthandExpansions {
            guard containsWord(original, short) else { continue }
            for expansion in expansions where !containsWord(original, expansion) {
                result = result.replacingOccurrences(
                    of: "\\b\(NSRegularExpression.escapedPattern(for: expansion))\\b",
                    with: short,
                    options: [.regularExpression, .caseInsensitive]
                )
            }
        }
        return result
    }

    private static func containsWord(_ text: String, _ word: String) -> Bool {
        text.range(
            of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}
