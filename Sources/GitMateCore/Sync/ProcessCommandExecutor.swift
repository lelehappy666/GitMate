@preconcurrency import Foundation

public final class ProcessCommandExecutor: CommandExecuting, @unchecked Sendable {
    private let processLock = NSLock()
    private var activeProcess: ProcessBox?

    public init() {}

    public func pause() throws {
        let process = currentProcess()
        guard let process else {
            throw CommandControlError.noActiveProcess
        }
        try process.pause()
    }

    public func resume() throws {
        let process = currentProcess()
        guard let process else {
            throw CommandControlError.noActiveProcess
        }
        try process.resume()
    }

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
            self.setActiveProcess(box)
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
                self.clearActiveProcess(box)
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
                self.clearActiveProcess(box)
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
                self.clearActiveProcess(box)
            }
        }
    }

    private func currentProcess() -> ProcessBox? {
        processLock.lock()
        defer { processLock.unlock() }
        return activeProcess
    }

    private func setActiveProcess(_ process: ProcessBox) {
        processLock.lock()
        activeProcess = process
        processLock.unlock()
    }

    private func clearActiveProcess(_ process: ProcessBox) {
        processLock.lock()
        if activeProcess === process {
            activeProcess = nil
        }
        processLock.unlock()
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
    private var isPaused = false

    init(_ process: Process) {
        self.process = process
    }

    func pause() throws {
        lock.lock()
        defer { lock.unlock() }
        guard process.isRunning else {
            throw CommandControlError.noActiveProcess
        }
        guard !isPaused else { return }
        guard process.suspend() else {
            throw CommandControlError.operationFailed("无法暂停当前下载任务。")
        }
        isPaused = true
    }

    func resume() throws {
        lock.lock()
        defer { lock.unlock() }
        guard process.isRunning else {
            throw CommandControlError.noActiveProcess
        }
        guard isPaused else { return }
        guard process.resume() else {
            throw CommandControlError.operationFailed("无法继续当前下载任务。")
        }
        isPaused = false
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        if process.isRunning {
            if isPaused {
                _ = process.resume()
                isPaused = false
            }
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
