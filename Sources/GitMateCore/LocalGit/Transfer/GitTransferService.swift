import CryptoKit
import Foundation

public enum PushMode: Equatable, Sendable {
    case normal
    case forceWithLease
}

public enum GitTransferOperation: Equatable, Sendable {
    case fetch
    case pull
    case push
}

public struct GitTransferPlan: Equatable, Sendable {
    public let operation: GitTransferOperation
    public let remote: String
    public let branch: String?
    public let pullStrategy: PullStrategy?
    public let pushMode: PushMode?
    public let expectedRemoteOID: String?
    public let ahead: Int?
    public let behind: Int?
    public let estimatedBytes: Int64?
    public let confirmation: RiskConfirmation?

    public init(
        operation: GitTransferOperation,
        remote: String,
        branch: String?,
        pullStrategy: PullStrategy?,
        pushMode: PushMode?,
        expectedRemoteOID: String?,
        ahead: Int?,
        behind: Int?,
        estimatedBytes: Int64?,
        confirmation: RiskConfirmation?
    ) {
        self.operation = operation
        self.remote = remote
        self.branch = branch
        self.pullStrategy = pullStrategy
        self.pushMode = pushMode
        self.expectedRemoteOID = expectedRemoteOID
        self.ahead = ahead
        self.behind = behind
        self.estimatedBytes = estimatedBytes
        self.confirmation = confirmation
    }

    public static func forcePush(
        remote: String,
        branch: String,
        expectedRemoteOID: String
    ) -> GitTransferPlan {
        GitTransferPlan(
            operation: .push,
            remote: remote,
            branch: branch,
            pullStrategy: nil,
            pushMode: .forceWithLease,
            expectedRemoteOID: expectedRemoteOID,
            ahead: nil,
            behind: nil,
            estimatedBytes: nil,
            confirmation: nil
        )
    }
}

public enum GitBranchProtectionStatus: Equatable, Sendable {
    case protected(summary: String)
    case unprotected
    case unverified
}

public protocol GitBranchProtectionChecking: Sendable {
    func status(
        remote: GitRemote,
        branch: String
    ) async -> GitBranchProtectionStatus
}

public protocol GitTransferServicing: Sendable {
    func planFetch(
        repositoryURL: URL,
        remote: String
    ) async throws -> GitTransferPlan

    func fetch(
        repositoryURL: URL,
        remote: String,
        context: GitCredentialContext
    ) -> AsyncThrowingStream<GitTransferEvent, Error>

    func planPull(
        repositoryURL: URL,
        remote: String,
        branch: String
    ) async throws -> GitTransferPlan

    func pull(
        repositoryURL: URL,
        plan: GitTransferPlan,
        context: GitCredentialContext,
        confirmation: RiskConfirmation
    ) -> AsyncThrowingStream<GitTransferEvent, Error>

    func planPush(
        repositoryURL: URL,
        remote: String,
        branch: String,
        mode: PushMode
    ) async throws -> GitTransferPlan

    func push(
        repositoryURL: URL,
        plan: GitTransferPlan,
        context: GitCredentialContext,
        confirmation: RiskConfirmation
    ) -> AsyncThrowingStream<GitTransferEvent, Error>
}

public struct GitTransferService: GitTransferServicing, Sendable {
    private let executor: any GitCommandExecuting
    private let coordinator: RepositoryOperationCoordinator
    private let transportPolicy: GitRemoteTransportPolicy
    private let credentialEnvironment: GitCredentialEnvironment
    private let strategyResolver: PullStrategyResolver
    private let stateDetector: GitOperationStateDetector
    private let commandBuilder: GitCommandBuilder

    public init(
        executor: any GitCommandExecuting = ProcessGitCommandExecutor(),
        coordinator: RepositoryOperationCoordinator =
            RepositoryOperationCoordinator(),
        transportPolicy: GitRemoteTransportPolicy = .production,
        credentialEnvironment: GitCredentialEnvironment? = nil,
        strategyResolver: PullStrategyResolver? = nil,
        stateDetector: GitOperationStateDetector = GitOperationStateDetector(),
        commandBuilder: GitCommandBuilder = GitCommandBuilder()
    ) {
        self.executor = executor
        self.coordinator = coordinator
        self.transportPolicy = transportPolicy
        self.credentialEnvironment = credentialEnvironment
            ?? GitCredentialEnvironment(
                credentialStore: InMemoryCredentialStore(),
                transportPolicy: transportPolicy
            )
        self.strategyResolver = strategyResolver
            ?? PullStrategyResolver(executor: executor)
        self.stateDetector = stateDetector
        self.commandBuilder = commandBuilder
    }

    public func planFetch(
        repositoryURL: URL,
        remote: String
    ) async throws -> GitTransferPlan {
        _ = try await remoteEnvironmentSource(
            repositoryURL: repositoryURL,
            remote: remote
        )
        return GitTransferPlan(
            operation: .fetch,
            remote: remote,
            branch: nil,
            pullStrategy: nil,
            pushMode: nil,
            expectedRemoteOID: nil,
            ahead: nil,
            behind: nil,
            estimatedBytes: nil,
            confirmation: nil
        )
    }

