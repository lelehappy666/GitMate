import Foundation
import GitMateCore

let githubBranchesAPITests = [
    TestCase("远端分支接口分页并映射保护状态") {
        let recorder = LockedRecorder<URLRequest>()
        URLProtocolStub.handler = { request in
            recorder.append(request)
            if request.url?.query?.contains("page=2") == true {
                return try stubResponse(
                    for: request,
                    body: #"[{"name":"develop","commit":{"sha":"def"},"protected":false}]"#
                )
            }
            return try stubResponse(
                for: request,
                headers: [
                    "Link": "<https://api.github.com/repos/GitMate/mac-client/branches?per_page=100&page=2>; rel=\"next\""
                ],
                body: #"[{"name":"main","commit":{"sha":"abc"},"protected":true}]"#
            )
        }
        let api = URLSessionGitHubBranchesAPI(
            client: GitHubRESTClient(session: makeStubSession()),
            repositoryFullName: "GitMate/mac-client"
        )

        let branches = try await api.remoteBranches(token: "secret")

        try expectEqual(branches.map(\.name), ["develop", "main"], "应加载并排序全部分页")
        let main = try branches.first(where: { $0.name == "main" }) ?? {
            throw TestFailure(description: "应返回 main 分支")
        }()
        try expectEqual(main.remoteSHA, "abc", "应解析远端提交")
        try expect(main.isProtected, "应解析 GitHub 分支保护状态")
        try expectEqual(
            recorder.snapshot.first?.url?.path,
            "/repos/GitMate/mac-client/branches",
            "应请求当前仓库分支端点"
        )
        try expectEqual(
            recorder.snapshot.first?.url?.query,
            "per_page=100",
            "每页应请求 100 条"
        )
    },
    TestCase("分支保护接口映射审查与状态检查") {
        URLProtocolStub.handler = { request in
            try stubResponse(
                for: request,
                body: """
                {
                  "required_status_checks": {
                    "strict": true,
                    "contexts": ["build", "test"]
                  },
                  "enforce_admins": {"enabled": true},
                  "required_pull_request_reviews": {
                    "dismiss_stale_reviews": true,
                    "require_code_owner_reviews": true,
                    "required_approving_review_count": 2
                  },
                  "restrictions": null
                }
                """
            )
        }
        let api = URLSessionGitHubBranchesAPI(
            client: GitHubRESTClient(session: makeStubSession()),
            repositoryFullName: "GitMate/mac-client"
        )

        let protection = try await api.branchProtection(
            name: "main",
            token: "secret"
        )

        try expectEqual(protection?.requiredApprovingReviews, 2, "应解析审批数量")
        try expectEqual(protection?.requiredStatusChecks, ["build", "test"], "应解析状态检查")
        try expect(protection?.enforcesAdmins == true, "应解析管理员执行状态")
        try expect(protection?.requiresCodeOwnerReview == true, "应解析代码所有者审查")
    },
    TestCase("Ruleset 接口识别组织继承来源和规则条件") {
        URLProtocolStub.handler = { request in
            try stubResponse(
                for: request,
                body: """
                [{
                  "id": 88,
                  "name": "企业主分支规则",
                  "target": "branch",
                  "source_type": "Organization",
                  "source": "GitMate",
                  "enforcement": "active",
                  "conditions": {
                    "ref_name": {
                      "include": ["~DEFAULT_BRANCH"],
                      "exclude": ["refs/heads/hotfix/*"]
                    }
                  },
                  "rules": [
                    {"type": "required_linear_history"},
                    {"type": "pull_request"}
                  ],
                  "bypass_actors": []
                }]
                """
            )
        }
        let recorder = LockedRecorder<URLRequest>()
        let session = makeStubSession()
        let original = URLProtocolStub.handler
        URLProtocolStub.handler = { request in
            recorder.append(request)
            return try original?(request) ?? {
                throw URLError(.badServerResponse)
            }()
        }
        let api = URLSessionGitHubBranchesAPI(
            client: GitHubRESTClient(session: session),
            repositoryFullName: "GitMate/mac-client"
        )

        let rulesets = try await api.rulesets(token: "secret")
        let ruleset = try rulesets.first ?? {
            throw TestFailure(description: "应返回 Ruleset")
        }()

        try expectEqual(
            ruleset.source,
            .organization(login: "GitMate"),
            "应识别组织继承来源"
        )
        try expect(!ruleset.isEditable, "组织继承规则必须只读")
        try expectEqual(ruleset.includedRefs, ["~DEFAULT_BRANCH"], "应解析包含条件")
        try expectEqual(
            ruleset.excludedRefs,
            ["refs/heads/hotfix/*"],
            "应解析排除条件"
        )
        try expectEqual(
            ruleset.rules.map(\.type),
            ["required_linear_history", "pull_request"],
            "应解析规则类型"
        )
        try expectEqual(
            recorder.snapshot.first?.url?.query,
            "includes_parents=true&per_page=100",
            "Ruleset 列表必须包含继承规则"
        )
    },
    TestCase("Ruleset 详情读取使用精确编号") {
        let recorder = LockedRecorder<URLRequest>()
        URLProtocolStub.handler = { request in
            recorder.append(request)
            return try stubResponse(
                for: request,
                body: """
                {
                  "id": 88,
                  "name": "主分支规则",
                  "target": "branch",
                  "source_type": "Repository",
                  "source": "GitMate/mac-client",
                  "enforcement": "evaluate",
                  "conditions": {
                    "ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}
                  },
                  "rules": [],
                  "bypass_actors": []
                }
                """
            )
        }
        let api = URLSessionGitHubBranchesAPI(
            client: GitHubRESTClient(session: makeStubSession()),
            repositoryFullName: "GitMate/mac-client"
        )

        let ruleset = try await api.ruleset(id: 88, token: "secret")

        try expectEqual(ruleset.id, 88, "应解析指定 Ruleset")
        try expectEqual(ruleset.enforcement, .evaluate, "应解析详情执行模式")
        try expectEqual(
            recorder.snapshot.first?.url?.path,
            "/repos/GitMate/mac-client/rulesets/88",
            "详情请求不得落到 Ruleset 列表端点"
        )
    },
    TestCase("Ruleset 创建更新删除使用结构化负载") {
        let recorder = LockedRecorder<URLRequest>()
        URLProtocolStub.handler = { request in
            recorder.append(request)
            if request.httpMethod == "DELETE" {
                return try stubResponse(for: request, statusCode: 204, body: "")
            }
            let identifier = request.httpMethod == "POST" ? 99 : 89
            return try stubResponse(
                for: request,
                body: """
                {
                  "id": \(identifier),
                  "name": "主分支保护",
                  "target": "branch",
                  "source_type": "Repository",
                  "source": "GitMate/mac-client",
                  "enforcement": "active",
                  "conditions": {
                    "ref_name": {
                      "include": ["~DEFAULT_BRANCH"],
                      "exclude": []
                    }
                  },
                  "rules": [{"type": "required_linear_history"}],
                  "bypass_actors": []
                }
                """
            )
        }
        let api = URLSessionGitHubBranchesAPI(
            client: GitHubRESTClient(session: makeStubSession()),
            repositoryFullName: "GitMate/mac-client"
        )
        let input = RepositoryRulesetInput(
            name: "主分支保护",
            enforcement: .active,
            target: .branch,
            includedRefs: ["~DEFAULT_BRANCH"],
            excludedRefs: [],
            rules: [
                RepositoryRule(
                    type: "pull_request",
                    parameters: [
                        "required_approving_review_count": .integer(2)
                    ]
                )
            ]
        )
        let editable = RepositoryRuleset(
            id: 89,
            name: "主分支保护",
            enforcement: .evaluate,
            source: .repository
        )

        let created = try await api.createRuleset(input, token: "secret")
        let updated = try await api.updateRuleset(
            editable,
            input: input,
            token: "secret"
        )
        try await api.deleteRuleset(editable, token: "secret")

        try expectEqual(created.id, 99, "应解析新建 Ruleset")
        try expectEqual(updated.enforcement, .active, "应解析更新结果")
        let patch = try recorder.snapshot.first(where: { $0.httpMethod == "PATCH" }) ?? {
            throw TestFailure(description: "应发送 PATCH Ruleset 请求")
        }()
        let data = try requestBodyData(patch) ?? {
            throw TestFailure(description: "PATCH 应包含 JSON 负载")
        }()
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let conditions = body?["conditions"] as? [String: Any]
        let referenceNames = conditions?["ref_name"] as? [String: Any]
        let rules = body?["rules"] as? [[String: Any]]
        try expectEqual(body?["enforcement"] as? String, "active", "应编码执行状态")
        try expectEqual(
            referenceNames?["include"] as? [String],
            ["~DEFAULT_BRANCH"],
            "应编码分支包含条件"
        )
        try expectEqual(
            rules?.first?["type"] as? String,
            "pull_request",
            "应编码规则数组"
        )
        let parameters = rules?.first?["parameters"] as? [String: Any]
        try expectEqual(
            parameters?["required_approving_review_count"] as? Int,
            2,
            "应保留规则参数的真实 JSON 类型"
        )
        try expect(
            recorder.snapshot.contains {
                $0.httpMethod == "DELETE"
                    && $0.url?.path == "/repos/GitMate/mac-client/rulesets/89"
            },
            "删除必须指向精确 Ruleset 编号"
        )
    },
    TestCase("组织继承 Ruleset 在发请求前拒绝更新") {
        let recorder = LockedRecorder<URLRequest>()
        URLProtocolStub.handler = { request in
            recorder.append(request)
            return try stubResponse(for: request, statusCode: 500, body: "{}")
        }
        let api = URLSessionGitHubBranchesAPI(
            client: GitHubRESTClient(session: makeStubSession()),
            repositoryFullName: "GitMate/mac-client"
        )
        let inherited = RepositoryRuleset(
            id: 88,
            name: "企业规则",
            enforcement: .active,
            source: .organization(login: "GitMate")
        )
        let input = RepositoryRulesetInput(
            name: "企业规则",
            enforcement: .disabled,
            target: .branch
        )

        do {
            _ = try await api.updateRuleset(
                inherited,
                input: input,
                token: "secret"
            )
            throw TestFailure(description: "继承 Ruleset 不应允许更新")
        } catch RulesetOperationError.inheritedRulesetIsReadOnly {}
        try expectEqual(recorder.snapshot.count, 0, "只读校验必须发生在网络请求前")
    },
    TestCase("标签 Release 摘要保留网页入口") {
        URLProtocolStub.handler = { request in
            try stubResponse(
                for: request,
                body: """
                {
                  "id": 501,
                  "tag_name": "v2.4.0",
                  "name": "GitMate 2.4",
                  "draft": false,
                  "prerelease": false,
                  "published_at": "2026-07-20T08:30:00Z",
                  "html_url": "https://github.com/GitMate/mac-client/releases/tag/v2.4.0"
                }
                """
            )
        }
        let api = URLSessionGitHubBranchesAPI(
            client: GitHubRESTClient(session: makeStubSession()),
            repositoryFullName: "GitMate/mac-client"
        )

        let release = try await api.tagReleaseSummary(
            name: "v2.4.0",
            token: "secret"
        )

        try expectEqual(release?.name, "GitMate 2.4", "应解析 Release 名称")
        try expectEqual(
            release?.webURL.absoluteString,
            "https://github.com/GitMate/mac-client/releases/tag/v2.4.0",
            "Release 只提供真实网页入口"
        )
    }
]
