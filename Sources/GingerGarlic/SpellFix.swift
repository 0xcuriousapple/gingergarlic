import AppKit

/// Suggests spelling corrections using the system spellchecker — but does NOT
/// apply them. The dictionary has no context, so it "corrects" names, brands,
/// and acronyms it doesn't know (vpn->von, mullvad->mulled, aws->was). Instead
/// of blindly rewriting the draft, we hand these as suggestions to the model,
/// which sees the original word and decides whether each is a genuine typo.
enum SpellFix {
    struct Suggestion {
        let word: String
        let guess: String
    }

    /// Casual/meme vocabulary the spellchecker would flag but the author
    /// writes on purpose. The shorthand list in Rewriter is protected too.
    private static let slang: Set<String> = [
        "lol", "lmao", "lmaooo", "imo", "btw", "tbh", "fr", "omg", "wtf",
        "af", "ok", "gonna", "gotta", "wanna", "kinda", "sorta", "dunno",
        "yeah", "yo", "nah", "hmm", "ngl", "idk", "rn", "txt", "ish",
    ]

    @MainActor
    static func suggestions(for text: String) -> [Suggestion] {
        let protected = slang.union(Rewriter.protectedShorthand)
        let checker = NSSpellChecker.shared
        checker.automaticallyIdentifiesLanguages = false
        _ = checker.setLanguage("en")

        var suggestions: [Suggestion] = []
        var seen = Set<String>()
        var offset = 0
        while offset < (text as NSString).length {
            var wordCount = 0
            // wrap: false is load-bearing — the wrapping variant re-finds
            // flagged-but-protected words (like "rn") forever.
            let range = checker.checkSpelling(
                of: text, startingAt: offset, language: "en", wrap: false,
                inSpellDocumentWithTag: 0, wordCount: &wordCount
            )
            if range.location == NSNotFound || range.location < offset { break }
            let word = (text as NSString).substring(with: range)
            offset = range.location + range.length
            let lower = word.lowercased()
            if protected.contains(lower) || seen.contains(lower) { continue }
            if word.rangeOfCharacter(from: .decimalDigits) != nil { continue }
            guard let guesses = checker.guesses(
                forWordRange: range, in: text, language: "en",
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
            seen.insert(lower)
            suggestions.append(Suggestion(word: lower, guess: guess.lowercased()))
        }
        return suggestions
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
