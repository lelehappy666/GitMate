import CryptoKit
import Foundation

public enum GitHistoryOperationRequest: Equatable, Sendable {
    case merge(source: String)
    case rebase(onto: String)
    case cherryPick(commits: [String])
}

public enum GitHistoryOperationResult: Equatable, Sendable {
    case completed
    case conflicted
}

public enum GitOperationBlocker: Equatable, Sendable {
    case workingTreeNotClean
    case anotherOperationInProgress
    case invalidSource
    case conflictPredictionUnknown
}

public enum GitRecoveryAction: Equatable, Sendable {
    case createStash
    case resolveCurrentOperation
    case refresh
}

public enum GitConflictPrediction: Equatable, Sendable {
    case none
    case likely(paths: [String])
    case unknown
}

public struct GitOperationPreflight: Equatable, Sendable {
    public let canStart: Bool
    public let blocker: GitOperationBlocker?
    public let availableRecovery: [GitRecoveryAction]
    public let affectedFiles: [String]
    public let commitCount: Int
    public let conflictPrediction: GitConflictPrediction
    public let confirmation: RiskConfirmation?

    public init(
        canStart: Bool,
        blocker: GitOperationBlocker?,
        availableRecovery: [GitRecoveryAction],
        affectedFiles: [String],
        commitCount: Int,
        conflictPrediction: GitConflictPrediction,
        confirmation: RiskConfirmation?
    ) {
        self.canStart = canStart
        self.blocker = blocker
        self.availableRecovery = availableRecovery
        self.affectedFiles = affectedFiles
        self.commitCount = commitCount
        self.conflictPrediction = conflictPrediction
        self.confirmation = confirmation
    }
}

public protocol GitHistoryOperationServicing: Sendable {
    func preflight(
        repositoryURL: URL,
        request: GitHistoryOperationRequest
    ) async throws -> GitOperationPreflight

    func start(
        repositoryURL: URL,
        request: GitHistoryOperationRequest,
        confirmation: RiskConfirmation
    ) async throws -> GitHistoryOperationResult

    func `continue`(
        repositoryURL: URL
    ) async throws -> GitHistoryOperationResult

    func abort(repositoryURL: URL) async throws

    func state(
        repositoryURL: URL
    ) async throws -> GitRepositoryOperationState
}

