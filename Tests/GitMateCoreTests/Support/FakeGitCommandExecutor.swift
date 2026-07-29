import Foundation
import GitMateCore

final class FakeGitCommandExecutor: GitCommandExecuting, @unchecked Sendable {
    enum Outcome {
        case chunks([GitCommandChunk])
        case failure(GitCommandError)
    }

    private let lock = NSLock()
    private var outcomes: [Outcome]
    private var recordedCommands: [GitCommand] = []

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    var commands: [GitCommand] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCommands
    }

    func execute(
        _ command: GitCommand
    ) -> AsyncThrowingStream<GitCommandChunk, Error> {
        lock.lock()
        recordedCommands.append(command)
        let outcome = outcomes.isEmpty
            ? .chunks([])
            : outcomes.removeFirst()
        lock.unlock()

        return AsyncThrowingStream { continuation in
            switch outcome {
            case let .chunks(chunks):
                for chunk in chunks {
                    continuation.yield(chunk)
                }
                continuation.finish()
            case let .failure(error):
                continuation.finish(throwing: error)
            }
        }
    }
}
