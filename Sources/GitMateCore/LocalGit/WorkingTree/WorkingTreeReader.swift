import Foundation

public protocol WorkingTreeReading: Sendable {
    func trackedSnapshot(
        repositoryURL: URL,
        generation: UInt64
    ) async throws -> WorkingTreeSnapshot

    func untrackedBatches(
        repositoryURL: URL,
        generation: UInt64,
        batchSize: Int
    ) -> AsyncThrowingStream<WorkingTreeBatch, Error>
}

public struct WorkingTreeReader: WorkingTreeReading, Sendable {
    private let executor: any GitCommandExecuting
    private let commandBuilder: GitCommandBuilder

    public init(
        executor: any GitCommandExecuting,
        commandBuilder: GitCommandBuilder = GitCommandBuilder()
    ) {
        self.executor = executor
        self.commandBuilder = commandBuilder
    }

    public func trackedSnapshot(
        repositoryURL: URL,
        generation: UInt64
    ) async throws -> WorkingTreeSnapshot {
        let command = try commandBuilder.workingTreeStatus(
            repositoryURL: repositoryURL
        )
        let output = try await executor.collect(command)
        return try WorkingTreeParser.parseTracked(
            output.stdoutData,
            generation: generation
        )
    }

    public func untrackedBatches(
        repositoryURL: URL,
        generation: UInt64,
        batchSize: Int
    ) -> AsyncThrowingStream<WorkingTreeBatch, Error> {
        AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    guard batchSize > 0 else {
                        throw WorkingTreeParseError.invalidBatchSize
                    }
                    let command = try commandBuilder.untrackedFiles(
                        repositoryURL: repositoryURL
                    )
                    var buffer = Data()
                    var currentFiles: [WorkingTreeFile] = []
                    currentFiles.reserveCapacity(batchSize)

                    for try await chunk in executor.execute(command) {
                        try Task.checkCancellation()
                        guard case let .standardOutput(data) = chunk else {
                            continue
                        }
                        buffer.append(data)
                        let paths = extractNULTerminatedPaths(from: &buffer)
                        for path in paths {
                            if currentFiles.count == batchSize {
                                continuation.yield(
                                    WorkingTreeBatch(
                                        generation: generation,
                                        files: currentFiles,
                                        isLast: false
                                    )
                                )
                                currentFiles.removeAll(
                                    keepingCapacity: true
                                )
                            }
                            currentFiles.append(
                                WorkingTreeFile(
                                    path: path,
                                    category: .untracked
                                )
                            )
                        }
                    }

                    guard buffer.isEmpty else {
                        throw WorkingTreeParseError.incompleteNULRecord
                    }
                    if !currentFiles.isEmpty {
                        continuation.yield(
                            WorkingTreeBatch(
                                generation: generation,
                                files: currentFiles,
                                isLast: true
                            )
                        )
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(
                        throwing: GitCommandError.cancelled
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                worker.cancel()
            }
        }
    }

    private func extractNULTerminatedPaths(
        from buffer: inout Data
    ) -> [String] {
        var paths: [String] = []
        while let separator = buffer.firstIndex(of: 0) {
            let pathData = buffer[..<separator]
            buffer.removeSubrange(...separator)
            paths.append(String(decoding: pathData, as: UTF8.self))
        }
        return paths
    }
}