public struct GitHistoryOperationService:
    GitHistoryOperationServicing,
    Sendable
{
    private let executor: any GitCommandExecuting
    private let coordinator: RepositoryOperationCoordinator
    private let detector: GitOperationStateDetector
    private let journal: (any GitOperationJournalRecording)?
    private let commandBuilder: GitCommandBuilder

    public init(
        executor: any GitCommandExecuting = ProcessGitCommandExecutor(),
        coordinator: RepositoryOperationCoordinator =
            RepositoryOperationCoordinator(),
        detector: GitOperationStateDetector = GitOperationStateDetector(),
        journal: (any GitOperationJournalRecording)? = nil,
        commandBuilder: GitCommandBuilder = GitCommandBuilder()
    ) {
        self.executor = executor
        self.coordinator = coordinator
        self.detector = detector
        self.journal = journal
        self.commandBuilder = commandBuilder
    }

    public func preflight(
        repositoryURL: URL,
        request: GitHistoryOperationRequest
    ) async throws -> GitOperationPreflight {
        let activeState = try detector.detect(repositoryURL: repositoryURL)
        if activeState.kind != nil {
            return blocked(
                by: .anotherOperationInProgress,
                recovery: [.resolveCurrentOperation]
            )
        }

        do {
            try await verifySources(
                repositoryURL: repositoryURL,
                request: request
            )
        } catch LocalGitError.invalidReference {
            return blocked(by: .invalidSource, recovery: [.refresh])
        } catch GitCommandError.exitStatus {
            return blocked(by: .invalidSource, recovery: [.refresh])
        }

        let statusCommand = try commandBuilder.fullWorkingTreeStatus(
            repositoryURL: repositoryURL
        )
        let status = try await executor.collect(statusCommand)
        if !status.stdoutData.isEmpty {
            return blocked(
                by: .workingTreeNotClean,
                recovery: [.createStash, .refresh]
            )
        }

        let head = try await text(
            commandBuilder.headOID(repositoryURL: repositoryURL)
        )
        let impact = try await impact(
            repositoryURL: repositoryURL,
            request: request
        )
        let prediction = await conflictPrediction(
            repositoryURL: repositoryURL,
            request: request,
            affectedFiles: impact.files
        )
        let fingerprint = Self.fingerprint(
            request: request,
            head: head,
            affectedFiles: impact.files
        )
        let confirmation = RiskConfirmation(
            repositoryID: GitRepositoryIdentifier.make(
                repositoryURL: repositoryURL
            ),
            impactFingerprint: fingerprint
        )
        return GitOperationPreflight(
            canStart: true,
            blocker: nil,
            availableRecovery: [],
            affectedFiles: impact.files,
            commitCount: impact.commitCount,
            conflictPrediction: prediction,
            confirmation: confirmation
        )
    }

    public func start(
        repositoryURL: URL,
        request: GitHistoryOperationRequest,
        confirmation: RiskConfirmation
    ) async throws -> GitHistoryOperationResult {
        let latest = try await preflight(
            repositoryURL: repositoryURL,
            request: request
        )
        guard latest.canStart,
              let expected = latest.confirmation
        else {
            throw LocalGitError.workingTreeNotClean
        }
        try validate(confirmation, expected: expected)

        let command = try commandBuilder.startHistoryOperation(
            repositoryURL: repositoryURL,
            request: request
        )
        await record(
            repositoryURL: repositoryURL,
            phase: "开始\(Self.summary(request))",
            result: .running
        )
        do {
            try await runWrite(
                repositoryURL: repositoryURL,
                command: command
            )
            await record(
                repositoryURL: repositoryURL,
                phase: "完成\(Self.summary(request))",
                result: .succeeded
            )
            return .completed
        } catch GitCommandError.exitStatus {
            if try detector.detect(
                repositoryURL: repositoryURL
            ).kind != nil {
                await record(
                    repositoryURL: repositoryURL,
                    phase: "\(Self.summary(request))发生冲突",
                    result: .conflicted
                )
                return .conflicted
            }
            throw LocalGitError.stalePatch
        }
    }

    public func `continue`(
        repositoryURL: URL
    ) async throws -> GitHistoryOperationResult {
        let state = try detector.detect(repositoryURL: repositoryURL)
        guard let kind = state.kind else {
            throw LocalGitError.operationInProgress
        }
        guard state.canContinue else {
            return .conflicted
        }
        let command = try commandBuilder.continueHistoryOperation(
            repositoryURL: repositoryURL,
            kind: kind
        )
        do {
            try await runWrite(
                repositoryURL: repositoryURL,
                command: command
            )
            return .completed
        } catch GitCommandError.exitStatus {
            return try detector.detect(
                repositoryURL: repositoryURL
            ).kind == nil ? .completed : .conflicted
        }
    }

    public func abort(repositoryURL: URL) async throws {
        let state = try detector.detect(repositoryURL: repositoryURL)
        guard let kind = state.kind else {
            throw LocalGitError.operationInProgress
        }
        let command = try commandBuilder.abortHistoryOperation(
            repositoryURL: repositoryURL,
            kind: kind
        )
        try await runWrite(
            repositoryURL: repositoryURL,
            command: command
        )
    }

    public func state(
        repositoryURL: URL
    ) async throws -> GitRepositoryOperationState {
        try detector.detect(repositoryURL: repositoryURL)
    }

    private func verifySources(
        repositoryURL: URL,
        request: GitHistoryOperationRequest
    ) async throws {
        let references: [String]
        switch request {
        case let .merge(source):
            references = [source]
        case let .rebase(onto):
            references = [onto]
        case let .cherryPick(commits):
            guard !commits.isEmpty else {
                throw LocalGitError.invalidReference
            }
            references = commits
        }
        for reference in references {
            let command = try commandBuilder.verifyCommit(
                repositoryURL: repositoryURL,
                reference: reference
            )
            _ = try await executor.collect(command)
        }
    }

    private func impact(
        repositoryURL: URL,
        request: GitHistoryOperationRequest
    ) async throws -> (files: [String], commitCount: Int) {
        switch request {
        case let .merge(source):
            return try await rangeImpact(
                repositoryURL: repositoryURL,
                first: "HEAD",
                second: source,
                countRange: "HEAD..\(source)"
            )
        case let .rebase(onto):
            return try await rangeImpact(
                repositoryURL: repositoryURL,
                first: "HEAD",
                second: onto,
                countRange: "\(onto)..HEAD"
            )
        case let .cherryPick(commits):
            var paths = Set<String>()
            for commit in commits {
                let command = try commandBuilder.commitAffectedPaths(
                    repositoryURL: repositoryURL,
                    commit: commit
                )
                let output = try await executor.collect(command)
                paths.formUnion(Self.paths(from: output.stdoutData))
            }
            return (paths.sorted(), commits.count)
        }
    }

    private func rangeImpact(
        repositoryURL: URL,
        first: String,
        second: String,
        countRange: String
    ) async throws -> (files: [String], commitCount: Int) {
        let pathsCommand = try commandBuilder.historyAffectedPaths(
            repositoryURL: repositoryURL,
            first: first,
            second: second
        )
        let countCommand = try commandBuilder.historyCommitCount(
            repositoryURL: repositoryURL,
            range: countRange
        )
        async let pathsOutput = executor.collect(pathsCommand)
        async let countValue = text(countCommand)
        let paths = try await Self.paths(from: pathsOutput.stdoutData)
        let count = try await Int(countValue) ?? 0
        return (paths.sorted(), count)
    }

    private func conflictPrediction(
        repositoryURL: URL,
        request: GitHistoryOperationRequest,
        affectedFiles: [String]
    ) async -> GitConflictPrediction {
        guard case let .merge(source) = request else {
            return .unknown
        }
        do {
            let base = try await text(
                commandBuilder.mergeBase(
                    repositoryURL: repositoryURL,
                    first: "HEAD",
                    second: source
                )
            )
            let output = try await executor.collect(
                commandBuilder.mergeTree(
                    repositoryURL: repositoryURL,
                    base: base,
                    ours: "HEAD",
                    theirs: source
                )
            )
            let value = String(decoding: output.stdoutData, as: UTF8.self)
            if value.contains("changed in both")
                || value.contains("CONFLICT") {
                return .likely(paths: affectedFiles)
            }
            return .none
        } catch {
            return .unknown
        }
    }

    private func runWrite(
        repositoryURL: URL,
        command: GitCommand
    ) async throws {
        let executor = executor
        try await coordinator.run(
            repositoryURL: repositoryURL,
            kind: .historyRewrite
        ) {
            _ = try await executor.collect(command)
        }
    }

    private func text(_ command: GitCommand) async throws -> String {
        let output = try await executor.collect(command)
        return String(decoding: output.stdoutData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func blocked(
        by blocker: GitOperationBlocker,
        recovery: [GitRecoveryAction]
    ) -> GitOperationPreflight {
        GitOperationPreflight(
            canStart: false,
            blocker: blocker,
            availableRecovery: recovery,
            affectedFiles: [],
            commitCount: 0,
            conflictPrediction: .unknown,
            confirmation: nil
        )
    }

    private func validate(
        _ confirmation: RiskConfirmation,
        expected: RiskConfirmation
    ) throws {
        let age = Date().timeIntervalSince(confirmation.createdAt)
        guard confirmation.repositoryID == expected.repositoryID,
              confirmation.impactFingerprint
                == expected.impactFingerprint,
              age >= 0,
              age <= 300
        else {
            throw LocalGitError.confirmationExpired
        }
    }

    private func record(
        repositoryURL: URL,
        phase: String,
        result: GitOperationResult
    ) async {
        guard let journal else {
            return
        }
        try? await journal.record(
            GitOperationJournalEntry(
                repositoryID: GitRepositoryIdentifier.make(
                    repositoryURL: repositoryURL
                ),
                kind: .historyRewrite,
                startedAt: Date(),
                finishedAt: result == .running ? nil : Date(),
                phase: phase,
                result: result
            )
        )
    }

    private static func fingerprint(
        request: GitHistoryOperationRequest,
        head: String,
        affectedFiles: [String]
    ) -> String {
        let value = [
            summary(request),
            head,
            affectedFiles.sorted().joined(separator: "\0")
        ].joined(separator: "\0")
        return SHA256.hash(data: Data(value.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static func summary(
        _ request: GitHistoryOperationRequest
    ) -> String {
        switch request {
        case let .merge(source):
            return "合并:\(source)"
        case let .rebase(onto):
            return "变基:\(onto)"
        case let .cherryPick(commits):
            return "拣选:\(commits.joined(separator: ","))"
        }
    }

    private static func paths(from data: Data) -> [String] {
        data.split(separator: 0).map {
            String(decoding: $0, as: UTF8.self)
        }
    }
}
