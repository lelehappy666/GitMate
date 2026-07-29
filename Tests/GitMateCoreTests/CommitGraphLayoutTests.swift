import Foundation
import GitMateCore

let commitGraphLayoutTests = [
    TestCase("同一提交页重复布局结果稳定") {
        let page = CommitGraphPage(
            commits: [
                graphCommit(
                    hash: "merge",
                    parents: ["main-parent", "feature-parent"]
                ),
                graphCommit(hash: "main-parent", parents: ["base"]),
                graphCommit(hash: "feature-parent", parents: ["base"]),
                graphCommit(hash: "base")
            ],
            nextCursor: nil
        )

        let first = CommitGraphLayout().layout(page: page)
        let second = CommitGraphLayout().layout(page: page)

        try expectEqual(first, second, "相同输入必须产生完全相同的节点和边")
    },
    TestCase("合并提交为每个父提交生成边") {
        let page = CommitGraphPage(
            commits: [
                graphCommit(
                    hash: "merge",
                    parents: ["main-parent", "feature-parent"]
                ),
                graphCommit(hash: "main-parent"),
                graphCommit(hash: "feature-parent")
            ],
            nextCursor: nil
        )

        let result = CommitGraphLayout().layout(page: page)
        let mergeEdges = result.edges.filter { $0.childHash == "merge" }

        try expectEqual(mergeEdges.count, 2, "双父提交必须生成两条关系边")
        try expect(
            mergeEdges.contains { $0.kind == .merge },
            "额外父提交的边必须明确标记为合并关系"
        )
    },
    TestCase("不同分支使用不同稳定列") {
        let page = CommitGraphPage(
            commits: [
                graphCommit(
                    hash: "main",
                    parents: ["base"],
                    decorations: ["HEAD -> main"]
                ),
                graphCommit(
                    hash: "feature",
                    parents: ["base"],
                    decorations: ["feature/sync"]
                ),
                graphCommit(hash: "base")
            ],
            nextCursor: nil
        )

        let result = CommitGraphLayout().layout(page: page)
        let mainColumn = result.nodes.first { $0.hash == "main" }?.column
        let featureColumn = result.nodes.first { $0.hash == "feature" }?.column

        try expect(mainColumn != featureColumn, "并行分支节点不得落在同一列")
    }
]

private func graphCommit(
    hash: String,
    parents: [String] = [],
    decorations: [String] = []
) -> GitCommit {
    GitCommit(
        shortHash: String(hash.prefix(7)),
        fullHash: hash,
        subject: "提交 \(hash)",
        authorName: "Lele",
        authorEmail: "lele@example.com",
        authoredAt: Date(timeIntervalSince1970: 100),
        parentHashes: parents,
        decorations: decorations
    )
}
