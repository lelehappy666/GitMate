import GitMateCore

let credentialStoreTests = [
    TestCase("凭据存储支持保存读取覆盖和删除") {
        let store = InMemoryCredentialStore()

        try store.save(token: "first", accountID: "github.com:1")
        let firstToken = try store.token(accountID: "github.com:1")
        try expectEqual(
            firstToken,
            "first",
            "应读取已保存的令牌"
        )

        try store.save(token: "second", accountID: "github.com:1")
        let secondToken = try store.token(accountID: "github.com:1")
        try expectEqual(
            secondToken,
            "second",
            "再次保存应覆盖旧令牌"
        )

        try store.deleteToken(accountID: "github.com:1")
        let deletedToken = try store.token(accountID: "github.com:1")
        try expectEqual(
            deletedToken,
            nil,
            "删除后不应保留令牌"
        )
    },
    TestCase("不同账户的令牌相互隔离") {
        let store = InMemoryCredentialStore()
        try store.save(token: "github-token", accountID: "github.com:1")
        try store.save(token: "enterprise-token", accountID: "enterprise:8")
        let githubToken = try store.token(accountID: "github.com:1")
        let enterpriseToken = try store.token(accountID: "enterprise:8")

        try expectEqual(
            githubToken,
            "github-token",
            "GitHub.com 账户应读取自己的令牌"
        )
        try expectEqual(
            enterpriseToken,
            "enterprise-token",
            "企业账户应读取自己的令牌"
        )
    }
]
