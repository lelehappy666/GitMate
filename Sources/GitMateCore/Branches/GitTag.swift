import Foundation

public enum GitTagKind: String, Codable, Sendable {
    case lightweight
    case annotated
}

public enum TagRemoteStatus: String, Codable, Sendable {
    case localOnly
    case remoteOnly
    case synchronized
}

public struct GitTag: Identifiable, Equatable, Codable, Sendable {
    public var id: String { name }

    public let name: String
    public let objectSHA: String
    public var targetSHA: String?
    public let kind: GitTagKind
    public var existsLocally: Bool
    public var existsRemotely: Bool
    public var taggerName: String?
    public var createdAt: Date?
    public var message: String?
    public var releaseURL: URL?

    public init(
        name: String,
        objectSHA: String,
        targetSHA: String? = nil,
        kind: GitTagKind,
        existsLocally: Bool,
        existsRemotely: Bool,
        taggerName: String? = nil,
        createdAt: Date? = nil,
        message: String? = nil,
        releaseURL: URL? = nil
    ) {
        self.name = name
        self.objectSHA = objectSHA
        self.targetSHA = targetSHA
        self.kind = kind
        self.existsLocally = existsLocally
        self.existsRemotely = existsRemotely
        self.taggerName = taggerName
        self.createdAt = createdAt
        self.message = message
        self.releaseURL = releaseURL
    }

    public var remoteStatus: TagRemoteStatus {
        switch (existsLocally, existsRemotely) {
        case (true, false):
            .localOnly
        case (false, true):
            .remoteOnly
        case (true, true):
            .synchronized
        case (false, false):
            .localOnly
        }
    }
}