    public func fetch(
        repositoryURL: URL,
        remote: String,
        context: GitCredentialContext
    ) -> AsyncThrowingStream<GitTransferEvent, Error> {
        AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    let environment = try await environment(
                        repositoryURL: repositoryURL,
                        remote: remote,
                        context: context
                    )
                    let command = try commandBuilder.fetch(
                        repositoryURL: repositoryURL,
                        remote: remote,
                        environment: environment
                    )
                    continuation.yield(
                        GitTransferEvent(phase: .connecting)
                    )
                    try await stream(
                        repositoryURL: repositoryURL,
                        kind: .fetch,
                        command: command,
                        continuation: continuation
                    )
                    continuation.yield(
                        GitTransferEvent(phase: .completed)
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(
                        throwing: Self.mapped(error)
                    )
                }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    public func planPull(
        repositoryURL: URL,
        remote: String,
        branch: String
    ) async throws -> GitTransferPlan {
        let counts = try await aheadBehind(
            repositoryURL: repositoryURL,
            remote: remote,
            branch: branch
        )
        let strategy = try await strategyResolver.resolve(
            repositoryURL: repositoryURL
        )
        return makeConfirmedPlan(
            repositoryURL: repositoryURL,
            operation: .pull,
            remote: remote,
            branch: branch,
            pullStrategy: strategy,
            pushMode: nil,
            expectedRemoteOID: nil,
            ahead: counts.ahead,
            behind: counts.behind
        )
    }

    public func pull(
        repositoryURL: URL,
        plan: GitTransferPlan,
        context: GitCredentialContext,
        confirmation: RiskConfirmation
    ) -> AsyncThrowingStream<GitTransferEvent, Error> {
        AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    try validate(
                        confirmation,
                        plan: plan,
                        repositoryURL: repositoryURL
                    )
                    let environment = try await environment(
                        repositoryURL: repositoryURL,
                        remote: plan.remote,
                        context: context
                    )
                    let fetchCommand = try commandBuilder.fetch(
                        repositoryURL: repositoryURL,
                        remote: plan.remote,
                        environment: environment
                    )
                    continuation.yield(
                        GitTransferEvent(phase: .connecting)
                    )
                    try await stream(
                        repositoryURL: repositoryURL,
                        kind: .fetch,
                        command: fetchCommand,
                        continuation: continuation
                    )
                    try Task.checkCancellation()
                    continuation.yield(
                        GitTransferEvent(phase: .integrating)
                    )
                    let integrateCommand = try commandBuilder.integratePull(
                        repositoryURL: repositoryURL,
                        plan: plan
                    )
                    do {
                        try await runCollected(
                            repositoryURL: repositoryURL,
                            kind: .pull,
                            command: integrateCommand
                        )
                        continuation.yield(
                            GitTransferEvent(phase: .completed)
                        )
                    } catch GitCommandError.exitStatus {
                        if try stateDetector.detect(
                            repositoryURL: repositoryURL
                        ).kind != nil {
                            continuation.yield(
                                GitTransferEvent(phase: .conflicted)
                            )
                        } else {
                            throw LocalGitError.nonFastForward
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(
                        throwing: Self.mapped(error)
                    )
                }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    public func planPush(
        repositoryURL: URL,
        remote: String,
        branch: String,
        mode: PushMode
    ) async throws -> GitTransferPlan {
        let counts = try await aheadBehind(
            repositoryURL: repositoryURL,
            remote: remote,
            branch: branch
        )
        if mode == .normal, counts.behind > 0 {
            throw LocalGitError.nonFastForward
        }
        let expectedOID: String?
        if mode == .forceWithLease {
            expectedOID = try await text(
                commandBuilder.remoteTrackingOID(
                    repositoryURL: repositoryURL,
                    remote: remote,
                    branch: branch
                )
            )
        } else {
            expectedOID = nil
        }
        return makeConfirmedPlan(
            repositoryURL: repositoryURL,
            operation: .push,
            remote: remote,
            branch: branch,
            pullStrategy: nil,
            pushMode: mode,
            expectedRemoteOID: expectedOID,
            ahead: counts.ahead,
            behind: counts.behind
        )
    }

    public func push(
        repositoryURL: URL,
        plan: GitTransferPlan,
        context: GitCredentialContext,
        confirmation: RiskConfirmation
    ) -> AsyncThrowingStream<GitTransferEvent, Error> {
        AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    try validate(
                        confirmation,
                        plan: plan,
                        repositoryURL: repositoryURL
                    )
                    let environment = try await environment(
                        repositoryURL: repositoryURL,
                        remote: plan.remote,
                        context: context
                    )
                    let command = try commandBuilder.push(
                        repositoryURL: repositoryURL,
                        plan: plan,
                        environment: environment
                    )
                    continuation.yield(
                        GitTransferEvent(phase: .connecting)
                    )
                    try await stream(
                        repositoryURL: repositoryURL,
                        kind: .push,
                        command: command,
                        continuation: continuation
                    )
                    continuation.yield(
                        GitTransferEvent(phase: .completed)
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(
                        throwing: Self.mapped(error)
                    )
                }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    private func stream(
        repositoryURL: URL,
        kind: GitOperationKind,
        command: GitCommand,
        continuation: AsyncThrowingStream<
            GitTransferEvent,
            Error
        >.Continuation
    ) async throws {
        let executor = executor
        try await coordinator.run(
            repositoryURL: repositoryURL,
            kind: kind
        ) {
            let parser = GitTransferProgressParser()
            for try await chunk in executor.execute(command) {
                try Task.checkCancellation()
                if case let .standardError(line) = chunk {
                    continuation.yield(parser.parse(line: line))
                }
            }
        }
    }

    private func runCollected(
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

    private func environment(
        repositoryURL: URL,
        remote: String,
        context: GitCredentialContext
    ) async throws -> [String: String] {
        let source = try await remoteEnvironmentSource(
            repositoryURL: repositoryURL,
            remote: remote
        )
        return try credentialEnvironment.environment(
            remoteURLString: source,
            context: context
        )
    }

    private func remoteEnvironmentSource(
        repositoryURL: URL,
        remote: String
    ) async throws -> String {
        let command = try commandBuilder.remoteURL(
            repositoryURL: repositoryURL,
            name: remote,
            push: false
        )
        let source = try await text(command)
        _ = try transportPolicy.validate(remoteURLString: source)
        return source
    }

    private func aheadBehind(
        repositoryURL: URL,
        remote: String,
        branch: String
    ) async throws -> (ahead: Int, behind: Int) {
        let command = try commandBuilder.aheadBehind(
            repositoryURL: repositoryURL,
            remote: remote,
            branch: branch
        )
        let value = try await text(command)
        let fields = value.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2,
              let behind = Int(fields[0]),
              let ahead = Int(fields[1])
        else {
            throw GitCommandError.exitStatus(
                -1,
                "无法解析领先落后状态。"
            )
        }
        return (ahead, behind)
    }

    private func text(_ command: GitCommand) async throws -> String {
        let output = try await executor.collect(command)
        return String(decoding: output.stdoutData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeConfirmedPlan(
        repositoryURL: URL,
        operation: GitTransferOperation,
        remote: String,
        branch: String,
        pullStrategy: PullStrategy?,
        pushMode: PushMode?,
        expectedRemoteOID: String?,
        ahead: Int,
        behind: Int
    ) -> GitTransferPlan {
        let draft = GitTransferPlan(
            operation: operation,
            remote: remote,
            branch: branch,
            pullStrategy: pullStrategy,
            pushMode: pushMode,
            expectedRemoteOID: expectedRemoteOID,
            ahead: ahead,
            behind: behind,
            estimatedBytes: nil,
            confirmation: nil
        )
        let confirmation = RiskConfirmation(
            repositoryID: GitRepositoryIdentifier.make(
                repositoryURL: repositoryURL
            ),
            impactFingerprint: Self.fingerprint(draft)
        )
        return GitTransferPlan(
            operation: operation,
            remote: remote,
            branch: branch,
            pullStrategy: pullStrategy,
            pushMode: pushMode,
            expectedRemoteOID: expectedRemoteOID,
            ahead: ahead,
            behind: behind,
            estimatedBytes: nil,
            confirmation: confirmation
        )
    }

    private func validate(
        _ confirmation: RiskConfirmation,
        plan: GitTransferPlan,
        repositoryURL: URL
    ) throws {
        let age = Date().timeIntervalSince(confirmation.createdAt)
        guard confirmation.repositoryID == GitRepositoryIdentifier.make(
            repositoryURL: repositoryURL
        ),
        confirmation.impactFingerprint == Self.fingerprint(plan),
        age >= 0,
        age <= 300
        else {
            throw LocalGitError.confirmationExpired
        }
    }

    private static func fingerprint(_ plan: GitTransferPlan) -> String {
        let value = [
            String(describing: plan.operation),
            plan.remote,
            plan.branch ?? "",
            String(describing: plan.pullStrategy),
            String(describing: plan.pushMode),
            plan.expectedRemoteOID ?? "",
            String(plan.ahead ?? -1),
            String(plan.behind ?? -1)
        ].joined(separator: "\0")
        return SHA256.hash(data: Data(value.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static func mapped(_ error: Error) -> Error {
        if error is CancellationError
            || error as? GitCommandError == .cancelled {
            return GitCommandError.cancelled
        }
        guard case let GitCommandError.exitStatus(_, message) = error else {
            return error
        }
        let value = message.lowercased()
        if value.contains("could not resolve host")
            || value.contains("network is unreachable")
            || value.contains("connection refused") {
            return LocalGitError.networkUnavailable
        }
        if value.contains("timed out")
            || value.contains("timeout") {
            return LocalGitError.networkTimedOut
        }
        if value.contains("non-fast-forward")
            || value.contains("fetch first")
            || value.contains("stale info") {
            return LocalGitError.nonFastForward
        }
        return LocalGitError.remoteRejected(
            GitOutputRedactor.redact(message)
        )
    }
}
