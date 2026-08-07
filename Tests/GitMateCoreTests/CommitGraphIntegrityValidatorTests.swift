import Foundation
import GitMateCore

let commitGraphIntegrityValidatorTests = [
    TestCase("完整提交图通过节点和父边校验") {
        let snapshot = integritySnapshot(
            commits: [
                integrityCommit("child", parents: ["root"]),
                integrityCommit("root")
            ],
            expectedCommitCount: 2
        )
        let report = CommitGraphIntegrityValidator.validate(snapshot)
        try expectEqual(report.status, .valid, "完整关系必须通过校验")
        try expectEqual(report.actualRelationshipCount, 1, "必须统计父边")
    },
    TestCase("缺失父节点和分支顶点返回无效报告") {
        let snapshot = integritySnapshot(
            commits: [integrityCommit("child", parents: ["missing"])],
            expectedCommitCount: 2,
            references: [
                CommitGraphReference(
                    name: "refs/heads/main",
                    targetHash: "unknown",
                    kind: .localBranch
                )
            ]
        )
        let report = CommitGraphIntegrityValidator.validate(snapshot)
        try expectEqual(report.status, .invalid, "无法解释的缺失必须失败")
        try expectEqual(report.missingParentHashes, ["missing"], "必须报告父节点")
        try expectEqual(report.missingReferenceTargets, ["unknown"], "必须报告分支顶点")
    },
    TestCase("重复提交和重复父边返回无效报告") {
        let snapshot = integritySnapshot(
            commits: [
                integrityCommit("child", parents: ["root"]),
                integrityCommit("child", parents: ["root"]),
                integrityCommit("root")
            ],
            expectedCommitCount: 3
        )
        let report = CommitGraphIntegrityValidator.validate(snapshot)
        try expectEqual(report.status, .invalid, "重复提交或父边必须失败")
        try expectEqual(report.duplicateCommitHashes, ["child"], "必须报告重复提交")
        try expectEqual(
            report.duplicateEdgeIDs,
            ["child->root#0"],
            "重复父边必须使用稳定边标识报告"
        )
    },
    TestCase("浅克隆边界缺失父节点返回警告报告") {
        let snapshot = CommitGraphSnapshot(
            repositoryPath: "/repo",
            fingerprint: CommitGraphReferenceFingerprint(
                references: [],
                headName: "main",
                headHash: "child",
                isShallow: true
            ),
            commitsNewestFirst: [integrityCommit("child", parents: ["boundary"])],
            expectedCommitCount: 1,
            shallowBoundaryParentHashes: ["boundary"],
            generatedAt: Date(timeIntervalSince1970: 200)
        )
        let report = CommitGraphIntegrityValidator.validate(snapshot)
        try expectEqual(report.status, .warning, "浅克隆边界必须返回警告")
        try expectEqual(report.missingParentHashes, [], "浅克隆边界不能算作缺失父节点")
        try expectEqual(
            report.shallowBoundaryParentHashes,
            ["boundary"],
            "必须报告实际命中的浅克隆边界"
        )
    },
    TestCase("缺失 HEAD 顶点返回无效报告") {
        let snapshot = CommitGraphSnapshot(
            repositoryPath: "/repo",
            fingerprint: CommitGraphReferenceFingerprint(
                references: [],
                headName: nil,
                headHash: "detached-head",
                isShallow: false
            ),
            commitsNewestFirst: [integrityCommit("child")],
            expectedCommitCount: 1,
            shallowBoundaryParentHashes: [],
            generatedAt: Date(timeIntervalSince1970: 200)
        )
        let report = CommitGraphIntegrityValidator.validate(snapshot)
        try expectEqual(report.status, .invalid, "缺失 HEAD 顶点必须失败")
        try expectEqual(
            report.missingReferenceTargets,
            ["detached-head"],
            "必须报告缺失 HEAD 顶点"
        )
    },
    TestCase("非浅克隆边界缺失父节点返回无效报告") {
        let snapshot = CommitGraphSnapshot(
            repositoryPath: "/repo",
            fingerprint: CommitGraphReferenceFingerprint(
                references: [],
                headName: "main",
                headHash: "child",
                isShallow: false
            ),
            commitsNewestFirst: [integrityCommit("child", parents: ["boundary"])],
            expectedCommitCount: 1,
            shallowBoundaryParentHashes: ["boundary"],
            generatedAt: Date(timeIntervalSince1970: 200)
        )
        let report = CommitGraphIntegrityValidator.validate(snapshot)
        try expectEqual(report.status, .invalid, "非浅克隆不得豁免缺失父节点")
        try expectEqual(report.missingParentHashes, ["boundary"], "必须保留真实缺失父节点")
        try expectEqual(report.shallowBoundaryParentHashes, [], "非浅克隆不能报告浅边界")
    }
]

private func integrityCommit(
    _ hash: String,
    parents: [String] = []
) -> GitCommit {
    GitCommit(
        shortHash: String(hash.prefix(7)),
        fullHash: hash,
        subject: hash,
        authorName: "测试用户",
        authorEmail: "test@example.com",
        authoredAt: Date(timeIntervalSince1970: 100),
        parentHashes: parents,
        decorations: []
    )
}

private func integritySnapshot(
    commits: [GitCommit],
    expectedCommitCount: Int,
    references: [CommitGraphReference] = []
) -> CommitGraphSnapshot {
    CommitGraphSnapshot(
        repositoryPath: "/repo",
        fingerprint: CommitGraphReferenceFingerprint(
            references: references,
            headName: "main",
            headHash: commits.first?.fullHash,
            isShallow: false
        ),
        commitsNewestFirst: commits,
        expectedCommitCount: expectedCommitCount,
        shallowBoundaryParentHashes: [],
        generatedAt: Date(timeIntervalSince1970: 200)
    )
}
