import Foundation
import GitMateCore

let commitGraphTraditionalPublicationTests = [
    TestCase("远程可达提交为实线且本地新增提交为未推送虚线") {
        let index = CommitGraphTraditionalPublicationIndex.build(
            snapshot: publicationSnapshot(
                references: [
                    CommitGraphReference(
                        name: "refs/heads/main",
                        targetHash: "local-tip",
                        kind: .localBranch
                    ),
                    CommitGraphReference(
                        name: "refs/remotes/origin/main",
                        targetHash: "remote-tip",
                        kind: .remoteBranch
                    )
                ],
                commits: [
                    publicationCommit("local-tip", parents: ["remote-tip"]),
                    publicationCommit("remote-tip", parents: ["root"]),
                    publicationCommit("root")
                ]
            )
        )

        try expectEqual(index.state(for: "local-tip"), .localUnpushed, "远端不可达的本地提交必须标记未推送")
        try expect(index.isDashed(childHash: "local-tip"), "本地未推送提交发出的父边必须使用虚线")
        try expectEqual(index.state(for: "remote-tip"), .remoteKnown, "远端 tip 必须使用实线")
        try expect(!index.isDashed(childHash: "remote-tip"), "远程已知提交发出的父边不得使用虚线")
        try expectEqual(index.state(for: "root"), .remoteKnown, "远程 tip 的祖先同样属于远程已知")
    },
    TestCase("没有远程引用时全部本地可达提交均为未推送") {
        let index = CommitGraphTraditionalPublicationIndex.build(
            snapshot: publicationSnapshot(
                references: [
                    CommitGraphReference(
                        name: "refs/heads/main",
                        targetHash: "tip",
                        kind: .localBranch
                    )
                ],
                commits: [
                    publicationCommit("tip", parents: ["root"]),
                    publicationCommit("root")
                ]
            )
        )

        try expectEqual(index.state(for: "tip"), .localUnpushed, "本地 tip 必须标记未推送")
        try expectEqual(index.state(for: "root"), .localUnpushed, "本地 tip 的祖先也必须标记未推送")
    },
    TestCase("仅远程分支可达提交保持远程实线") {
        let index = CommitGraphTraditionalPublicationIndex.build(
            snapshot: publicationSnapshot(
                references: [
                    CommitGraphReference(
                        name: "refs/remotes/upstream/release",
                        targetHash: "remote-only",
                        kind: .remoteBranch
                    )
                ],
                commits: [publicationCommit("remote-only")]
            )
        )

        try expectEqual(index.state(for: "remote-only"), .remoteKnown, "仅远程提交不得误标未推送")
    },
    TestCase("Merge提交所有父边继承子提交的发布状态") {
        let index = CommitGraphTraditionalPublicationIndex.build(
            snapshot: publicationSnapshot(
                references: [
                    CommitGraphReference(
                        name: "refs/heads/main",
                        targetHash: "merge",
                        kind: .localBranch
                    ),
                    CommitGraphReference(
                        name: "refs/remotes/origin/main",
                        targetHash: "main-parent",
                        kind: .remoteBranch
                    )
                ],
                commits: [
                    publicationCommit("merge", parents: ["main-parent", "feature-parent"]),
                    publicationCommit("feature-parent", parents: ["root"]),
                    publicationCommit("main-parent", parents: ["root"]),
                    publicationCommit("root")
                ]
            )
        )

        try expect(index.isDashed(childHash: "merge"), "本地未推送 Merge 发出的每一条父边都必须是虚线")
        try expectEqual(index.state(for: "main-parent"), .remoteKnown, "父提交自身状态不应被 Merge 子提交覆盖")
    },
    TestCase("无本地远程引用的提交不误标未推送") {
        let index = CommitGraphTraditionalPublicationIndex.build(
            snapshot: publicationSnapshot(
                references: [],
                commits: [publicationCommit("orphan")]
            )
        )

        try expectEqual(index.state(for: "orphan"), .unclassified, "没有真实引用的提交应安全退化")
        try expect(!index.isDashed(childHash: "orphan"), "未分类提交不得伪装成未推送")
    }
]

private func publicationSnapshot(
    references: [CommitGraphReference],
    commits: [GitCommit]
) -> CommitGraphSnapshot {
    CommitGraphSnapshot(
        repositoryPath: "/publication",
        fingerprint: CommitGraphReferenceFingerprint(
            references: references,
            headName: references.first(where: { $0.kind == .localBranch })?.name,
            headHash: references.first(where: { $0.kind == .localBranch })?.targetHash,
            isShallow: false
        ),
        commitsNewestFirst: commits,
        expectedCommitCount: commits.count,
        shallowBoundaryParentHashes: [],
        generatedAt: Date(timeIntervalSince1970: 1)
    )
}

private func publicationCommit(
    _ hash: String,
    parents: [String] = []
) -> GitCommit {
    GitCommit(
        shortHash: String(hash.prefix(7)),
        fullHash: hash,
        subject: hash,
        authorName: "Lele",
        authorEmail: "lele@example.com",
        authoredAt: Date(timeIntervalSince1970: 1),
        parentHashes: parents,
        decorations: []
    )
}
