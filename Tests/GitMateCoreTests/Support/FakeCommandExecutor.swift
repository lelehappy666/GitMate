import Foundation
import GitMateCore

final class FakeCommandExecutor: CommandExecuting, @unchecked Sendable {
    enum Result: Sendable {
        case success([CommandOutput])
        case failure(SyncFailure)
    }

    private let lock = NSLock()
    private var queuedResults: [Result]
    private var recordedCommands: [[String]] = []
    private var recordedEnvironments: [[String: String]] = []
    private var paused = false

    init(results: [Result] = [.success([])]) {
        queuedResults = results
    }

    var commands: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCommands
    }

    var environments: [[String: String]] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEnvironments
    }

    var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return paused
    }

    func pause() throws {
        lock.lock()
        paused = true
        lock.unlock()
    }

    func resume() throws {
        lock.lock()
        paused = false
        lock.unlock()
    }

    func execute(
        arguments: [String],
        environment: [String: String]
    ) -> AsyncThrowingStream<CommandOutput, Error> {
        lock.lock()
        recordedCommands.append(arguments)
        recordedEnvironments.append(environment)
        let result = queuedResults.count > 1
            ? queuedResults.removeFirst()
            : queuedResults[0]
        lock.unlock()

        return AsyncThrowingStream(
            CommandOutput.self,
            bufferingPolicy: .unbounded
        ) { continuation in
            switch result {
            case let .success(outputs):
                for output in outputs {
                    continuation.yield(output)
                }
                continuation.finish()
            case let .failure(error):
                continuation.finish(throwing: error)
            }
        }
    }
}
