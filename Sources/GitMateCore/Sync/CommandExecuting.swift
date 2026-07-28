public enum CommandOutput: Equatable, Sendable {
    case standardOutput(String)
    case standardError(String)
}

public protocol CommandExecuting: Sendable {
    func execute(arguments: [String]) -> AsyncThrowingStream<CommandOutput, Error>
}

public enum CommandExecutionError: Error, Equatable, Sendable {
    case launchFailed(String)
    case exitStatus(Int32, String)
}
