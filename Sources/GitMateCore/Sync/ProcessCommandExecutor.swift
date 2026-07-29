@preconcurrency import Foundation

public final class ProcessCommandExecutor: CommandExecuting, @unchecked Sendable {
    public init() {}

    public func execute(
        arguments: [String],
        environment: [String: String]
    ) -> AsyncThrowingStream<CommandOutput, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            let standardOutput = Pipe()
            let standardError = Pipe()
            let state = ProcessOutputState()
            let box = ProcessBox(process)
            let standardOutputReader = ProcessPipeReader()
            let standardErrorReader = ProcessPipeReader()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment
                .merging(environment) { _, newValue in newValue }
            process.standardOutput = standardOutput
            process.standardError = standardError

            standardOutput.fileHandleForReading.readabilityHandler = { handle in
                standardOutputReader.consumeAvailable(from: handle) { data in
                    state.consume(
                        data,
                        stream: .standardOutput,
                        continuation: continuation
                    )
                }
            }
            standardError.fileHandleForReading.readabilityHandler = { handle in
                standardErrorReader.consumeAvailable(from: handle) { data in
                    state.consume(
                        data,
                        stream: .standardError,
                        continuation: continuation
                    )
                }
            }

            process.terminationHandler = { process in
                standardOutput.fileHandleForReading.readabilityHandler = nil
                standardError.fileHandleForReading.readabilityHandler = nil
                standardOutputReader.drain(
                    from: standardOutput.fileHandleForReading
                ) { data in
                    state.consume(
                        data,
                        stream: .standardOutput,
                        continuation: continuation
                    )
                }
                standardErrorReader.drain(
                    from: standardError.fileHandleForReading
                ) { data in
                    state.consume(
                        data,
                        stream: .standardError,
                        continuation: continuation
                    )
                }

                if process.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(
                        throwing: CommandExecutionError.exitStatus(
                            process.terminationStatus,
                            state.standardErrorText
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                standardOutput.fileHandleForReading.readabilityHandler = nil
                standardError.fileHandleForReading.readabilityHandler = nil
                continuation.finish(
                    throwing: CommandExecutionError.launchFailed(
                        error.localizedDescription
                    )
                )
            }

            continuation.onTermination = { _ in
                box.terminate()
            }
        }
    }
}

final class ProcessPipeReader: @unchecked Sendable {
    private let lock = NSLock()

    func consumeAvailable(
        from handle: FileHandle,
        consume: (Data) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        let data = handle.availableData
        if !data.isEmpty {
            consume(data)
        }
    }

    func drain(
        from handle: FileHandle,
        consume: (Data) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        let data = handle.readDataToEndOfFile()
        if !data.isEmpty {
            consume(data)
        }
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()

    init(_ process: Process) {
        self.process = process
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        if process.isRunning {
            process.terminate()
        }
    }
}

private final class ProcessOutputState: @unchecked Sendable {
    private let lock = NSLock()
    private var errorData = Data()

    var standardErrorText: String {
        lock.lock()
        defer { lock.unlock() }
        return Self.redactedDiagnostic(
            String(decoding: errorData, as: UTF8.self)
        )
    }

    func consume(
        _ data: Data,
        stream: ProcessStream,
        continuation: AsyncThrowingStream<CommandOutput, Error>.Continuation
    ) {
        guard !data.isEmpty else { return }
        if stream == .standardError {
            lock.lock()
            errorData.append(data)
            lock.unlock()
        }
        continuation.yield(
            stream == .standardOutput
                ? .standardOutputData(data)
                : .standardErrorData(data)
        )
    }

    private static func redactedDiagnostic(_ value: String) -> String {
        let pattern = #"(https?://)[^/@\s]+@"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(
            in: value,
            range: range,
            withTemplate: "$1***@"
        )
    }
}

private enum ProcessStream {
    case standardOutput
    case standardError
}
