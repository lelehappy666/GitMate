import Foundation

public enum GitRepositoryOperationKind: Equatable, Sendable {
    case merge
    case rebase
    case cherryPick
}

public struct GitRepositoryOperationState: Equatable, Sendable {
    public let kind: GitRepositoryOperationKind?
    public let canContinue: Bool

    public init(
        kind: GitRepositoryOperationKind?,
        canContinue: Bool
    ) {
        self.kind = kind
        self.canContinue = canContinue
    }

    public static let none = GitRepositoryOperationState(
        kind: nil,
        canContinue: false
    )
}

public struct GitOperationStateDetector: Sendable {
    public init() {}

    public func detect(
        repositoryURL: URL
    ) throws -> GitRepositoryOperationState {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        let gitDirectory = try resolveGitDirectory(repository)
        let fileManager = FileManager.default
        let kind: GitRepositoryOperationKind?

        if fileManager.fileExists(
            atPath: gitDirectory.appending(path: "MERGE_HEAD").path
        ) {
            kind = .merge
        } else if fileManager.fileExists(
            atPath: gitDirectory.appending(path: "CHERRY_PICK_HEAD").path
        ) {
            kind = .cherryPick
        } else if fileManager.fileExists(
            atPath: gitDirectory.appending(path: "rebase-merge").path
        ) || fileManager.fileExists(
            atPath: gitDirectory.appending(path: "rebase-apply").path
        ) {
            kind = .rebase
        } else {
            return .none
        }

        return GitRepositoryOperationState(
            kind: kind,
            canContinue: try !hasUnmergedEntries(repository)
        )
    }

    private func resolveGitDirectory(_ repositoryURL: URL) throws -> URL {
        let metadataURL = repositoryURL.appending(path: ".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: metadataURL.path,
            isDirectory: &isDirectory
        ) else {
            throw LocalGitError.notGitRepository
        }
        if isDirectory.boolValue {
            return metadataURL
        }

        let content = try String(contentsOf: metadataURL, encoding: .utf8)
        guard content.lowercased().hasPrefix("gitdir:") else {
            throw LocalGitError.notGitRepository
        }
        let rawPath = content
            .dropFirst("gitdir:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if NSString(string: rawPath).isAbsolutePath {
            return URL(fileURLWithPath: rawPath)
        }
        return repositoryURL
            .appending(path: rawPath)
            .standardizedFileURL
    }

    private func hasUnmergedEntries(_ repositoryURL: URL) throws -> Bool {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "-C",
            repositoryURL.path,
            "diff",
            "--name-only",
            "--diff-filter=U",
            "-z"
        ]
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                decoding: error.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            throw GitCommandError.exitStatus(
                process.terminationStatus,
                GitOutputRedactor.redact(message)
            )
        }
        return !output.fileHandleForReading.readDataToEndOfFile().isEmpty
    }
}
