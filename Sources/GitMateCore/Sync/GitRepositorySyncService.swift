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

        return AsyncThrowingStream(
            SyncEvent.self,
            bufferingPolicy: .bufferingNewest(64)
        ) { continuation in
            let task = Task.detached(priority: .utility) {
                do {
                    try self.fileManager.createDirectory(
                        at: destination,
                        withIntermediateDirectories: true
                    )
                    var completed = 0

                    for repository in selectedRepositories {
                        try Task.checkCancellation()
                        continuation.yield(.repositoryStarted(repository))
                        let repositoryDirectory = destination.appending(
                            path: repository.safeLocalDirectoryName,
                            directoryHint: .isDirectory
                        )

                        do {
                            try await self.runGit(
                                for: repository,
                                at: repositoryDirectory,
                                accessToken: accessToken,
                                onActivity: { activity in
                                    continuation.yield(
                                        .fileChanged(
                                            repositoryID: repository.id,
                                            path: activity
                                        )
                                    )
                                }
                            )
                            try Task.checkCancellation()
                            try self.reportFiles(in: repositoryDirectory) { file in
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
            "terminal prompts disabled",
            "unable to read askpass response",
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
        accessToken: String?,
        onActivity: @escaping @Sendable (String) -> Void
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
            var environment: [String: String] = [
                "GIT_TERMINAL_PROMPT": "0",
                "GCM_INTERACTIVE": "never"
            ]
            if let accessToken, !accessToken.isEmpty {
                let credential = Data(
                    "x-access-token:\(accessToken)".utf8
                )
                .base64EncodedString()
                environment["GIT_CONFIG_COUNT"] = "1"
                environment["GIT_CONFIG_KEY_0"] = "http.extraHeader"
                environment["GIT_CONFIG_VALUE_0"] = "Authorization: Basic \(credential)"
            }

            let clock = ContinuousClock()
            var lastUpdate: ContinuousClock.Instant?
            for try await output in executor.execute(
                arguments: arguments,
                environment: environment
            ) {
                try Task.checkCancellation()
                let value: String
                switch output {
                case let .standardOutput(text), let .standardError(text):
                    value = text
                }
                let activity = Self.normalizedActivity(value)
                guard !activity.isEmpty else { continue }

                let now = clock.now
                if lastUpdate == nil
                    || now - lastUpdate! >= .milliseconds(120) {
                    onActivity(activity)
                    lastUpdate = now
                }
            }
        } catch let CommandExecutionError.exitStatus(_, message) {
            throw Self.mapFailure(message: message)
        } catch {
            throw error
        }
    }

    private func reportFiles(
        in repositoryDirectory: URL,
        onFile: (String) -> Void
    ) throws {
        let resolvedRepositoryPath = repositoryDirectory
            .resolvingSymlinksInPath()
            .path
        guard let enumerator = fileManager.enumerator(
            at: repositoryDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }

        var regularFileCount = 0
        var lastReportedPath: String?
        var lastVisitedPath: String?
        let clock = ContinuousClock()
        var lastUpdate: ContinuousClock.Instant?

        while let item = enumerator.nextObject() {
            if regularFileCount.isMultiple(of: 128) {
                try Task.checkCancellation()
            }
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else {
                continue
            }
            let resolvedFilePath = url.resolvingSymlinksInPath().path
            let prefix = resolvedRepositoryPath.hasSuffix("/")
                ? resolvedRepositoryPath
                : resolvedRepositoryPath + "/"
            let relativePath = resolvedFilePath.hasPrefix(prefix)
                ? String(resolvedFilePath.dropFirst(prefix.count))
                : url.lastPathComponent
            regularFileCount += 1
            lastVisitedPath = relativePath

            let now = clock.now
            if lastUpdate == nil
                || now - lastUpdate! >= .milliseconds(120) {
                onFile(relativePath)
                lastReportedPath = relativePath
                lastUpdate = now
            }
        }

        if let lastVisitedPath, lastVisitedPath != lastReportedPath {
            onFile(lastVisitedPath)
        }
    }

    private static func normalizedActivity(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        return String(normalized.prefix(180))
    }

}
