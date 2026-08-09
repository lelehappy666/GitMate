import Foundation
import GitMateCore

let commitGraphSearchIndexTests = [
    TestCase("提交搜索使用预构建倒排候选而非扫描全历史") {
        let commits = (0..<50_000).reversed().map { index in
            let subject: String
            if index == 12_345 {
                subject = "修复网络恢复后的索引重复 unique-needle"
            } else {
                subject = "普通性能提交 \(index)"
            }
            let parentHashes: [String]
            if index == 0 {
                parentHashes = []
            } else {
                parentHashes = ["commit-\(index - 1)"]
            }
            return GitCommit(
                shortHash: "c\(index)",
                fullHash: "commit-\(index)",
                subject: subject,
                authorName: "性能测试",
                authorEmail: "performance@example.com",
                authoredAt: Date(timeIntervalSince1970: Double(index)),
                parentHashes: parentHashes,
                decorations: []
            )
        }
        let index = CommitGraphSearchIndex(
            commitsNewestFirst: commits,
            fingerprint: CommitGraphReferenceFingerprint(
                references: [
                    CommitGraphReference(
                        name: "refs/remotes/origin/release-search",
                        targetHash: "commit-12345",
                        kind: .remoteBranch
                    )
                ],
                headName: nil,
                headHash: nil,
                isShallow: false
            )
        )

        try expectEqual(
            index.firstMatch(query: "unique-needle"),
            "commit-12345",
            "搜索必须返回最新优先顺序中的真实提交"
        )
        try expectEqual(
            index.firstMatch(query: "release-search"),
            "commit-12345",
            "远程引用名必须进入同一搜索索引"
        )
        try expect(
            index.candidateCount(query: "unique-needle") < 100,
            "唯一关键词查询不得遍历五万条提交"
        )
    }
]
