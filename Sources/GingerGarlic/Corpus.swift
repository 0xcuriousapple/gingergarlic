import Foundation
import NaturalLanguage

struct CorpusEntry: Codable {
    let ts: Date
    let draft: String
    let rewrite: String
    var accepted: Bool
}

/// Draft→rewrite pairs used as few-shot examples so the tool mirrors how
/// this specific author writes. Privacy default: pairs live in memory for
/// the current session only. Writing them to disk (corpus.jsonl, the future
/// LoRA training set) is strictly opt-in via the menu, because it means
/// persisting the user's raw messages.
actor Corpus {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/gingergarlic/corpus.jsonl")

    private let fileURL: URL
    private var entries: [CorpusEntry] = []
    private var vectors: [[Double]?] = []
    /// Mirror of what's actually in the file — a subset of `entries` when
    /// the user opted in mid-session.
    private var persisted: [CorpusEntry] = []
    private var persistToDisk: Bool
    private var embedder: NLEmbedding?
    private var loaded = false

    init(fileURL: URL = Corpus.defaultURL, persistToDisk: Bool = false) {
        self.fileURL = fileURL
        self.persistToDisk = persistToDisk
    }

    // MARK: - Public API

    func setPersist(_ enabled: Bool) {
        ensureLoaded()
        persistToDisk = enabled
    }

    func persistedCount() -> Int {
        ensureLoaded()
        return persisted.count
    }

    /// Deletes the on-disk history and everything learned this session.
    func wipe() {
        ensureLoaded()
        entries.removeAll()
        vectors.removeAll()
        persisted.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    func log(draft: String, rewrite: String) {
        ensureLoaded()
        let entry = CorpusEntry(ts: Date(), draft: draft, rewrite: rewrite, accepted: true)
        entries.append(entry)
        vectors.append(embed(draft))
        if persistToDisk {
            persisted.append(entry)
            appendToFile(entry)
        }
    }

    /// Called when the user hits undo: the last rewrite wasn't what they
    /// wanted, so keep it out of the few-shot pool (and available as a
    /// negative for future adapter training).
    func markLastRejected() {
        ensureLoaded()
        guard !entries.isEmpty else { return }
        entries[entries.count - 1].accepted = false
        // Update the file only if that exact pair made it to disk.
        if persistToDisk, let last = entries.last,
           let index = persisted.lastIndex(where: { $0.ts == last.ts && $0.draft == last.draft }) {
            persisted[index].accepted = false
            rewriteFile()
        }
    }

    func acceptedCount() -> Int {
        ensureLoaded()
        return entries.lazy.filter(\.accepted).count
    }

    /// Up to k accepted pairs to use as few-shot examples: most similar
    /// drafts first (NLEmbedding cosine), backfilled with the most recent
    /// accepted pairs. The examples teach voice more than topic, so a recent
    /// pair is always better than no pair; the similarity floor only decides
    /// which slots go to topical matches.
    func similar(to draft: String, k: Int = 3, minSimilarity: Double = 0.45) -> [CorpusEntry] {
        ensureLoaded()
        var scored: [(score: Double, index: Int)] = []
        if let query = embed(draft) {
            for (i, vector) in vectors.enumerated() {
                guard entries[i].accepted, let vector else { continue }
                let score = Self.cosine(query, vector)
                if score >= minSimilarity {
                    scored.append((score, i))
                }
            }
            scored.sort { $0.score > $1.score }
        }

        var result: [CorpusEntry] = []
        var seenDrafts = Set<String>()
        for (_, index) in scored {
            let entry = entries[index]
            if seenDrafts.insert(entry.draft).inserted {
                result.append(entry)
            }
            if result.count == k { return result }
        }
        for entry in entries.reversed() {
            guard entry.accepted, seenDrafts.insert(entry.draft).inserted else { continue }
            result.append(entry)
            if result.count == k { break }
        }
        return result
    }

    // MARK: - Internals

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        embedder = NLEmbedding.sentenceEmbedding(for: .english)
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for line in text.split(separator: "\n") {
            guard let entry = try? decoder.decode(CorpusEntry.self, from: Data(line.utf8)) else { continue }
            entries.append(entry)
            persisted.append(entry)
            vectors.append(embed(entry.draft))
        }
    }

    private func embed(_ text: String) -> [Double]? {
        embedder?.vector(for: text.lowercased())
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denominator = (na * nb).squareRoot()
        return denominator > 0 ? dot / denominator : 0
    }

    private func encodeLine(_ entry: CorpusEntry) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(entry)
    }

    private func appendToFile(_ entry: CorpusEntry) {
        guard var data = encodeLine(entry) else { return }
        data.append(Data("\n".utf8))
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }

    private func rewriteFile() {
        var data = Data()
        for entry in persisted {
            guard let line = encodeLine(entry) else { continue }
            data.append(line)
            data.append(Data("\n".utf8))
        }
        try? data.write(to: fileURL)
    }
}
