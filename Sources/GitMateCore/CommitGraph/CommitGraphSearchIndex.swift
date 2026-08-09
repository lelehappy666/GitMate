import Foundation

public struct CommitGraphSearchIndex: Sendable {
    private struct Entry: Sendable {
        let hash: String
        let searchableText: String
    }

    private let entries: [Entry]
    private let postingsByGram: [String: [Int]]

    public init(
        commitsNewestFirst: [GitCommit],
        fingerprint: CommitGraphReferenceFingerprint
    ) {
        let referencesByHash = Dictionary(
            grouping: fingerprint.references,
            by: \.targetHash
        ).mapValues { $0.map(\.name) }
        entries = commitsNewestFirst.map { commit in
            Entry(
                hash: commit.fullHash,
                searchableText: Self.normalize(
                    [
                        commit.fullHash,
                        commit.shortHash,
                        commit.subject,
                        commit.authorName,
                        commit.authorEmail
                    ]
                    + commit.decorations
                    + (referencesByHash[commit.fullHash] ?? [])
                )
            )
        }

        var postings: [String: [Int]] = [:]
        for (index, entry) in entries.enumerated() {
            for gram in Self.grams(entry.searchableText) {
                postings[gram, default: []].append(index)
            }
        }
        postingsByGram = postings
    }

    public static let empty = CommitGraphSearchIndex(
        commitsNewestFirst: [],
        fingerprint: CommitGraphReferenceFingerprint(
            references: [],
            headName: nil,
            headHash: nil,
            isShallow: false
        )
    )

    public func firstMatch(query: String) -> String? {
        let normalized = Self.normalize([query])
        guard !normalized.isEmpty else { return nil }
        return candidateIndices(normalized).first { index in
            entries[index].searchableText.contains(normalized)
        }.map { entries[$0].hash }
    }

    public func candidateCount(query: String) -> Int {
        let normalized = Self.normalize([query])
        guard !normalized.isEmpty else { return 0 }
        return candidateIndices(normalized).count
    }

    private func candidateIndices(_ normalized: String) -> [Int] {
        let characters = Array(normalized)
        let length = min(characters.count, 3)
        guard length > 0 else { return [] }
        let key = String(characters.prefix(length))
        return postingsByGram[key] ?? []
    }

    private static func normalize(_ values: [String]) -> String {
        values.joined(separator: "\u{1F}")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func grams(_ value: String) -> Set<String> {
        let characters = Array(value)
        guard !characters.isEmpty else { return [] }
        var result = Set<String>()
        for length in 1...min(3, characters.count) {
            guard characters.count >= length else { continue }
            for start in 0...(characters.count - length) {
                result.insert(String(characters[start..<(start + length)]))
            }
        }
        return result
    }
}
