import Foundation

public final class GitRepositorySyncService: RepositorySyncService, @unchecked Sendable {
    private let executor: any CommandExecuting
    private let fileManager: FileManager

    public init(
        executor: any CommandExecuting = ProcessCommandExecutor(),
        fileManager: FileManager = .default
    ) {
        self.executor = executor
        self.fileManager = fileManager
    }

    public func sync(
        repositories: [Repository],
        preferences: [RepositorySyncPreference],
        destination: URL,
        accessToken: String?
    ) -> AsyncThrowingStream<SyncEvent, Error> {
        let selectedIDs = Set(
            preferences
                .filter(\.shouldSyncInitially)
                .map(\.repositoryID)
        )
        let selectedRepositories = repositories.filter { selectedIDs.contains($0.id) }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try fileManager.createDirectory(
                        at: destination,
                        withIntermediateDirectories: true
                    )
                    var completed = 0

                    for repository in selectedRepositories {
                        try Task.checkCancellation()
                        continuation.yield(.repositoryStarted(repository))
                        let repositoryDirectory = destination.appending(
                            path: Self.safeDirectoryName(repository.name),
                            directoryHint: .isDirectory
                        )

                        do {
                            try await runGit(
                                for: repository,
                                at: repositoryDirectory,
                                accessToken: accessToken
                            )
                            try Task.checkCancellation()
                            for file in files(in: repositoryDirectory) {
                                continuation.yield(
                                    .fileChanged(
                                        repositoryID: repository.id,
                                        path: file
                                    )
                                )
                            }
                            completed += 1
                            continuation.yield(
                                .progress(
                                    SyncProgress(
                                        completed: completed,
                                        total: selectedRepositories.count
                                    )
                                )
                            )
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            let failure = (error as? SyncFailure)
                                ?? Self.mapFailure(message: error.localizedDescription)
                            continuation.yield(
                                .repositoryFailed(
                                    repositoryID: repository.id,
                                    failure: failure
                                )
                            )
                        }
                    }

                    continuation.yield(.finished)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: SyncFailure.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public static func mapFailure(message: String) -> SyncFailure {
        let normalized = message.lowercased()
        let authorizationMarkers = [
            "http 401",
            "http 403",
            "authentication failed",
            "bad credentials",
            "could not read username",
            "permission denied"
        ]
        if authorizationMarkers.contains(where: normalized.contains) {
            return .authorizationExpired(message)
        }

        let networkMarkers = [
            "could not resolve host",
            "network is unreachable",
            "connection timed out",
            "connection timeout",
            "connection reset",
            "failed to connect",
            "unable to access"
        ]
        if networkMarkers.contains(where: normalized.contains) {
            return .networkInterrupted(message)
        }

        return .commandFailed(message)
    }

    private func runGit(
        for repository: Repository,
        at directory: URL,
        accessToken: String?
    ) async throws {
        let gitDirectory = directory.appending(path: ".git", directoryHint: .isDirectory)
        let arguments: [String]
        if fileManager.fileExists(atPath: gitDirectory.path) {
            arguments = [
                "-C",
                directory.path,
                "fetch",
                "--prune",
                "--progress"
            ]
        } else {
            arguments = [
                "clone",
                "--progress",
                "--recurse-submodules",
                repository.cloneURL.absoluteString,
                directory.path
            ]
        }

        do {
            var environment: [String: String] = [:]
            if let accessToken, !accessToken.isEmpty {
                environment = [
                    "GIT_CONFIG_COUNT": "1",
                    "GIT_CONFIG_KEY_0": "http.extraHeader",
                    "GIT_CONFIG_VALUE_0": "Authorization: " + "Bearer " + accessToken
                ]
            }
            for try await _ in executor.execute(
                arguments: arguments,
                environment: environment
            ) {
                try Task.checkCancellation()
            }
        } catch let CommandExecutionError.exitStatus(_, message) {
            throw Self.mapFailure(message: message)
        } catch {
            throw error
        }
    }

    private func files(in repositoryDirectory: URL) -> [String] {
        let resolvedRepositoryPath = repositoryDirectory
            .resolvingSymlinksInPath()
            .path
        guard let enumerator = fileManager.enumerator(
            at: repositoryDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        return enumerator.compactMap { item -> String? in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else {
                return nil
            }
            let resolvedFilePath = url.resolvingSymlinksInPath().path
            let prefix = resolvedRepositoryPath.hasSuffix("/")
                ? resolvedRepositoryPath
                : resolvedRepositoryPath + "/"
            guard resolvedFilePath.hasPrefix(prefix) else {
                return url.lastPathComponent
            }
            return String(resolvedFilePath.dropFirst(prefix.count))
        }
        .sorted()
    }

    private static func safeDirectoryName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\")
        return name.components(separatedBy: invalid).joined(separator: "-")
    }
}
