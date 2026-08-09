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
            "下载已取消"
        }
    }
}

public enum SyncEvent: Equatable, Sendable {
    case repositoryStarted(Repository)
    case fileChanged(repositoryID: Int64, path: String)
    case repositoryProgress(
        repositoryID: Int64,
        progress: GitTransferProgress
    )
    case progress(SyncProgress)
    case repositoryFailed(repositoryID: Int64, failure: SyncFailure)
    case finished
}

public protocol RepositorySyncService: Sendable {
    func sync(
        repositories: [Repository],
        selectedRepositoryIDs: Set<Int64>,
        destination: URL,
        accessToken: String?
    ) -> AsyncThrowingStream<SyncEvent, Error>

    func pause() throws
    func resume() throws
}

public extension RepositorySyncService {
    func sync(
        repositories: [Repository],
        preferences: [RepositorySyncPreference],
        destination: URL,
        accessToken: String?
    ) -> AsyncThrowingStream<SyncEvent, Error> {
        sync(
            repositories: repositories,
            selectedRepositoryIDs: Set(
                preferences
                    .filter(\.shouldSyncInitially)
                    .map(\.repositoryID)
            ),
            destination: destination,
            accessToken: accessToken
        )
    }

    func pause() throws {
        throw CommandControlError.noActiveProcess
    }

    func resume() throws {
        throw CommandControlError.noActiveProcess
    }
}
