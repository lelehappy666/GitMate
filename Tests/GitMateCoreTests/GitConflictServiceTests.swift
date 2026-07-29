import Foundation
import GitMateCore

let gitConflictServiceTests = [
    TestCase("文本冲突读取基准当前传入三方内容") {
        let fixture = try await MergeConflictFixture.make()
        _ = try await fixture.startMerge()

        let files = try await fixture.conflictService.files(
            repositoryURL: fixture.repository.url
        )
        let document = try await fixture.conflictService.document(
            repositoryURL: fixture.repository.url,
            path: files[0].path
        )

        try expect(
            document.baseText?.contains("base") == true,
            "应读取 stage 1"
        )
        try expect(
            document.currentText?.contains("current") == true,
            "应读取 stage 2"
        )
        try expect(
            document.incomingText?.contains("incoming") == true,
            "应读取 stage 3"
        )
    },
    TestCase("保存最终结果并标记已解决") {
        let fixture = try await MergeConflictFixture.make()
        _ = try await fixture.startMerge()

        try await fixture.conflictService.saveTextResult(
            repositoryURL: fixture.repository.url,
            path: fixture.path,
            text: "resolved\n"
        )

        let savedContent = try fixture.repository.read(path: fixture.path)
        try expectEqual(
            savedContent,
            "resolved\n",
            "应原子写入最终结果"
        )
        let hasUnmergedEntries = try fixture.repository.hasUnmergedEntries()
        try expect(!hasUnmergedEntries, "应通过 git add 标记解决")
        let state = try fixture.detector.detect(
            repositoryURL: fixture.repository.url
        )
        try expect(state.canContinue, "全部解决后应允许继续")
    },
    TestCase("二进制冲突拒绝文本保存") {
        let fixture = try await BinaryConflictFixture.make()

        do {
            try await fixture.service.saveTextResult(
                repositoryURL: fixture.repository.url,
                path: fixture.path,
                text: "invalid"
            )
            throw TestFailure(description: "二进制冲突不应文本保存")
        } catch LocalGitError.binaryConflictRequiresWholeFileChoice {
        }
    },
    TestCase("二进制冲突经确认后选择传入整文件") {
        let fixture = try await BinaryConflictFixture.make()
        let confirmation = fixture.service.wholeFileConfirmation(
            repositoryURL: fixture.repository.url,
            path: fixture.path,
            side: .incoming
        )

        try await fixture.service.chooseWholeFile(
            repositoryURL: fixture.repository.url,
            path: fixture.path,
            side: .incoming,
            confirmation: confirmation
        )

        let savedData = try Data(
            contentsOf: fixture.repository.url.appending(path: fixture.path)
        )
        try expectEqual(
            savedData,
            Data([0, 3, 4]),
            "应写入传入侧完整二进制内容"
        )
        let hasUnmergedEntries = try fixture.repository.hasUnmergedEntries()
        try expect(!hasUnmergedEntries, "整文件选择后应标记解决")
    }
]
