import Foundation

public struct Repository: Identifiable, Equatable, Codable, Sendable {
    public let id: Int64
    public let name: String
    public let fullName: String
    public let isPrivate: Bool
    public let defaultBranch: String
    public let sizeInKilobytes: Int
    public let cloneURL: URL
    public let ownerAvatarURL: URL?
    public let primaryLanguage: String?

    public init(
        id: Int64,
        name: String,
        fullName: String,
        isPrivate: Bool,
        defaultBranch: String,
        sizeInKilobytes: Int,
        cloneURL: URL,
        ownerAvatarURL: URL?,
        primaryLanguage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.isPrivate = isPrivate
        self.defaultBranch = defaultBranch
        self.sizeInKilobytes = sizeInKilobytes
        self.cloneURL = cloneURL
        self.ownerAvatarURL = ownerAvatarURL
        self.primaryLanguage = primaryLanguage
    }

    public var safeLocalDirectoryName: String {
        let invalid = CharacterSet(charactersIn: "/:\\")
        let directoryName = name.components(separatedBy: invalid).joined(separator: "-")
        if directoryName == "." || directoryName == ".." {
            return "repository-\(directoryName)"
        }
        return directoryName
    }

    public var normalizedFullName: String {
        Self.normalizedFullName(fullName)
    }

    public static func normalizedFullName(_ fullName: String) -> String {
        fullName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }
}
