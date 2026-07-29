import CryptoKit
import Foundation

public protocol GitDiffServicing: Sendable {
    func diff(
        repositoryURL: URL,
        path: String,
        source: GitDiffSource,
        options: GitDiffOptions
    ) async throws -> GitDiffDocument

    func stage(repositoryURL: URL, paths: [String]) async throws
    func unstage(repositoryURL: URL, paths: [String]) async throws
    func stageHunk(repositoryURL: URL, hunk: GitDiffHunk) async throws
    func unstageHunk(repositoryURL: URL, hunk: GitDiffHunk) async throws

    func discardHunk(
        repositoryURL: URL,
        hunk: GitDiffHunk,
        confirmation: RiskConfirmation
    ) async throws

    func discardFiles(
        repositoryURL: URL,
        paths: [String],
        confirmation: RiskConfirmation
    ) async throws
}

public struct GitDiffService: GitDiffServicing, Sendable {
    private let executor: any GitCommandExecuting
    private let coordinator: RepositoryOperationCoordinator
    private let commandBuilder: GitCommandBuilder

    public init(
        executor: any GitCommandExecuting,
        coordinator: RepositoryOperationCoordinator =
            RepositoryOperationCoordinator(),
        commandBuilder: GitCommandBuilder = GitCommandBuilder()
    ) {
        self.executor = executor
        self.coordinator = coordinator
        self.commandBuilder = commandBuilder
    }

    public func diff(
        repositoryURL: URL,
        path: String,
        source: GitDiffSource,
        options: GitDiffOptions = .default
    ) async throws -> GitDiffDocument {
        let command = try commandBuilder.diff(
            repositoryURL: repositoryURL,
            path: path,
            source: source,
            options: options
        )
        let output = try await executor.collect(command)
        return GitDiffParser.parse(path: path, data: output.stdoutData)
    }

    public func stage(
        repositoryURL: URL,
        paths: [String]
    ) async throws {
        let command = try commandBuilder.stagePaths(
            repositoryURL: repositoryURL,
            paths: paths
        )
        try await runWrite(
            repositoryURL: repositoryURL,
            kind: .stage,
            command: command
        )
    }

    public func unstage(
        repositoryURL: URL,
        paths: [String]
    ) async throws {
        let command = try commandBuilder.unstagePaths(
            repositoryURL: repositoryURL,
            paths: paths
        )
        try await runWrite(
            repositoryURL: repositoryURL,
            kind: .unstage,
            command: command
        )
    }

    public func stageHunk(
        repositoryURL: URL,
        hunk: GitDiffHunk
    ) async throws {
        let command = try commandBuilder.applyPatch(
            repositoryURL: repositoryURL,
            patch: hunk.patch,
            cached: true,
            reverse: false
        )
        try await runPatch(
            repositoryURL: repositoryURL,
            kind: .stage,
            command: command
        )
    }

    public func unstageHunk(
        repositoryURL: URL,
        hunk: GitDiffHunk
    ) async throws {
        let command = try commandBuilder.applyPatch(
            repositoryURL: repositoryURL,
            patch: hunk.patch,
            cached: true,
            reverse: true
        )
        try await runPatch(
            repositoryURL: repositoryURL,
            kind: .unstage,
            command: command
        )
    }

    public func discardHunkConfirmation(
        repositoryURL: URL,
        hunk: GitDiffHunk
    ) -> RiskConfirmation {
        makeConfirmation(
            repositoryURL: repositoryURL,
            fingerprint: hunkFingerprint(hunk)
        )
    }

    public func discardFilesConfirmation(
        repositoryURL: URL,
        paths: [String]
    ) -> RiskConfirmation {
        makeConfirmation(
            repositoryURL: repositoryURL,
            fingerprint: filesFingerprint(paths)
        )
    }

    public func discardHunk(
        repositoryURL: URL,
        hunk: GitDiffHunk,
        confirmation: RiskConfirmation
    ) async throws {
        try validate(
            confirmation,
            repositoryURL: repositoryURL,
            fingerprint: hunkFingerprint(hunk)
        )
        let command = try commandBuilder.applyPatch(
            repositoryURL: repositoryURL,
            patch: hunk.patch,
            cached: false,
            reverse: true
        )
        try await runPatch(
            repositoryURL: repositoryURL,
            kind: .stage,
            command: command
        )
    }

    public func discardFiles(
        repositoryURL: URL,
        paths: [String],
        confirmation: RiskConfirmation
    ) async throws {
        try validate(
            confirmation,
            repositoryURL: repositoryURL,
            fingerprint: filesFingerprint(paths)
        )
        let command = try commandBuilder.restoreWorkingTreePaths(
            repositoryURL: repositoryURL,
            paths: paths
        )
        try await runWrite(
            repositoryURL: repositoryURL,
            kind: .stage,
            command: command
        )
    }

    private func runWrite(
        repositoryURL: URL,
        kind: GitOperationKind,
        command: GitCommand
    ) async throws {
        let executor = executor
        try await coordinator.run(
            repositoryURL: repositoryURL,
            kind: kind
        ) {
            _ = try await executor.collect(command)
        }
    }

    private func runPatch(
        repositoryURL: URL,
        kind: GitOperationKind,
        command: GitCommand
    ) async throws {
        do {
            try await runWrite(
                repositoryURL: repositoryURL,
                kind: kind,
                command: command
            )
        } catch GitCommandError.exitStatus {
            throw LocalGitError.stalePatch
        }
    }

    private func makeConfirmation(
        repositoryURL: URL,
        fingerprint: String
    ) -> RiskConfirmation {
        RiskConfirmation(
            repositoryID: GitRepositoryIdentifier.make(
                repositoryURL: repositoryURL
            ),
            impactFingerprint: fingerprint
        )
    }

    private func validate(
        _ confirmation: RiskConfirmation,
        repositoryURL: URL,
        fingerprint: String
    ) throws {
        let repositoryID = GitRepositoryIdentifier.make(
            repositoryURL: repositoryURL
        )
        let age = Date().timeIntervalSince(confirmation.createdAt)
        guard confirmation.repositoryID == repositoryID,
              confirmation.impactFingerprint == fingerprint,
              age >= 0,
              age <= 300
        else {
            throw LocalGitError.confirmationExpired
        }
    }

    private func hunkFingerprint(_ hunk: GitDiffHunk) -> String {
        sha256(
            Data(hunk.id.utf8) + hunk.patch
        )
    }

    private func filesFingerprint(_ paths: [String]) -> String {
        sha256(Data(paths.sorted().joined(separator: "\0").utf8))
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
