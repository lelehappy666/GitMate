import Foundation

public struct GitCommand: Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let standardInput: Data?
    public let cancellation: GitCancellationPolicy

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        arguments: [String],
        environment: [String: String] = [:],
        standardInput: Data? = nil,
        cancellation: GitCancellationPolicy = .terminateProcess
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.standardInput = standardInput
        self.cancellation = cancellation
    }
}

public enum GitCancellationPolicy: Sendable {
    case terminateProcess
    case finishToSafeState
}

public enum GitCommandChunk: Equatable, Sendable {
    case standardOutput(Data)
    case standardError(String)
}

public enum GitCommandError: Error, Equatable, Sendable {
    case launchFailed(String)
    case exitStatus(Int32, String)
    case cancelled
}
