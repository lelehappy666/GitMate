import Foundation
import GitMateCore

let workingTreeViewModelTests = [
    TestCase("旧刷新结果不得覆盖新代次") { @MainActor in
        let repository = try TemporaryGitRepository.make()
        let reader = DelayedGenerationWorkingTreeReader()
        let viewModel = WorkingTreeViewModel(
            repositoryURL: repository.url,
            reader: reader
        )

        async let first: Void = viewModel.refresh()
        try await Task.sleep(for: .milliseconds(10))
        await viewModel.refresh()
        _ = await first

        try expectEqual(
            viewModel.snapshot?.generation,
            2,
            "必须保留最新代次"
        )
        try expectEqual(
            viewModel.snapshot?.files.first?.path,
            "new.swift",
            "旧结果不得覆盖新结果"
        )
    },
    TestCase("刷新后只保留仍存在文件的选择") { @MainActor in
        let repository = try TemporaryGitRepository.make()
        let reader = SequencedWorkingTreeReader(
            snapshots: [
                snapshot(paths: ["A.swift", "B.swift"], generation: 1),
                snapshot(paths: ["B.swift"], generation: 2)
            ]
        )
        let viewModel = WorkingTreeViewModel(
            repositoryURL: repository.url,
            reader: reader
        )

        await viewModel.refresh()
        viewModel.toggleSelection("A.swift")
        viewModel.toggleSelection("B.swift")
        await viewModel.refresh()

        try expectEqual(
            viewModel.selection,
            Set(["B.swift"]),
            "已消失文件必须从选择中删除"
        )
    },
    TestCase("文件系统突发变化经过防抖只产生一个事件") {
        let repository = try TemporaryGitRepository.make()
        let watcher = RepositoryFileSystemWatcher(
            debounce: .milliseconds(80)
        )
        let stream = watcher.events(repositoryURL: repository.url)
        let collector = Task {
            var count = 0
            for await _ in stream {
                count += 1
            }
            return count
        }
        try await Task.sleep(for: .milliseconds(30))

        try repository.write(path: "A.swift", content: "1\n")
        try repository.write(path: "B.swift", content: "2\n")
        try repository.write(path: "C.swift", content: "3\n")
        try await Task.sleep(for: .milliseconds(260))
        collector.cancel()
        let eventCount = await collector.value

        try expectEqual(eventCount, 1, "突发变化只能触发一次刷新")
    }
]

private actor DelayedGenerationWorkingTreeReader: WorkingTreeReading {
    private var callCount = 0

    func trackedSnapshot(
        repositoryURL: URL,
        generation: UInt64
    ) async throws -> WorkingTreeSnapshot {
        callCount += 1
        let currentCall = callCount
        try await Task.sleep(
            for: currentCall == 1
                ? .milliseconds(80)
                : .milliseconds(1)
        )
        return snapshot(
            paths: [currentCall == 1 ? "old.swift" : "new.swift"],
            generation: generation
        )
    }

    nonisolated func untrackedBatches(
        repositoryURL: URL,
        generation: UInt64,
        batchSize: Int
    ) -> AsyncThrowingStream<WorkingTreeBatch, Error> {
        emptyBatchStream()
    }
}

private actor SequencedWorkingTreeReader: WorkingTreeReading {
    private var snapshots: [WorkingTreeSnapshot]

    init(snapshots: [WorkingTreeSnapshot]) {
        self.snapshots = snapshots
    }

    func trackedSnapshot(
        repositoryURL: URL,
        generation: UInt64
    ) throws -> WorkingTreeSnapshot {
        let next = snapshots.removeFirst()
        return WorkingTreeSnapshot(
            branch: next.branch,
            files: next.files,
            untrackedScan: next.untrackedScan,
            generation: generation
        )
    }

    nonisolated func untrackedBatches(
        repositoryURL: URL,
        generation: UInt64,
        batchSize: Int
    ) -> AsyncThrowingStream<WorkingTreeBatch, Error> {
        emptyBatchStream()
    }
}

private func snapshot(
    paths: [String],
    generation: UInt64
) -> WorkingTreeSnapshot {
    WorkingTreeSnapshot(
        branch: LocalBranchStatus(
            name: "main",
            upstream: nil,
            ahead: 0,
            behind: 0
        ),
        files: paths.map {
            WorkingTreeFile(path: $0, category: .unstaged)
        },
        untrackedScan: .notStarted,
        generation: generation
    )
}

private func emptyBatchStream()
    -> AsyncThrowingStream<WorkingTreeBatch, Error>
{
    AsyncThrowingStream { continuation in
        continuation.finish()
    }
}
