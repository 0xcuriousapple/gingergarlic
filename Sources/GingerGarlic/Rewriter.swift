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

    static func availabilityIssue() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            return "\(reason)"
        }
    }

    /// Loads model resources ahead of the first hotkey press.
    func prewarm() {
        let session = LanguageModelSession(instructions: Style.load())
        session.prewarm()
    }

    func rewrite(_ text: String) async throws -> String {
        if let issue = Self.availabilityIssue() {
            throw RewriterError.modelUnavailable(issue)
        }
        // Fresh session per rewrite: no context bleed between messages,
        // and the style file can be edited live between presses.
        let spellFixed = await SpellFix.fix(text)
        let session = LanguageModelSession(instructions: Style.load())
        // "draft:/rewrite:" framing matches the few-shot examples, so the model
        // treats the text as material to rewrite instead of a message to answer
        // (a bare "hello i am abhi" used to get a chatbot reply). Greedy
        // sampling: same draft in, same rewrite out, every time.
        let response = try await session.respond(
            to: "draft: \(spellFixed)\nrewrite:",
            options: GenerationOptions(sampling: .greedy)
        )
        var output = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.lowercased().hasPrefix("rewrite:") {
            output = String(output.dropFirst("rewrite:".count))
                .trimmingCharacters(in: .whitespaces)
        }
        return Self.restoreShorthand(original: text, output: output)
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
