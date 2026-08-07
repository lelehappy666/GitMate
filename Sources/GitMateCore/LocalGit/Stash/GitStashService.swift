import CryptoKit
import Foundation

public struct GitStashID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.range(
            of: #"^stash@\{\d+\}$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }
        self.rawValue = rawValue
    }
}

public struct GitStashEntry: Identifiable, Equatable, Sendable {
    public let id: GitStashID
    public let message: String
    public let baseBranch: String?
    public let createdAt: Date?
    public let fileCount: Int

    public init(
        id: GitStashID,
        message: String,
        baseBranch: String?,
        createdAt: Date?,
        fileCount: Int
    ) {
        self.id = id
        self.message = message
        self.baseBranch = baseBranch
        self.createdAt = createdAt
        self.fileCount = fileCount
    }
}

public enum StashApplyResult: Equatable, Sendable {
    case applied
    case conflicted
}

public protocol GitStashServicing: Sendable {
    func list(repositoryURL: URL) async throws -> [GitStashEntry]

    func create(
        repositoryURL: URL,
        message: String,
        includeUntracked: Bool
    ) async throws

    func diff(
        repositoryURL: URL,
        id: GitStashID
    ) async throws -> GitDiffDocument

    func apply(
        repositoryURL: URL,
        id: GitStashID
    ) async throws -> StashApplyResult

    func pop(
        repositoryURL: URL,
        id: GitStashID,
        confirmation: RiskConfirmation
    ) async throws -> StashApplyResult

    func drop(
        repositoryURL: URL,
        id: GitStashID,
        confirmation: RiskConfirmation
    ) async throws

    func popConfirmation(
        repositoryURL: URL,
        id: GitStashID
    ) -> RiskConfirmation

    func dropConfirmation(
        repositoryURL: URL,
        id: GitStashID
    ) -> RiskConfirmation
}

public struct GitStashService: GitStashServicing, Sendable {
    private let executor: any GitCommandExecuting
    private let coordinator: RepositoryOperationCoordinator
    private let commandBuilder: GitCommandBuilder

    public init(
        executor: any GitCommandExecuting = ProcessGitCommandExecutor(),
        coordinator: RepositoryOperationCoordinator =
            RepositoryOperationCoordinator(),
        commandBuilder: GitCommandBuilder = GitCommandBuilder()
    ) {
        self.executor = executor
        self.coordinator = coordinator
        self.commandBuilder = commandBuilder
    }

    public func list(
        repositoryURL: URL
    ) async throws -> [GitStashEntry] {
        let command = try commandBuilder.stashList(
            repositoryURL: repositoryURL
        )
        let output = try await executor.collect(command)
        var entries: [GitStashEntry] = []

        for record in output.stdoutData.split(separator: 0x0A) {
            let fields = record.split(
                separator: 0,
                omittingEmptySubsequences: false
            )
            guard fields.count >= 3,
                  let id = GitStashID(
                    rawValue: String(decoding: fields[0], as: UTF8.self)
                  )
            else {
                continue
            }
            let message = String(decoding: fields[1], as: UTF8.self)
            let createdAt = TimeInterval(
                String(decoding: fields[2], as: UTF8.self)
            ).map(Date.init(timeIntervalSince1970:))
            let paths = try await stashPaths(
                repositoryURL: repositoryURL,
                id: id
            )
            entries.append(
                GitStashEntry(
                    id: id,
                    message: message,
                    baseBranch: Self.baseBranch(from: message),
                    createdAt: createdAt,
                    fileCount: paths.count
                )
            )
        }
        return entries
    }

    public func create(
        repositoryURL: URL,
        message: String,
        includeUntracked: Bool
    ) async throws {
        let before = try await list(repositoryURL: repositoryURL).count
        let command = try commandBuilder.stashCreate(
            repositoryURL: repositoryURL,
            message: message,
            includeUntracked: includeUntracked
        )
        try await runWrite(
            repositoryURL: repositoryURL,
            command: command
        )
        let after = try await list(repositoryURL: repositoryURL).count
        guard after > before else {
            throw LocalGitError.workingTreeNotClean
        }
    }

    public func diff(
        repositoryURL: URL,
        id: GitStashID
    ) async throws -> GitDiffDocument {
        let paths = try await stashPaths(
            repositoryURL: repositoryURL,
            id: id
        )
        let command = try commandBuilder.stashDiff(
            repositoryURL: repositoryURL,
            id: id
        )
        let output = try await executor.collect(command)
        let firstPath = paths.first ?? id.rawValue
        let parsed = GitDiffParser.parse(
            path: firstPath,
            data: output.stdoutData
        )
        return GitDiffDocument(
            path: id.rawValue,
            files: paths.map {
                GitDiffFile(oldPath: nil, path: $0, isBinary: false)
            },
            hunks: parsed.hunks,
            byteCount: parsed.byteCount,
            lineCount: parsed.lineCount,
            addedLineCount: parsed.addedLineCount,
            deletedLineCount: parsed.deletedLineCount,
            loadingMode: parsed.loadingMode
        )
    }

