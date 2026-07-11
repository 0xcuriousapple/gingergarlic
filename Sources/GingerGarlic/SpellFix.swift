import AppKit

/// Deterministic spelling pre-pass using the system spellchecker, run before
/// the model sees the draft. A 3B model guessing corrections blind sometimes
/// invents the wrong word; NSSpellChecker's top guess anchors it. Words the
/// spellchecker can't judge (real words used wrongly, e.g. "grate" for
/// "great") are left for the model to fix from context.
enum SpellFix {
    /// Casual/meme vocabulary the spellchecker would flag but the author
    /// writes on purpose. The shorthand list in Rewriter is protected too.
    private static let slang: Set<String> = [
        "lol", "lmao", "lmaooo", "imo", "btw", "tbh", "fr", "omg", "wtf",
        "af", "ok", "gonna", "gotta", "wanna", "kinda", "sorta", "dunno",
        "yeah", "yo", "nah", "hmm", "ngl", "idk", "rn", "txt", "ish",
    ]

    @MainActor
    static func fix(_ text: String) -> String {
        let protected = slang.union(Rewriter.protectedShorthand)
        let checker = NSSpellChecker.shared
        checker.automaticallyIdentifiesLanguages = false
        _ = checker.setLanguage("en")

        var result = text
        var offset = 0
        while offset < (result as NSString).length {
            var wordCount = 0
            // wrap: false is load-bearing — the wrapping variant re-finds
            // flagged-but-protected words (like "rn") forever.
            let range = checker.checkSpelling(
                of: result, startingAt: offset, language: "en", wrap: false,
                inSpellDocumentWithTag: 0, wordCount: &wordCount
            )
            if range.location == NSNotFound || range.location < offset { break }
            let word = (result as NSString).substring(with: range)
            offset = range.location + range.length
            if protected.contains(word.lowercased()) { continue }
            if word.rangeOfCharacter(from: .decimalDigits) != nil { continue }
            guard let guess = checker.guesses(
                forWordRange: range, in: result, language: "en",
                inSpellDocumentWithTag: 0
            )?.first else { continue }
            // the author writes lowercase; don't let guesses introduce caps
            let replacement = word == word.lowercased() ? guess.lowercased() : guess
            result = (result as NSString).replacingCharacters(in: range, with: replacement)
            offset = range.location + (replacement as NSString).length
        }
        return result
    }
}
