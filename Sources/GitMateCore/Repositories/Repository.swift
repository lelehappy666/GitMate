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

    public init(
        id: Int64,
        name: String,
        fullName: String,
        isPrivate: Bool,
        defaultBranch: String,
        sizeInKilobytes: Int,
        cloneURL: URL,
        ownerAvatarURL: URL?
    ) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.isPrivate = isPrivate
        self.defaultBranch = defaultBranch
        self.sizeInKilobytes = sizeInKilobytes
        self.cloneURL = cloneURL
        self.ownerAvatarURL = ownerAvatarURL
    }
}
