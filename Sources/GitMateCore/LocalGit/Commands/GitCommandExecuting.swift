import Foundation

public protocol GitCommandExecuting: Sendable {
    func execute(
        _ command: GitCommand
    ) -> AsyncThrowingStream<GitCommandChunk, Error>
}

public struct GitCollectedOutput: Equatable, Sendable {
    public let stdoutData: Data
    public let stderrLines: [String]

    public init(stdoutData: Data, stderrLines: [String]) {
        self.stdoutData = stdoutData
        self.stderrLines = stderrLines
    }
}

public extension GitCommandExecuting {
    func collect(_ command: GitCommand) async throws -> GitCollectedOutput {
        var stdoutData = Data()
        var stderrLines: [String] = []

        for try await chunk in execute(command) {
            switch chunk {
            case let .standardOutput(data):
                stdoutData.append(data)
            case let .standardError(line):
                stderrLines.append(line)
            }
        }

        return GitCollectedOutput(
            stdoutData: stdoutData,
            stderrLines: stderrLines
        )
    }
}
