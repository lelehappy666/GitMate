import Foundation
import GitMateCore

private enum LabelMergeFixtureError: Error {
    case removeFailed
}

private actor LabelMergeAPIFake: LabelMergeAPI {
    let numbers: [Int]
    let removalFailures: Set<Int>
    private(set) var addedIssueNumbers: [Int] = []
    private(set) var removedIssueNumbers: [Int] = []
    private(set) var deletedLabels: [String] = []

    init(numbers: [Int], removalFailures: Set<Int> = []) {
        self.numbers = numbers
        self.removalFailures = removalFailures
    }

    func issueNumbers(labelName: String, token: String) async throws -> [Int] {
        numbers
    }

    func addLabels(
        to issueNumber: Int,
        names: [String],
        token: String
    ) async throws {
        addedIssueNumbers.append(issueNumber)
    }

    func removeLabel(
        from issueNumber: Int,
        name: String,
        token: String
    ) async throws {
        removedIssueNumbers.append(issueNumber)
        if removalFailures.contains(issueNumber) {
            throw LabelMergeFixtureError.removeFailed
        }
    }

    func deleteLabel(name: String, token: String) async throws {
        deletedLabels.append(name)
    }

    func snapshot() -> ([Int], [Int], [String]) {
        (addedIssueNumbers, removedIssueNumbers, deletedLabels)
    }
}

let labelMergeServiceTests = [
    TestCase("标签合并拒绝相同来源和目标") {
        let api = LabelMergeAPIFake(numbers: [91])
        let service = LabelMergeService(api: api)

        do {
            _ = try await service.merge(
                source: "bug",
                into: "bug",
                token: "secret"
            )
            throw TestFailure(description: "相同标签不应进入合并流程")
        } catch LabelMergeError.sourceAndTargetAreEqual {}
        let snapshot = await api.snapshot()
        try expectEqual(snapshot.0, [], "危险输入不得修改议题标签")
        try expectEqual(snapshot.2, [], "危险输入不得删除标签")
    },
    TestCase("标签合并跳过已完成议题并保留失败进度") {
        let api = LabelMergeAPIFake(
            numbers: [91, 92, 93],
            removalFailures: [92]
        )
        let service = LabelMergeService(api: api)

        let progress = try await service.merge(
            source: "legacy",
            into: "bug",
            token: "secret",
            completedIssueNumbers: [91]
        )
        let snapshot = await api.snapshot()

        try expectEqual(snapshot.0, [92, 93], "重试时不得重复处理已完成议题")
        try expectEqual(snapshot.1, [92, 93], "每个新议题都应移除来源标签")
        try expectEqual(
            progress.completedIssueNumbers,
            [91, 93],
            "成功进度应保留旧结果并追加新结果"
        )
        try expectEqual(progress.failedIssueNumbers, [92], "应记录失败议题")
        try expectEqual(snapshot.2, [], "存在失败时不得删除来源标签")
    },
    TestCase("标签合并全部成功后才删除来源标签") {
        let api = LabelMergeAPIFake(numbers: [91, 92])
        let service = LabelMergeService(api: api)

        let progress = try await service.merge(
            source: "legacy",
            into: "bug",
            token: "secret"
        )
        let snapshot = await api.snapshot()

        try expectEqual(progress.completedIssueNumbers, [91, 92], "应完成全部议题")
        try expectEqual(progress.failedIssueNumbers, [], "成功时不应有失败项")
        try expectEqual(snapshot.2, ["legacy"], "最后一步才删除来源标签")
    }
]
