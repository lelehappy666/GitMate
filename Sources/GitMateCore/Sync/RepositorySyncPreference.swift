public enum RepositorySyncMode: String, CaseIterable, Codable, Sendable {
    case never
    case manual
    case automatic
}

public struct RepositorySyncPreference: Equatable, Codable, Sendable {
    public let repositoryID: Int64
    public var mode: RepositorySyncMode

    public init(repositoryID: Int64, mode: RepositorySyncMode) {
        self.repositoryID = repositoryID
        self.mode = mode
    }

    public var shouldSyncInitially: Bool {
        mode != .never
    }
}
