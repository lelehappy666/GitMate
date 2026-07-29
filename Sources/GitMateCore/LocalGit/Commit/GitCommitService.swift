import Foundation

public struct CommitMessage: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public struct CommitIdentity: Equatable, Sendable {
    public let name: String?
    public let email: String?

    public init(name: String?, email: String?) {
        self.name = name
        self.email = email
    }
}

public enum CommitSigningState: Equatable, Sendable {
    case disabled
    case configured(format: String?)
    case misconfigured(String)
}

public enum CommitSigningPolicy: Equatable, Sendable {
    case followGitConfiguration
}

public struct CommitResult: Equatable, Sendable {
    public let oid: String
    public let shortOID: String
    public let subject: String

    public init(oid: String, shortOID: String, subject: String) {
        self.oid = oid
        self.shortOID = shortOID
        self.subject = subject
    }
}

public enum GitConfigurationKey: String, Sendable {
    case userName = "user.name"
    case userEmail = "user.email"
    case commitGPGSign = "commit.gpgSign"
    case signingFormat = "gpg.format"
}

public protocol GitCommitServicing: Sendable {
    func identity(repositoryURL: URL) async throws -> CommitIdentity
    func signingState(
        repositoryURL: URL
    ) async throws -> CommitSigningState

    func commit(
        repositoryURL: URL,
        message: CommitMessage,
        signing: CommitSigningPolicy
    ) async throws -> CommitResult
}

public struct GitCommitService: GitCommitServicing, Sendable {
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

    public func identity(
        repositoryURL: URL
    ) async throws -> CommitIdentity {
        let name = try await configurationValue(
            repositoryURL: repositoryURL,
            key: .userName
        )
        let email = try await configurationValue(
            repositoryURL: repositoryURL,
            key: .userEmail
        )
        return CommitIdentity(name: name, email: email)
    }

    public func signingState(
        repositoryURL: URL
    ) async throws -> CommitSigningState {
        guard let value = try await configurationValue(
            repositoryURL: repositoryURL,
            key: .commitGPGSign
        ) else {
            return .disabled
        }
        switch value.lowercased() {
        case "false", "no", "off", "0":
            return .disabled
        case "true", "yes", "on", "1":
            let format = try await configurationValue(
                repositoryURL: repositoryURL,
                key: .signingFormat
            )
            return .configured(format: format)
        default:
            return .misconfigured("commit.gpgSign 的值无效。")
        }
    }

    public func commit(
        repositoryURL: URL,
        message: CommitMessage,
        signing: CommitSigningPolicy
    ) async throws -> CommitResult {
        let stagedCommand = try commandBuilder.stagedPaths(
            repositoryURL: repositoryURL
        )
        let stagedOutput = try await executor.collect(stagedCommand)
        guard !stagedOutput.stdoutData.isEmpty else {
            throw LocalGitError.emptyIndex
        }

        let signingState = try await signingState(
            repositoryURL: repositoryURL
        )
        if case let .misconfigured(reason) = signingState {
            throw LocalGitError.signingFailed(reason)
        }

        let commitCommand = try commandBuilder.commit(
            repositoryURL: repositoryURL,
            message: message
        )
        let executor = executor
        do {
            try await coordinator.run(
                repositoryURL: repositoryURL,
                kind: .commit
            ) {
                _ = try await executor.collect(commitCommand)
            }
        } catch let GitCommandError.exitStatus(_, message) {
            if case .configured = signingState {
                throw LocalGitError.signingFailed(message)
            }
            throw LocalGitError.hookFailed(message)
        }

        let resultCommand = try commandBuilder.latestCommit(
            repositoryURL: repositoryURL
        )
        let output = try await executor.collect(resultCommand)
        return try parseResult(output.stdoutData)
    }

    private func configurationValue(
        repositoryURL: URL,
        key: GitConfigurationKey
    ) async throws -> String? {
        let command = try commandBuilder.configurationValue(
            repositoryURL: repositoryURL,
            key: key
        )
        do {
            let output = try await executor.collect(command)
            let value = String(
                decoding: output.stdoutData,
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        } catch let GitCommandError.exitStatus(status, _) where status == 1 {
            return nil
        }
    }

    private func parseResult(_ data: Data) throws -> CommitResult {
        let fields = data.split(
            separator: 0,
            omittingEmptySubsequences: false
        )
        guard fields.count >= 3 else {
            throw GitCommandError.exitStatus(
                -1,
                "无法解析新提交信息。"
            )
        }
        return CommitResult(
            oid: String(decoding: fields[0], as: UTF8.self),
            shortOID: String(decoding: fields[1], as: UTF8.self),
            subject: String(decoding: fields[2], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
