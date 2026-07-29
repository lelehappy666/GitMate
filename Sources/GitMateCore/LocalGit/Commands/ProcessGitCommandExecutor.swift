@preconcurrency import Foundation

public final class ProcessGitCommandExecutor: GitCommandExecuting,
    @unchecked Sendable
{
    public init() {}

    public func execute(
        _ command: GitCommand
    ) -> AsyncThrowingStream<GitCommandChunk, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            let standardOutput = Pipe()
            let standardError = Pipe()
            let standardInput = command.standardInput.map { _ in Pipe() }
            let state = GitProcessOutputState()
            let processBox = GitProcessBox(
                process: process,
                cancellation: command.cancellation
            )

            process.executableURL = command.executableURL
            process.arguments = command.arguments
            process.environment = ProcessInfo.processInfo.environment
                .merging(command.environment) { _, provided in provided }
            process.standardOutput = standardOutput
            process.standardError = standardError
            process.standardInput = standardInput

            standardOutput.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    return
                }
                continuation.yield(.standardOutput(data))
            }
            standardError.fileHandleForReading.readabilityHandler = { handle in
                state.consumeError(
                    handle.availableData,
                    continuation: continuation
                )
            }

            process.terminationHandler = { process in
                standardOutput.fileHandleForReading.readabilityHandler = nil
                standardError.fileHandleForReading.readabilityHandler = nil

                let remainingOutput = standardOutput.fileHandleForReading
                    .readDataToEndOfFile()
                if !remainingOutput.isEmpty {
                    continuation.yield(.standardOutput(remainingOutput))
                }
                state.consumeError(
                    standardError.fileHandleForReading.readDataToEndOfFile(),
                    continuation: continuation
                )
                state.finishErrors(continuation: continuation)

                if process.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(
                        throwing: GitCommandError.exitStatus(
                            process.terminationStatus,
                            state.errorText
                        )
                    )
                }
            }

            do {
                try process.run()
                if let data = command.standardInput,
                   let standardInput {
                    try standardInput.fileHandleForWriting.write(
                        contentsOf: data
                    )
                    try standardInput.fileHandleForWriting.close()
                }
            } catch {
                standardOutput.fileHandleForReading.readabilityHandler = nil
                standardError.fileHandleForReading.readabilityHandler = nil
                processBox.terminateIfNeeded()
                continuation.finish(
                    throwing: GitCommandError.launchFailed(
                        GitOutputRedactor.redact(error.localizedDescription)
                    )
                )
            }

            continuation.onTermination = { termination in
                guard case .cancelled = termination else {
                    return
                }
                processBox.cancel()
            }
        }
    }
}

private final class GitProcessBox: @unchecked Sendable {
    private let process: Process
    private let cancellation: GitCancellationPolicy
    private let lock = NSLock()

    init(process: Process, cancellation: GitCancellationPolicy) {
        self.process = process
        self.cancellation = cancellation
    }

    func cancel() {
        guard cancellation == .terminateProcess else {
            return
        }
        terminateIfNeeded()
    }

    func terminateIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        if process.isRunning {
            process.terminate()
        }
    }
}

private final class GitProcessOutputState: @unchecked Sendable {
    private let lock = NSLock()
    private var errorBuffer = Data()
    private var errorLines: [String] = []

    var errorText: String {
        lock.lock()
        defer { lock.unlock() }
        return errorLines.joined(separator: "\n")
    }

    func consumeError(
        _ data: Data,
        continuation: AsyncThrowingStream<GitCommandChunk, Error>.Continuation
    ) {
        guard !data.isEmpty else {
            return
        }

        lock.lock()
        errorBuffer.append(data)
        let lines = extractCompleteLines()
        errorLines.append(contentsOf: lines)
        lock.unlock()

        for line in lines {
            continuation.yield(.standardError(line))
        }
    }

    func finishErrors(
        continuation: AsyncThrowingStream<GitCommandChunk, Error>.Continuation
    ) {
        lock.lock()
        let finalLine = String(decoding: errorBuffer, as: UTF8.self)
            .trimmingCharacters(in: .newlines)
        errorBuffer.removeAll()
        let redacted = finalLine.isEmpty
            ? nil
            : GitOutputRedactor.redact(finalLine)
        if let redacted {
            errorLines.append(redacted)
        }
        lock.unlock()

        if let redacted {
            continuation.yield(.standardError(redacted))
        }
    }

    private func extractCompleteLines() -> [String] {
        var lines: [String] = []
        while let lineBreak = errorBuffer.firstIndex(of: 0x0A) {
            let lineData = errorBuffer[..<lineBreak]
            errorBuffer.removeSubrange(...lineBreak)
            let line = String(decoding: lineData, as: UTF8.self)
                .trimmingCharacters(in: .newlines)
            if !line.isEmpty {
                lines.append(GitOutputRedactor.redact(line))
            }
        }
        return lines
    }
}
