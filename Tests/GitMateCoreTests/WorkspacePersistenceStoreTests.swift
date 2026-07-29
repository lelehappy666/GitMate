import Foundation
import GitMateCore

let workspacePersistenceStoreTests = [
    TestCase("议题草稿按账户和仓库隔离") {
        let store = InMemoryWorkspacePersistenceStore()
        try store.saveDraft(
            IssueDraft(title: "A", body: "正文"),
            accountID: "github.com:1",
            repositoryID: 101
        )

        let otherAccount = try store.issueDraft(
            accountID: "github.com:2",
            repositoryID: 101
        )
        let otherRepository = try store.issueDraft(
            accountID: "github.com:1",
            repositoryID: 102
        )
        let matching = try store.issueDraft(
            accountID: "github.com:1",
            repositoryID: 101
        )

        try expectEqual(otherAccount, nil, "其他账户不应读取该草稿")
        try expectEqual(otherRepository, nil, "其他仓库不应读取该草稿")
        try expectEqual(matching?.title, "A", "相同账户仓库应恢复草稿")
    },
    TestCase("保存视图覆盖当前仓库且不影响其他仓库") {
        let store = InMemoryWorkspacePersistenceStore()
        let first = SavedIssueView(name: "我创建的", query: "author:@me")
        let replacement = SavedIssueView(name: "待处理", query: "is:open")

        try store.saveViews(
            [first],
            accountID: "github.com:1",
            repositoryID: 101
        )
        try store.saveViews(
            [replacement],
            accountID: "github.com:1",
            repositoryID: 101
        )
        let matchingViews = try store.savedViews(
            accountID: "github.com:1",
            repositoryID: 101
        )
        let otherViews = try store.savedViews(
            accountID: "github.com:1",
            repositoryID: 102
        )

        try expectEqual(
            matchingViews,
            [replacement],
            "保存视图应原子覆盖"
        )
        try expectEqual(
            otherViews,
            [],
            "其他仓库不应被写入"
        )
    }
]
