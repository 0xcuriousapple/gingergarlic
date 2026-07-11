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
            guard let guesses = checker.guesses(
                forWordRange: range, in: result, language: "en",
                inSpellDocumentWithTag: 0
            ), let top = guesses.first else { continue }
            // The top guess is frequency-ranked but context-blind and can be
            // a different word than intended ("depoly" -> "deeply"). A
            // candidate one edit away (usually a transposition) is almost
            // always the intended word, so it overrides a top guess that's
            // two or more edits out ("depoly" -> "deploy"). Otherwise trust
            // the dictionary's ranking ("tommow" -> "tomorrow", not "tommy").
            var guess = top
            if Self.editDistance(word, top) >= 2,
               let oneEdit = guesses.first(where: { Self.editDistance(word, $0) == 1 }) {
                guess = oneEdit
            }
            // the author writes lowercase; don't let guesses introduce caps
            let replacement = word == word.lowercased() ? guess.lowercased() : guess
            result = (result as NSString).replacingCharacters(in: range, with: replacement)
            offset = range.location + (replacement as NSString).length
        }
        return result
    }

    /// Damerau-Levenshtein: edit distance where a transposition counts as
    /// one edit, since transpositions are the most common typing mistake.
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let s = Array(a.lowercased()), t = Array(b.lowercased())
        if s.isEmpty || t.isEmpty { return max(s.count, t.count) }
        var d = [[Int]](repeating: [Int](repeating: 0, count: t.count + 1), count: s.count + 1)
        for i in 0...s.count { d[i][0] = i }
        for j in 0...t.count { d[0][j] = j }
        for i in 1...s.count {
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[s.count][t.count]
    }
}
