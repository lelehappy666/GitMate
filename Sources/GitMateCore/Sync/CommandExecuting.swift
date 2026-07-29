import Foundation

public enum CommandOutput: Equatable, Sendable {
    case standardOutput(String)
    case standardError(String)
}

public protocol CommandExecuting: Sendable {
    func execute(
        arguments: [String],
        environment: [String: String]
    ) -> AsyncThrowingStream<CommandOutput, Error>

    func pause() throws
    func resume() throws
}

public extension CommandExecuting {
    func pause() throws {
        throw CommandControlError.noActiveProcess
    }

    func resume() throws {
        throw CommandControlError.noActiveProcess
    }
}

public enum CommandExecutionError: Error, Equatable, Sendable {
    case launchFailed(String)
    case exitStatus(Int32, String)
}

public enum CommandControlError: Error, LocalizedError, Sendable {
    case noActiveProcess
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noActiveProcess:
            "当前没有可控制的下载任务。"
        case let .operationFailed(message):
            message
        }
    }
}
