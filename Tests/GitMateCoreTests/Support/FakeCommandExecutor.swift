import Foundation
import GitMateCore

final class FakeCommandExecutor: CommandExecuting, @unchecked Sendable {
    struct ExpectedInvocation: Equatable, Sendable {
        let arguments: [String]
        let environment: [String: String]
    }

    enum Result: Sendable {
        case success([CommandOutput])
        case failure(SyncFailure)
    }

    private let lock = NSLock()
    private var queuedResults: [Result]
    private var expectedInvocations: [ExpectedInvocation]
    private var contractFailures: [String] = []
    private let validatesInvocations: Bool
    private var recordedCommands: [[String]] = []
    private var recordedEnvironments: [[String: String]] = []

    init(results: [Result] = [.success([])]) {
        queuedResults = results
        expectedInvocations = []
        validatesInvocations = false
    }

    init(
        results: [Result],
        expectedInvocations: [ExpectedInvocation]
    ) {
        queuedResults = results
        self.expectedInvocations = expectedInvocations
        validatesInvocations = true
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

    func execute(
        arguments: [String],
        environment: [String: String]
    ) -> AsyncThrowingStream<CommandOutput, Error> {
        lock.lock()
        recordedCommands.append(arguments)
        recordedEnvironments.append(environment)
        let actual = ExpectedInvocation(
            arguments: arguments,
            environment: environment
        )
        var contractError: FakeCommandContractError?
        let result: Result?
        if !validatesInvocations {
            contractError = nil
            result = queuedResults.count > 1
                ? queuedResults.removeFirst()
                : queuedResults.first
        } else if expectedInvocations.isEmpty {
            contractError = FakeCommandContractError(
                description: "收到未预期的额外命令：\(arguments)"
            )
            result = nil
            contractFailures.append(contractError!.description)
        } else if expectedInvocations[0] != actual {
            contractError = FakeCommandContractError(
                description:
                    "命令调用不匹配，实际：\(arguments)，预期：\(expectedInvocations[0])"
            )
            result = nil
            contractFailures.append(contractError!.description)
        } else {
            expectedInvocations.removeFirst()
            if queuedResults.isEmpty {
                contractError = FakeCommandContractError(
                    description: "命令没有对应的预置结果：\(arguments)"
                )
                result = nil
                contractFailures.append(contractError!.description)
            } else {
                contractError = nil
                result = queuedResults.removeFirst()
            }
        }
        lock.unlock()

        return AsyncThrowingStream(
            CommandOutput.self,
            bufferingPolicy: .unbounded
        ) { continuation in
            if let contractError {
                continuation.finish(throwing: contractError)
                return
            }
            guard let result else {
                continuation.finish(
                    throwing: FakeCommandContractError(
                        description: "命令没有对应的预置结果：\(arguments)"
                    )
                )
                return
            }
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

    func verifyComplete() throws {
        lock.lock()
        defer { lock.unlock() }
        guard validatesInvocations else { return }
        guard contractFailures.isEmpty else {
            throw FakeCommandContractError(
                description: "历史命令契约失败：\(contractFailures)"
            )
        }
        guard expectedInvocations.isEmpty else {
            throw FakeCommandContractError(
                description: "仍有未执行的预期命令：\(expectedInvocations)"
            )
        }
        guard queuedResults.isEmpty else {
            throw FakeCommandContractError(
                description: "仍有未消费的预置结果：\(queuedResults.count)"
            )
        }
    }
}

private struct FakeCommandContractError: Error, CustomStringConvertible, Sendable {
    let description: String
}
