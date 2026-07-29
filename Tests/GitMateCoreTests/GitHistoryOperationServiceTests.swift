import Foundation
import GitMateCore

let gitHistoryOperationServiceTests = [
    TestCase("工作区不干净时阻止变基并建议 Stash") {
        let repository = try TemporaryGitRepository.make()
        try repository.write(path: "tracked.txt", content: "base\n")
        try repository.commitAll(message: "初始")
        try repository.write(path: "tracked.txt", content: "dirty\n")
        let service = GitHistoryOperationService()

        let preflight = try await service.preflight(
            repositoryURL: repository.url,
            request: .rebase(onto: "main")
        )

        try expect(!preflight.canStart, "脏工作区不得开始")
        try expectEqual(
            preflight.blocker,
            .workingTreeNotClean,
            "应给出明确原因"
        )
        try expect(
            preflight.availableRecovery.contains(.createStash),
            "应提供 Stash"
        )
    },
    TestCase("合并冲突可检测并中止恢复原分支") {
        let fixture = try await MergeConflictFixture.make()

        let result = try await fixture.startMerge()

        try expectEqual(result, .conflicted, "应进入冲突")
        let activeState = try fixture.detector.detect(
            repositoryURL: fixture.repository.url
        )
        try expectEqual(activeState.kind, .merge, "应检测 MERGE_HEAD")
        try await fixture.service.abort(
            repositoryURL: fixture.repository.url
        )
        let cleanState = try fixture.detector.detect(
            repositoryURL: fixture.repository.url
        )
        try expectEqual(cleanState, .none, "中止后状态应清理")
        let restoredContent = try fixture.repository.read(path: fixture.path)
        try expectEqual(
            restoredContent,
            "current\n",
            "中止后应恢复当前分支内容"
        )
    },
    TestCase("解决合并冲突后可继续完成") {
        let fixture = try await MergeConflictFixture.make()
        _ = try await fixture.startMerge()
        try fixture.repository.write(
            path: fixture.path,
            content: "resolved\n"
        )
        try fixture.repository.run(["add", fixture.path])

        let result = try await fixture.service.continue(
            repositoryURL: fixture.repository.url
        )

        try expectEqual(result, .completed, "解决后应完成合并")
        let state = try fixture.detector.detect(
            repositoryURL: fixture.repository.url
        )
        try expectEqual(state, .none, "完成后应清理合并状态")
    },
    TestCase("变基和拣选使用真实提交范围") {
        let repository = try TemporaryGitRepository.make()
        try repository.write(path: "base.txt", content: "base\n")
        try repository.commitAll(message: "初始")
        try repository.run(["switch", "-c", "feature"])
        try repository.write(path: "feature.txt", content: "feature\n")
        try repository.commitAll(message: "功能提交")
        let featureCommit = try repository.run([
            "rev-parse",
            "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try repository.run(["switch", "main"])
        try repository.write(path: "main.txt", content: "main\n")
        try repository.commitAll(message: "主线提交")
        try repository.run(["switch", "feature"])

        let service = GitHistoryOperationService()
        let rebaseRequest = GitHistoryOperationRequest.rebase(onto: "main")
        let rebasePreflight = try await service.preflight(
            repositoryURL: repository.url,
            request: rebaseRequest
        )
        guard let rebaseConfirmation = rebasePreflight.confirmation else {
            throw TestFailure(description: "变基预检应可执行")
        }
        let rebaseResult = try await service.start(
            repositoryURL: repository.url,
            request: rebaseRequest,
            confirmation: rebaseConfirmation
        )
        try expectEqual(rebaseResult, .completed, "变基应成功")

        try repository.run(["switch", "main"])
        let cherryRequest = GitHistoryOperationRequest.cherryPick(
            commits: [featureCommit]
        )
        let cherryPreflight = try await service.preflight(
            repositoryURL: repository.url,
            request: cherryRequest
        )
        guard let cherryConfirmation = cherryPreflight.confirmation else {
            throw TestFailure(description: "拣选预检应可执行")
        }
        let cherryResult = try await service.start(
            repositoryURL: repository.url,
            request: cherryRequest,
            confirmation: cherryConfirmation
        )
        try expectEqual(cherryResult, .completed, "拣选应成功")
        let content = try repository.read(path: "feature.txt")
        try expectEqual(content, "feature\n", "应应用拣选提交")
    }
]
