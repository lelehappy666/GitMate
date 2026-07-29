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

            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment
                .merging(environment) { _, newValue in newValue }
            process.standardOutput = standardOutput
            process.standardError = standardError

            standardOutput.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                state.consume(
                    data,
                    stream: .standardOutput,
                    continuation: continuation
                )
            }
            standardError.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                state.consume(
                    data,
                    stream: .standardError,
                    continuation: continuation
                )
            }

            process.terminationHandler = { process in
                standardOutput.fileHandleForReading.readabilityHandler = nil
                standardError.fileHandleForReading.readabilityHandler = nil
                state.consume(
                    standardOutput.fileHandleForReading.readDataToEndOfFile(),
                    stream: .standardOutput,
                    continuation: continuation
                )
                state.consume(
                    standardError.fileHandleForReading.readDataToEndOfFile(),
                    stream: .standardError,
                    continuation: continuation
                )
                state.flush(continuation: continuation)

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
    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private var errorLines: [String] = []

    var standardErrorText: String {
        lock.lock()
        defer { lock.unlock() }
        return errorLines.joined(separator: "\n")
    }

    func consume(
        _ data: Data,
        stream: ProcessStream,
        continuation: AsyncThrowingStream<CommandOutput, Error>.Continuation
    ) {
        guard !data.isEmpty else { return }
        lock.lock()
        var buffer = stream == .standardOutput ? outputBuffer : errorBuffer
        buffer.append(data)
        let lines = extractLines(from: &buffer)
        if stream == .standardOutput {
            outputBuffer = buffer
        } else {
            errorBuffer = buffer
            errorLines.append(contentsOf: lines)
        }
        lock.unlock()

        for line in lines {
            let safeLine = Self.redacted(line)
            continuation.yield(
                stream == .standardOutput
                    ? .standardOutput(safeLine)
                    : .standardError(safeLine)
            )
        }
    }

    func flush(
        continuation: AsyncThrowingStream<CommandOutput, Error>.Continuation
    ) {
        lock.lock()
        let output = String(data: outputBuffer, encoding: .utf8)
        let error = String(data: errorBuffer, encoding: .utf8)
        if let error, !error.isEmpty {
            errorLines.append(error)
        }
        outputBuffer.removeAll()
        errorBuffer.removeAll()
        lock.unlock()

        if let output, !output.isEmpty {
            continuation.yield(.standardOutput(Self.redacted(output)))
        }
        if let error, !error.isEmpty {
            continuation.yield(.standardError(Self.redacted(error)))
        }
    }

    private func extractLines(from data: inout Data) -> [String] {
        var lines: [String] = []
        while let separator = data.firstIndex(
            where: { $0 == 0x0A || $0 == 0x0D }
        ) {
            let lineData = data[..<separator]
            data.removeSubrange(...separator)
            while data.first == 0x0A || data.first == 0x0D {
                data.removeFirst()
            }
            if let line = String(data: lineData, encoding: .utf8) {
                let normalized = line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    lines.append(normalized)
                }
            }
        }
        return lines
    }

    private static func redacted(_ value: String) -> String {
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
