import Foundation

public enum SyncFailure: Error, Equatable, Sendable {
    case networkInterrupted(String)
    case authorizationExpired(String)
    case commandFailed(String)
    case cancelled

    public var message: String {
        switch self {
        case let .networkInterrupted(message),
             let .authorizationExpired(message),
             let .commandFailed(message):
            message
        case .cancelled:
            "同步已取消"
        }
    }
}

public enum SyncEvent: Equatable, Sendable {
    case repositoryStarted(Repository)
    case fileChanged(repositoryID: Int64, path: String)
    case progress(SyncProgress)
    case repositoryFailed(repositoryID: Int64, failure: SyncFailure)
    case finished
}

public protocol RepositorySyncService: Sendable {
    func sync(
        repositories: [Repository],
        preferences: [RepositorySyncPreference],
        destination: URL,
        accessToken: String?
    ) -> AsyncThrowingStream<SyncEvent, Error>
}