    public func apply(
        repositoryURL: URL,
        id: GitStashID
    ) async throws -> StashApplyResult {
        try await apply(
            repositoryURL: repositoryURL,
            id: id,
            pop: false
        )
    }

    public func pop(
        repositoryURL: URL,
        id: GitStashID,
        confirmation: RiskConfirmation
    ) async throws -> StashApplyResult {
        try validate(
            confirmation,
            repositoryURL: repositoryURL,
            operation: "pop",
            id: id
        )
        return try await apply(
            repositoryURL: repositoryURL,
            id: id,
            pop: true
        )
    }

    public func drop(
        repositoryURL: URL,
        id: GitStashID,
        confirmation: RiskConfirmation
    ) async throws {
        try validate(
            confirmation,
            repositoryURL: repositoryURL,
            operation: "drop",
            id: id
        )
        let command = try commandBuilder.stashDrop(
            repositoryURL: repositoryURL,
            id: id
        )
        try await runWrite(
            repositoryURL: repositoryURL,
            command: command
        )
    }

    public func popConfirmation(
        repositoryURL: URL,
        id: GitStashID
    ) -> RiskConfirmation {
        confirmation(
            repositoryURL: repositoryURL,
            operation: "pop",
            id: id
        )
    }

    public func dropConfirmation(
        repositoryURL: URL,
        id: GitStashID
    ) -> RiskConfirmation {
        confirmation(
            repositoryURL: repositoryURL,
            operation: "drop",
            id: id
        )
    }

    private func apply(
        repositoryURL: URL,
        id: GitStashID,
        pop: Bool
    ) async throws -> StashApplyResult {
        let command = try commandBuilder.stashApply(
            repositoryURL: repositoryURL,
            id: id,
            pop: pop
        )
        do {
            try await runWrite(
                repositoryURL: repositoryURL,
                command: command
            )
            return .applied
        } catch GitCommandError.exitStatus {
            let conflicts = try await unmergedPaths(
                repositoryURL: repositoryURL
            )
            if !conflicts.isEmpty {
                return .conflicted
            }
            throw LocalGitError.stalePatch
        }
    }

    private func stashPaths(
        repositoryURL: URL,
        id: GitStashID
    ) async throws -> [String] {
        let command = try commandBuilder.stashPaths(
            repositoryURL: repositoryURL,
            id: id
        )
        let output = try await executor.collect(command)
        return output.stdoutData.split(separator: 0).map {
            String(decoding: $0, as: UTF8.self)
        }
    }

    private func unmergedPaths(
        repositoryURL: URL
    ) async throws -> [String] {
        let command = try commandBuilder.unmergedPaths(
            repositoryURL: repositoryURL
        )
        let output = try await executor.collect(command)
        return output.stdoutData.split(separator: 0).map {
            String(decoding: $0, as: UTF8.self)
        }
    }

    private func runWrite(
        repositoryURL: URL,
        command: GitCommand
    ) async throws {
        let executor = executor
        try await coordinator.run(
            repositoryURL: repositoryURL,
            kind: .stash
        ) {
            _ = try await executor.collect(command)
        }
    }

    private func confirmation(
        repositoryURL: URL,
        operation: String,
        id: GitStashID
    ) -> RiskConfirmation {
        RiskConfirmation(
            repositoryID: GitRepositoryIdentifier.make(
                repositoryURL: repositoryURL
            ),
            impactFingerprint: Self.fingerprint(
                operation: operation,
                id: id
            )
        )
    }

    private func validate(
        _ confirmation: RiskConfirmation,
        repositoryURL: URL,
        operation: String,
        id: GitStashID
    ) throws {
        let age = Date().timeIntervalSince(confirmation.createdAt)
        guard confirmation.repositoryID == GitRepositoryIdentifier.make(
            repositoryURL: repositoryURL
        ),
        confirmation.impactFingerprint == Self.fingerprint(
            operation: operation,
            id: id
        ),
        age >= 0,
        age <= 300
        else {
            throw LocalGitError.confirmationExpired
        }
    }

    private static func fingerprint(
        operation: String,
        id: GitStashID
    ) -> String {
        SHA256.hash(
            data: Data("\(operation)\0\(id.rawValue)".utf8)
        ).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static func baseBranch(from message: String) -> String? {
        for prefix in ["On ", "WIP on "] where message.hasPrefix(prefix) {
            let remainder = message.dropFirst(prefix.count)
            guard let colon = remainder.firstIndex(of: ":") else {
                return nil
            }
            return String(remainder[..<colon])
        }
        return nil
    }
}
