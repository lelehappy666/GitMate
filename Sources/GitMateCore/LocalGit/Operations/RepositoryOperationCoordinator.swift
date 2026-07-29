import Foundation

public actor RepositoryOperationCoordinator {
    private var activeOperations: [URL: GitOperationKind] = [:]

    public init() {}

    public func run<T: Sendable>(
        repositoryURL: URL,
        kind: GitOperationKind,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        if try repositoryHasIndexLock(repository) {
            throw LocalGitError.repositoryLocked
        }
        guard activeOperations[repository] == nil else {
            throw LocalGitError.repositoryBusy
        }

        activeOperations[repository] = kind
        defer {
            activeOperations.removeValue(forKey: repository)
        }
        return try await operation()
    }

    private func repositoryHasIndexLock(_ repositoryURL: URL) throws -> Bool {
        let gitMetadataURL = repositoryURL.appending(path: ".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: gitMetadataURL.path,
            isDirectory: &isDirectory
        ) else {
            throw LocalGitError.notGitRepository
        }

        let gitDirectory: URL
        if isDirectory.boolValue {
            gitDirectory = gitMetadataURL
        } else {
            let content = try String(contentsOf: gitMetadataURL, encoding: .utf8)
            let prefix = "gitdir:"
            guard content.lowercased().hasPrefix(prefix) else {
                throw LocalGitError.notGitRepository
            }
            let rawPath = content
                .dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if NSString(string: rawPath).isAbsolutePath {
                gitDirectory = URL(fileURLWithPath: rawPath)
            } else {
                gitDirectory = repositoryURL
                    .appending(path: rawPath)
                    .standardizedFileURL
            }
        }

        return FileManager.default.fileExists(
            atPath: gitDirectory.appending(path: "index.lock").path
        )
    }
}
