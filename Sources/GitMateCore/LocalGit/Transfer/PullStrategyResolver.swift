import Foundation

public enum PullStrategy: Equatable, Sendable {
    case fastForwardOnly
    case merge
    case rebase
}

public struct PullStrategyResolver: Sendable {
    private let executor: any GitCommandExecuting
    private let commandBuilder: GitCommandBuilder

    public init(
        executor: any GitCommandExecuting = ProcessGitCommandExecutor(),
        commandBuilder: GitCommandBuilder = GitCommandBuilder()
    ) {
        self.executor = executor
        self.commandBuilder = commandBuilder
    }

    public func resolve(
        repositoryURL: URL
    ) async throws -> PullStrategy {
        let pullFF = try await configuration(
            repositoryURL: repositoryURL,
            key: .pullFF
        )
        if pullFF?.lowercased() == "only" {
            return .fastForwardOnly
        }

        let pullRebase = try await configuration(
            repositoryURL: repositoryURL,
            key: .pullRebase
        )?.lowercased()
        switch pullRebase {
        case "true", "yes", "on", "1", "merges", "interactive":
            return .rebase
        case nil, "false", "no", "off", "0":
            return .merge
        default:
            throw GitCommandError.exitStatus(
                -1,
                "无法解析 pull.rebase 配置。"
            )
        }
    }

    private func configuration(
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
        } catch let GitCommandError.exitStatus(status, _)
            where status == 1 {
            return nil
        }
    }
}
