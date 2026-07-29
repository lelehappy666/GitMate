import Foundation
import GitMateCore

private let workspaceRepositoryFixture = Repository(
    id: 101,
    name: "mac-client",
    fullName: "GitMate/mac-client",
    isPrivate: true,
    defaultBranch: "main",
    sizeInKilobytes: 2_457_600,
    cloneURL: URL(string: "https://github.com/GitMate/mac-client.git")!,
    ownerAvatarURL: nil
)

let githubWorkspaceAPITests = [
    TestCase("仓库摘要使用分离搜索并解析在线数量") {
        let recorder = LockedRecorder<URLRequest>()
        URLProtocolStub.handler = { request in
            recorder.append(request)
            switch request.url?.path {
            case "/repos/GitMate/mac-client":
                return try stubResponse(
                    for: request,
                    body: #"{"language":"Swift","updated_at":"2026-07-29T10:00:00Z"}"#
                )
            case "/search/issues":
                let query = URLComponents(
                    url: request.url!,
                    resolvingAgainstBaseURL: false
                )?.queryItems?.first(where: { $0.name == "q" })?.value
                switch query {
                case "repo:GitMate/mac-client is:issue is:open":
                    return try stubResponse(
                        for: request,
                        body: #"{"total_count":7,"items":[]}"#
                    )
                case "repo:GitMate/mac-client is:pr is:open":
                    return try stubResponse(
                        for: request,
                        body: #"{"total_count":3,"items":[]}"#
                    )
                default:
                    return try stubResponse(
                        for: request,
                        statusCode: 422,
                        body: #"{"message":"invalid query"}"#
                    )
                }
            case "/repos/GitMate/mac-client/actions/runs":
                return try stubResponse(
                    for: request,
                    body: #"{"total_count":2,"workflow_runs":[]}"#
                )
            default:
                return try stubResponse(
                    for: request,
                    statusCode: 404,
                    body: #"{"message":"Not Found"}"#
                )
            }
        }
        let api = URLSessionGitHubWorkspaceAPI(session: makeStubSession())

        let summary = try await api.repositorySummary(
            repository: workspaceRepositoryFixture,
            token: "secret"
        )
        let requests = recorder.snapshot
        let searchRequests = requests.filter { $0.url?.path == "/search/issues" }
        let actionsRequest = requests.first {
            $0.url?.path == "/repos/GitMate/mac-client/actions/runs"
        }

        try expectEqual(summary.repositoryID, 101, "在线摘要应关联请求仓库")
        try expectEqual(summary.primaryLanguage, "Swift", "应解析主要语言")
        try expectEqual(summary.openIssueCount, 7, "应解析开放议题数量")
        try expectEqual(summary.openPullRequestCount, 3, "应解析开放拉取请求数量")
        try expectEqual(summary.failedWorkflowCount, 2, "应只解析失败工作流数量")
        try expectEqual(
            summary.remoteUpdatedAt?.timeIntervalSince1970,
            1_785_319_200,
            "应解析远程更新时间"
        )
        try expectEqual(searchRequests.count, 2, "议题与拉取请求必须分开查询")
        try expect(
            searchRequests.allSatisfy {
                $0.url?.absoluteString.contains("%20") == true
                    && $0.url?.absoluteString.contains(" ") == false
            },
            "搜索查询中的空格必须正确 URL 编码"
        )
        try expectEqual(
            actionsRequest.flatMap {
                URLComponents(
                    url: $0.url!,
                    resolvingAgainstBaseURL: false
                )?.queryItems
            },
            [
                URLQueryItem(name: "status", value: "failure"),
                URLQueryItem(name: "per_page", value: "1")
            ],
            "Actions 请求应只查询失败摘要"
        )
        try expect(
            requests.allSatisfy {
                $0.value(forHTTPHeaderField: "Authorization") == "Bearer secret"
                    && $0.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28"
                    && $0.url?.absoluteString.contains("secret") == false
            },
            "所有请求应复用固定认证头且不得把令牌写入 URL"
        )
    },
    TestCase("API 限流保留恢复时间") {
        URLProtocolStub.handler = { request in
            try stubResponse(
                for: request,
                statusCode: 403,
                headers: [
                    "X-RateLimit-Remaining": "0",
                    "X-RateLimit-Reset": "1785300000"
                ],
                body: #"{"message":"API rate limit exceeded"}"#
            )
        }
        let api = URLSessionGitHubWorkspaceAPI(session: makeStubSession())

        do {
            _ = try await api.repositorySummary(
                repository: workspaceRepositoryFixture,
                token: "secret"
            )
            throw TestFailure(description: "限流响应不应成功")
        } catch let WorkspaceAPIError.rateLimited(resetAt) {
            try expectEqual(
                resetAt.timeIntervalSince1970,
                1_785_300_000,
                "应保留准确的限流恢复时间"
            )
        }
    },
    TestCase("限流同时返回两种恢复头时优先 Retry-After") {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        URLProtocolStub.handler = { request in
            try stubResponse(
                for: request,
                statusCode: 403,
                headers: [
                    "Retry-After": "30",
                    "X-RateLimit-Remaining": "0",
                    "X-RateLimit-Reset": "2000000900"
                ],
                body: #"{"message":"API rate limit exceeded"}"#
            )
        }
        let api = URLSessionGitHubWorkspaceAPI(
            session: makeStubSession(),
            now: { now }
        )

        do {
            _ = try await api.repositorySummary(
                repository: workspaceRepositoryFixture,
                token: "secret"
            )
            throw TestFailure(description: "限流响应不应成功")
        } catch let WorkspaceAPIError.rateLimited(resetAt) {
            try expectEqual(
                resetAt.timeIntervalSince1970,
                2_000_000_030,
                "Retry-After 应优先于 X-RateLimit-Reset"
            )
        }
    },
    TestCase("无效 Retry-After 回退主限流恢复时间") {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        for invalidRetryAfter in ["-5", "NaN", "Infinity", "not-a-number"] {
            URLProtocolStub.handler = { request in
                try stubResponse(
                    for: request,
                    statusCode: 403,
                    headers: [
                        "Retry-After": invalidRetryAfter,
                        "X-RateLimit-Remaining": "0",
                        "X-RateLimit-Reset": "2000000900"
                    ],
                    body: #"{"message":"API rate limit exceeded"}"#
                )
            }
            let api = URLSessionGitHubWorkspaceAPI(
                session: makeStubSession(),
                now: { now }
            )

            do {
                _ = try await api.repositorySummary(
                    repository: workspaceRepositoryFixture,
                    token: "secret"
                )
                throw TestFailure(description: "限流响应不应成功")
            } catch let WorkspaceAPIError.rateLimited(resetAt) {
                try expectEqual(
                    resetAt.timeIntervalSince1970,
                    2_000_000_900,
                    "无效 Retry-After 应回退 X-RateLimit-Reset"
                )
            }
        }
    },
    TestCase("无效权限响应映射为重新授权") {
        URLProtocolStub.handler = { request in
            try stubResponse(
                for: request,
                statusCode: 401,
                body: #"{"message":"Bad credentials"}"#
            )
        }
        let api = URLSessionGitHubWorkspaceAPI(session: makeStubSession())

        do {
            _ = try await api.repositorySummary(
                repository: workspaceRepositoryFixture,
                token: "expired"
            )
            throw TestFailure(description: "401 响应不应成功")
        } catch WorkspaceAPIError.authorizationRequired {
            // 业务状态由错误类型表达。
        }
    },
    TestCase("403 权限不足映射为重新授权") {
        URLProtocolStub.handler = { request in
            try stubResponse(
                for: request,
                statusCode: 403,
                headers: ["X-RateLimit-Remaining": "4999"],
                body: #"{"message":"Resource not accessible"}"#
            )
        }
        let api = URLSessionGitHubWorkspaceAPI(session: makeStubSession())

        do {
            _ = try await api.repositorySummary(
                repository: workspaceRepositoryFixture,
                token: "insufficient"
            )
            throw TestFailure(description: "403 权限响应不应成功")
        } catch WorkspaceAPIError.authorizationRequired {
            // 非限流 403 必须进入重新授权状态。
        }
    },
    TestCase("429 与二级限流都保留恢复时间") {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let scenarios: [(Int, [String: String], String, TimeInterval)] = [
            (
                429,
                ["Retry-After": "30"],
                #"{"message":"Too many requests"}"#,
                2_000_000_030
            ),
            (
                403,
                ["Retry-After": "60"],
                #"{"message":"You have exceeded a secondary rate limit"}"#,
                2_000_000_060
            ),
            (
                403,
                [:],
                #"{"message":"You have exceeded a secondary rate limit"}"#,
                2_000_000_060
            )
        ]

        for (statusCode, headers, body, expectedResetAt) in scenarios {
            URLProtocolStub.handler = { request in
                try stubResponse(
                    for: request,
                    statusCode: statusCode,
                    headers: headers,
                    body: body
                )
            }
            let api = URLSessionGitHubWorkspaceAPI(
                session: makeStubSession(),
                now: { now }
            )

            do {
                _ = try await api.repositorySummary(
                    repository: workspaceRepositoryFixture,
                    token: "secret"
                )
                throw TestFailure(description: "限流响应不应成功")
            } catch let WorkspaceAPIError.rateLimited(resetAt) {
                try expectEqual(
                    resetAt.timeIntervalSince1970,
                    expectedResetAt,
                    "应按 Retry-After 保留恢复时间"
                )
            }
        }
    },
    TestCase("自定义 API 基址保留前缀并用于所有摘要请求") {
        let recorder = LockedRecorder<URLRequest>()
        URLProtocolStub.handler = { request in
            recorder.append(request)
            switch request.url?.path {
            case "/api/v3/repos/GitMate/mac-client":
                return try stubResponse(
                    for: request,
                    body: #"{"language":"Swift","updated_at":null}"#
                )
            case "/api/v3/search/issues":
                return try stubResponse(
                    for: request,
                    body: #"{"total_count":0,"items":[]}"#
                )
            case "/api/v3/repos/GitMate/mac-client/actions/runs":
                return try stubResponse(
                    for: request,
                    body: #"{"total_count":0,"workflow_runs":[]}"#
                )
            default:
                return try stubResponse(
                    for: request,
                    statusCode: 404,
                    body: #"{"message":"Not Found"}"#
                )
            }
        }
        let api = URLSessionGitHubWorkspaceAPI(
            session: makeStubSession(),
            baseURL: URL(string: "https://ghe.example/api/v3")!
        )

        _ = try await api.repositorySummary(
            repository: workspaceRepositoryFixture,
            token: "secret"
        )

        try expectEqual(recorder.snapshot.count, 4, "摘要应完成四个真实边界请求")
        try expect(
            recorder.snapshot.allSatisfy {
                $0.url?.host() == "ghe.example"
                    && $0.url?.path.hasPrefix("/api/v3/") == true
            },
            "所有请求都应保留注入基址的主机和路径前缀"
        )
    },
    TestCase("README 解码 Base64 原始内容和下载地址") {
        URLProtocolStub.handler = { request in
            try stubResponse(
                for: request,
                body: """
                {
                  "path": "README.md",
                  "content": "IyBHaXRNYXRlCg\\nrkvaDlpb0K",
                  "encoding": "base64",
                  "download_url": "https://raw.githubusercontent.com/GitMate/mac-client/main/README.md"
                }
                """
            )
        }
        let api = URLSessionGitHubWorkspaceAPI(session: makeStubSession())

        let readme = try await api.readme(
            repository: workspaceRepositoryFixture,
            token: "secret"
        )

        try expectEqual(readme.repositoryID, 101, "README 应关联请求仓库")
        try expectEqual(readme.path, "README.md", "应保留 README 路径")
        try expectEqual(readme.markdown, "# GitMate\n\n你好\n", "应解码原始 Markdown")
        try expectEqual(
            readme.downloadURL?.absoluteString,
            "https://raw.githubusercontent.com/GitMate/mac-client/main/README.md",
            "应保留原始内容下载地址"
        )
    },
    TestCase("README 拒绝非 Base64 编码") {
        URLProtocolStub.handler = { request in
            try stubResponse(
                for: request,
                body: """
                {
                  "path": "README.md",
                  "content": "# GitMate",
                  "encoding": "utf-8",
                  "download_url": null
                }
                """
            )
        }
        let api = URLSessionGitHubWorkspaceAPI(session: makeStubSession())

        do {
            _ = try await api.readme(
                repository: workspaceRepositoryFixture,
                token: "secret"
            )
            throw TestFailure(description: "非 Base64 README 不应成功")
        } catch WorkspaceAPIError.decoding {
            // 解析失败由稳定错误类型表达。
        }
    }
]
