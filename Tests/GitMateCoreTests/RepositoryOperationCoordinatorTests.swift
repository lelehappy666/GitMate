import Foundation
import GitMateCore

let repositoryOperationCoordinatorTests = [
    TestCase("索引锁存在时拒绝写操作且不删除锁") {
        let repository = try TemporaryGitRepository.make()
        try repository.write(path: ".git/index.lock", data: Data())
        let coordinator = RepositoryOperationCoordinator()
        let probe = ExecutionProbe()

        do {
            _ = try await coordinator.run(
                repositoryURL: repository.url,
                kind: .stage
            ) {
                await probe.markExecuted()
                return true
            }
            throw TestFailure(description: "索引锁存在时不应开始写操作")
        } catch LocalGitError.repositoryLocked {
        }

        let executed = await probe.executed
        try expect(!executed, "被锁定时不得执行操作闭包")
        try expect(
            FileManager.default.fileExists(
                atPath: repository.url.appending(path: ".git/index.lock").path
            ),
            "不得自动删除未知 Git 锁"
        )
    },
    TestCase("同一仓库拒绝第二个并发写操作") {
        let repository = try TemporaryGitRepository.make()
        let coordinator = RepositoryOperationCoordinator()
        let gate = BlockingGate()
        let first = Task {
            try await coordinator.run(
                repositoryURL: repository.url,
                kind: .commit
            ) {
                await gate.hold()
                return true
            }
        }
        await gate.waitUntilHeld()

        do {
            _ = try await coordinator.run(
                repositoryURL: repository.url,
                kind: .stash
            ) {
                true
            }
            throw TestFailure(description: "并发写操作不应成功")
        } catch LocalGitError.repositoryBusy {
            await gate.release()
            _ = try await first.value
        }
    },
    TestCase("不同仓库允许并发写操作") {
        let repositoryA = try TemporaryGitRepository.make()
        let repositoryB = try TemporaryGitRepository.make()
        let coordinator = RepositoryOperationCoordinator()
        let probe = ConcurrencyProbe()

        async let valueA: String = coordinator.run(
            repositoryURL: repositoryA.url,
            kind: .commit
        ) {
            await probe.enter()
            try await Task.sleep(for: .milliseconds(50))
            await probe.leave()
            return "A"
        }
        async let valueB: String = coordinator.run(
            repositoryURL: repositoryB.url,
            kind: .stash
        ) {
            await probe.enter()
            try await Task.sleep(for: .milliseconds(50))
            await probe.leave()
            return "B"
        }

        let values = try await [valueA, valueB]
        let maximumConcurrency = await probe.maximum

        try expectEqual(
            values.sorted(),
            ["A", "B"],
            "不同仓库的结果都应返回"
        )
        try expectEqual(
            maximumConcurrency,
            2,
            "不同仓库不得被全局串行化"
        )
    }
]

private actor BlockingGate {
    private var isHeld = false
    private var continuation: CheckedContinuation<Void, Never>?

    func hold() async {
        isHeld = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilHeld() async {
        while !isHeld {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor ConcurrencyProbe {
    private var active = 0
    private(set) var maximum = 0

    func enter() {
        active += 1
        maximum = max(maximum, active)
    }

    func leave() {
        active -= 1
    }
}

private actor ExecutionProbe {
    private(set) var executed = false

    func markExecuted() {
        executed = true
    }
}
