import Foundation

public struct CommitGraphAuthorAvatarIdentity: Equatable, Sendable {
    public let remoteURL: URL?
    public let fallbackInitials: String
    public let fallbackColorIndex: Int

    public init(
        remoteURL: URL?,
        fallbackInitials: String,
        fallbackColorIndex: Int
    ) {
        self.remoteURL = remoteURL
        self.fallbackInitials = fallbackInitials
        self.fallbackColorIndex = fallbackColorIndex
    }

    public static func resolve(
        authorName: String,
        authorEmail: String,
        currentUserLogin: String?,
        currentUserName: String?,
        currentUserAvatarURL: URL?
    ) -> Self {
        let fallbackSource = normalizedFallbackSource(
            authorName: authorName,
            authorEmail: authorEmail
        )
        let initials = initials(from: fallbackSource)
        let colorIndex = stableColorIndex(
            "\(authorName.trimmingCharacters(in: .whitespacesAndNewlines))|\(authorEmail)"
        )

        if let login = githubLogin(from: authorEmail) {
            return Self(
                remoteURL: URL(string: "https://github.com/\(login).png"),
                fallbackInitials: initials,
                fallbackColorIndex: colorIndex
            )
        }

        let normalizedAuthor = comparisonKey(authorName)
        let matchesCurrentAccount = !normalizedAuthor.isEmpty
            && [currentUserLogin, currentUserName]
                .compactMap { $0 }
                .map(comparisonKey)
                .contains(normalizedAuthor)
        return Self(
            remoteURL: matchesCurrentAccount ? currentUserAvatarURL : nil,
            fallbackInitials: initials,
            fallbackColorIndex: colorIndex
        )
    }

    private static func githubLogin(from email: String) -> String? {
        let normalized = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized.hasSuffix("@users.noreply.github.com"),
              let local = normalized.split(separator: "@", maxSplits: 1).first
        else {
            return nil
        }
        let candidate = local
            .split(separator: "+", maxSplits: 1)
            .last
            .map(String.init) ?? String(local)
        guard !candidate.isEmpty,
              candidate.allSatisfy({
                  $0.isLetter || $0.isNumber || $0 == "-"
              })
        else {
            return nil
        }
        return candidate
    }

    private static func normalizedFallbackSource(
        authorName: String,
        authorEmail: String
    ) -> String {
        let name = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }
        let local = authorEmail.split(separator: "@", maxSplits: 1).first
        return local.map(String.init) ?? "?"
    }

    private static func initials(from source: String) -> String {
        let words = source.split { character in
            character.isWhitespace
                || character == "."
                || character == "_"
                || character == "-"
                || character == "+"
        }
        let characters: [Character]
        if words.count >= 2 {
            characters = words.prefix(2).compactMap(\.first)
        } else if let word = words.first {
            characters = Array(word.prefix(2))
        } else {
            characters = ["?"]
        }
        return String(characters).uppercased()
    }

    private static func comparisonKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
    }

    private static func stableColorIndex(_ value: String) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return Int(hash % 6)
    }
}
