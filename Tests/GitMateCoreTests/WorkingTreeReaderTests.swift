import Foundation
import GitMateCore

let workingTreeReaderTests = [
    TestCase("解析已暂存未暂存重命名和冲突状态") {
        let data = Data(
            (
                "# branch.head main\0"
                    + "# branch.upstream origin/main\0"
                    + "# branch.ab +3 -1\0"
                    + "1 M. N... 100644 100644 100644 abc def Sources/A.swift\0"
                    + "2 .M N... 100644 100644 100644 abc def R100 New.swift\0"
                    + "Old.swift\0"
                    + "u UU N... 100644 100644 100644 100644 a b c Conflict.swift\0"
            ).utf8
        )

        let snapshot = try WorkingTreeParser.parseTracked(data)

        try expectEqual(snapshot.branch.name, "main", "应解析当前分支")
        try expectEqual(
            snapshot.branch.upstream,
            "origin/main",
            "应解析上游"
        )
        try expectEqual(snapshot.branch.ahead, 3, "应解析领先数量")
        try expectEqual(snapshot.branch.behind, 1, "应解析落后数量")
        try expectEqual(snapshot.files.count, 3, "应解析三类记录")
        try expect(
            snapshot.files.contains(where: {
                $0.path == "New.swift" && $0.originalPath == "Old.swift"
            }),
            "应解析重命名原路径"
        )
        try expect(
            snapshot.files.contains(where: {
                $0.path == "Conflict.swift" && $0.category == .conflicted
            }),
            "应解析冲突"
        )
    },
    TestCase("未跟踪文件每批最多二百条") {
        var data = Data()
        for index in 0..<501 {
            data.append(Data("文件-\(index).swift".utf8))
            data.append(0)
        }

        let batches = try WorkingTreeParser.parseUntrackedBatches(
            data,
            generation: 7,
            batchSize: 200
        )

        try expectEqual(
            batches.map(\.files.count),
            [200, 200, 101],
            "批次必须稳定"
        )
        try expect(
            batches.allSatisfy { $0.generation == 7 },
            "批次必须携带当前代次"
        )
        try expectEqual(
            batches.last?.isLast,
            true,
            "最后一批必须明确结束"
        )
    },
    TestCase("两阶段读取先返回已跟踪状态再流式返回未跟踪文件") {
        let repository = try TemporaryGitRepository.make()
        try repository.write(path: "tracked.txt", content: "base\n")
        try repository.commitAll(message: "初始")
        try repository.write(path: "tracked.txt", content: "changed\n")
        try repository.write(path: "未跟踪 文件.txt", content: "new\n")
        let reader = WorkingTreeReader(
            executor: ProcessGitCommandExecutor()
        )

        let tracked = try await reader.trackedSnapshot(
            repositoryURL: repository.url,
            generation: 9
        )
        var untracked: [WorkingTreeFile] = []
        for try await batch in reader.untrackedBatches(
            repositoryURL: repository.url,
            generation: 9,
            batchSize: 200
        ) {
            untracked.append(contentsOf: batch.files)
        }

        try expect(
            tracked.files.contains(where: { $0.path == "tracked.txt" }),
            "第一阶段应返回已跟踪变更"
        )
        try expect(
            !tracked.files.contains(where: { $0.path == "未跟踪 文件.txt" }),
            "第一阶段不得等待未跟踪扫描"
        )
        try expect(
            untracked.contains(where: { $0.path == "未跟踪 文件.txt" }),
            "第二阶段应流式返回未跟踪文件"
        )
    }
]
