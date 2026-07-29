import Foundation
import GitMateCore

let githubIssuesAPITests = [
    TestCase("议题列表使用仓库筛选并排除拉取请求") {
        let recorder = LockedRecorder<URLRequest>()
        URLProtocolStub.handler = { request in
            recorder.append(request)
            return try stubResponse(
                for: request,
                body: """
                [
                  {
                    "id": 1,
                    "number": 91,
                    "title": "问题",
                    "body": "正文",
                    "state": "open",
                    "user": {"id": 1, "login": "lele"},
                    "assignees": [],
                    "labels": [],
                    "comments": 2,
                    "locked": false,
                    "created_at": "2026-07-20T08:30:00Z",
                    "updated_at": "2026-07-28T08:30:00Z",
                    "html_url": "https://github.com/GitMate/mac-client/issues/91"
                  },
                  {
                    "id": 2,
                    "number": 214,
                    "title": "PR",
                    "body": null,
                    "state": "open",
                    "user": {"id": 2, "login": "mingxu"},
                    "assignees": [],
                    "labels": [],
                    "comments": 0,
                    "locked": false,
                    "created_at": "2026-07-20T08:30:00Z",
                    "updated_at": "2026-07-28T08:30:00Z",
                    "html_url": "https://github.com/GitMate/mac-client/pull/214",
                    "pull_request": {}
                  }
                ]
                """
            )
        }
        let api = URLSessionGitHubIssuesAPI(
            client: GitHubRESTClient(session: makeStubSession()),
            repositoryFullName: "GitMate/mac-client"
        )
        let query = IssueQuery(
            state: .open,
            author: "lele",
            labels: ["bug", "macOS"],
            sort: .updated,
            direction: .descending
        )

        let page = try await api.issues(
            query: query,
            pageURL: nil,
            token: "secret"
        )

        try expectEqual(page.items.map(\.number), [91], "Issues API 结果必须排除 PR")
        let request = try recorder.snapshot.first ?? {
            throw TestFailure(description: "应发送议题列表请求")
        }()
        try expectEqual(
            request.url?.path,
            "/repos/GitMate/mac-client/issues",
            "普通筛选应使用仓库 Issues 端点"
        )
        let components = URLComponents(
            url: request.url!,
            resolvingAgainstBaseURL: false
        )
        let queryItems = Dictionary(
            uniqueKeysWithValues: (components?.queryItems ?? []).map {
                ($0.name, $0.value ?? "")
            }
        )
        try expectEqual(queryItems["state"], "open", "应编码议题状态")
        try expectEqual(queryItems["creator"], "lele", "应编码作者")
        try expectEqual(queryItems["labels"], "bug,macOS", "应编码全部标签")
        try expectEqual(queryItems["per_page"], "100", "每页应请求 100 条")
    },
    TestCase("高级搜索使用 search issues 并限定当前仓库") {
        let recorder = LockedRecorder<URLRequest>()
        URLProtocolStub.handler = { request in
            recorder.append(request)
            return try stubResponse(
                for: request,
                body: """
                {
                  "total_count": 1,
                  "incomplete_results": false,
                  "items": [{
                    "id": 1,
                    "number": 91,
                    "title": "网络恢复异常",
                    "body": null,
                    "state": "open",
                    "user": {"login": "lele"},
                    "assignees": [],
                    "labels": [],
                    "comments": 0,
                    "locked": false,
                    "created_at": "2026-07-20T08:30:00Z",
                    "updated_at": "2026-07-28T08:30:00Z",
                    "html_url": "https://github.com/GitMate/mac-client/issues/91"
                  }]
                }
                """
            )
        }
        let api = URLSessionGitHubIssuesAPI(
            client: GitHubRESTClient(session: makeStubSession()),
            repositoryFullName: "GitMate/mac-client"
        )

        let page = try await api.issues(
            query: IssueQuery(search: "author:lele 网络恢复"),
            pageURL: nil,
            token: "secret"
        )

        try expectEqual(page.items.map(\.number), [91], "应解析搜索结果")
        let request = recorder.snapshot[0]
        try expectEqual(request.url?.path, "/search/issues", "搜索应使用专用端点")
        let query = URLComponents(
            url: request.url!,
            resolvingAgainstBaseURL: false
        )?.queryItems?.first(where: { $0.name == "q" })?.value
        try expect(query?.contains("repo:GitMate/mac-client") == true, "搜索必须限定当前仓库")
        try expect(query?.contains("is:issue") == true, "搜索必须排除 PR")
        try expect(query?.contains("author:lele 网络恢复") == true, "应保留高级语法")
    },
    TestCase("企业版搜索分页继续按搜索响应解码") {
        let recorder = LockedRecorder<URLRequest>()
        URLProtocolStub.handler = { request in
            recorder.append(request)
            let isSecondPage = request.url?.query?.contains("page=2") == true
            return try stubResponse(
                for: request,
                headers: isSecondPage ? [:] : [
                    "Link":
                        "<https://ghe.example/api/v3/search/issues?page=2>; rel=\"next\""
                ],
                body: """
                {
                  "total_count": 2,
                  "incomplete_results": false,
                  "items": [{
                    "id": \(isSecondPage ? 2 : 1),
                    "number": \(isSecondPage ? 92 : 91),
                    "title": "企业议题",
                    "state": "open",
                    "user": {"login": "lele"},
                    "labels": []
                  }]
                }
                """
            )
        }
        let api = URLSessionGitHubIssuesAPI(
            client: GitHubRESTClient(
                session: makeStubSession(),
                apiBaseURL: URL(string: "https://ghe.example/api/v3/")!
            ),
            repositoryFullName: "GitMate/mac-client"
        )
        let query = IssueQuery(search: "企业")

        let first = try await api.issues(
            query: query,
            pageURL: nil,
            token: "secret"
        )
        let second = try await api.issues(
            query: query,
            pageURL: first.nextPageURL,
            token: "secret"
        )

        try expectEqual(second.items.map(\.number), [92], "企业版第二页应按搜索对象解析")
        try expectEqual(
            recorder.snapshot[1].url?.path,
            "/api/v3/search/issues",
            "企业版分页路径应保留 API 前缀"
        )
    },
    TestCase("标签名称作为路径参数时完整编码") {
        let recorder = LockedRecorder<URLRequest>()
        URLProtocolStub.handler = { request in
            recorder.append(request)
            if request.httpMethod == "DELETE" {
                return try stubResponse(for: request, statusCode: 204, body: "")
            }
            return try stubResponse(
                for: request,
                body: """
                {
                  "id": 10,
                  "name": "needs/triage",
                  "color": "ff0000"
                }
                """
            )
        }
        let api = URLSessionGitHubIssuesAPI(
            client: GitHubRESTClient(session: makeStubSession()),
            repositoryFullName: "GitMate/mac-client"
        )

        _ = try await api.updateLabel(
            name: "needs/triage",
            input: IssueLabelInput(
                name: "needs/triage",
                color: "ff0000",
                description: nil
            ),
            token: "secret"
        )
        try await api.deleteLabel(name: "needs/triage", token: "secret")

        try expect(
            recorder.snapshot.allSatisfy {
                $0.url?.absoluteString.contains("/labels/needs%2Ftriage") == true
            },
            "标签名中的斜杠不得改变 REST 路由层级"
        )
    },
    TestCase("标签使用统计排除拉取请求并区分议题状态") {
        URLProtocolStub.handler = { request in
            try stubResponse(
                for: request,
                body: """
                [
                  {
                    "id": 1,
                    "number": 91,
                    "title": "打开议题",
                    "state": "open",
                    "user": {"login": "lele"},
                    "labels": [
                      {"id": 10, "name": "bug", "color": "ff0000"},
                      {"id": 11, "name": "macOS", "color": "0000ff"}
                    ]
                  },
                  {
                    "id": 2,
                    "number": 92,
                    "title": "关闭议题",
                    "state": "closed",
                    "user": {"login": "lele"},
                    "labels": [
                      {"id": 10, "name": "bug", "color": "ff0000"}
                    ]
                  },
                  {
                    "id": 3,
                    "number": 214,
                    "title": "拉取请求",
                    "state": "open",
                    "user": {"login": "lele"},
                    "labels": [
                      {"id": 10, "name": "bug", "color": "ff0000"}
                    ],
                    "pull_request": {}
                  }
                ]
                """
            )
        }
        let api = URLSessionGitHubIssuesAPI(
            client: GitHubRESTClient(session: makeStubSession()),
            repositoryFullName: "GitMate/mac-client"
        )

        let usage = try await api.labelUsage(token: "secret")

        try expectEqual(
            usage["bug"],
            IssueLabelUsage(openIssueCount: 1, closedIssueCount: 1),
            "标签统计应只计算议题并区分状态"
        )
        try expectEqual(
            usage["macOS"],
            IssueLabelUsage(openIssueCount: 1, closedIssueCount: 0),
            "单个打开议题应计入进行中使用数"
        )
    },
    TestCase("议题详情时间线和评论使用真实端点") {
        let recorder = LockedRecorder<URLRequest>()
        URLProtocolStub.handler = { request in
            recorder.append(request)
            let path = request.url?.path ?? ""
            if path.hasSuffix("/timeline") {
                return try stubResponse(
                    for: request,
                    body: """
                    [{
                      "id": 700,
                      "event": "closed",
                      "actor": {"login": "lele"},
                      "created_at": "2026-07-28T09:00:00Z"
                    }]
                    """
                )
            }
            if path.hasSuffix("/comments") {
                return try stubResponse(
                    for: request,
                    body: """
                    [{
                      "id": 500,
                      "body": "我来处理",
                      "user": {"login": "lele"},
                      "created_at": "2026-07-28T08:30:00Z",
                      "updated_at": "2026-07-28T08:30:00Z",
                      "html_url": "https://github.com/GitMate/mac-client/issues/91#issuecomment-500"
                    }]
                    """
                )
            }
            return try stubResponse(
                for: request,
                body: """
                {
                  "id": 1,
                  "number": 91,
                  "title": "网络恢复异常",
                  "body": "正文",
                  "state": "open",
                  "user": {"login": "lele"},
                  "assignees": [],
                  "labels": [],
                  "comments": 1,
                  "locked": false,
                  "created_at": "2026-07-20T08:30:00Z",
                  "updated_at": "2026-07-28T08:30:00Z",
                  "html_url": "https://github.com/GitMate/mac-client/issues/91"
                }
                """
            )
        }
        let api = URLSessionGitHubIssuesAPI(
            client: GitHubRESTClient(session: makeStubSession()),
            repositoryFullName: "GitMate/mac-client"
        )

        let issue = try await api.issue(number: 91, token: "secret")
        let timeline = try await api.timeline(number: 91, token: "secret")
        let comments = try await api.comments(number: 91, token: "secret")

        try expectEqual(issue.number, 91, "应解析议题详情")
        try expectEqual(timeline.map(\.kind), [.closed], "应解析时间线事件")
        try expectEqual(comments.first?.body, "我来处理", "应解析评论")
        let paths = recorder.snapshot.compactMap(\.url?.path)
        try expect(paths.contains("/repos/GitMate/mac-client/issues/91"), "应请求详情")
        try expect(paths.contains("/repos/GitMate/mac-client/issues/91/timeline"), "应请求时间线")
        try expect(paths.contains("/repos/GitMate/mac-client/issues/91/comments"), "应请求评论")
    },
    TestCase("议题评论和锁定写操作使用结构化请求") {
        let recorder = LockedRecorder<URLRequest>()
        URLProtocolStub.handler = { request in
            recorder.append(request)
            let path = request.url?.path ?? ""
            if path.hasSuffix("/lock") {
                return try stubResponse(for: request, statusCode: 204, body: "")
            }
            if path.contains("/comments") {
                return try stubResponse(
                    for: request,
                    body: """
                    {
                      "id": 500,
                      "body": "更新后的评论",
                      "user": {"login": "lele"},
                      "created_at": "2026-07-28T08:30:00Z",
                      "updated_at": "2026-07-28T09:30:00Z",
                      "html_url": "https://github.com/GitMate/mac-client/issues/91#issuecomment-500"
                    }
                    """
                )
            }
            return try stubResponse(
                for: request,
                body: """
                {
                  "id": 1,
                  "number": 91,
                  "title": "网络恢复异常",
                  "body": "更新正文",
                  "state": "closed",
                  "user": {"login": "lele"},
                  "assignees": [],
                  "labels": [],
                  "comments": 1,
                  "locked": false,
                  "created_at": "2026-07-20T08:30:00Z",
                  "updated_at": "2026-07-28T09:30:00Z",
                  "html_url": "https://github.com/GitMate/mac-client/issues/91"
                }
                """
            )
        }
        let api = URLSessionGitHubIssuesAPI(
            client: GitHubRESTClient(session: makeStubSession()),
            repositoryFullName: "GitMate/mac-client"
        )
        let createInput = CreateIssueInput(
            title: "网络恢复异常",
            body: "正文",
            assigneeLogins: ["lele"],
            labelNames: ["bug"],
            milestoneNumber: 2
        )
        let updateInput = UpdateIssueInput(
            title: "网络恢复异常",
            body: "更新正文",
            state: .closed,
            assigneeLogins: [],
            labelNames: [],
            milestoneNumber: nil
        )

        _ = try await api.createIssue(createInput, token: "secret")
        _ = try await api.updateIssue(number: 91, input: updateInput, token: "secret")
        _ = try await api.createComment(number: 91, body: "开始处理", token: "secret")
        _ = try await api.updateComment(id: 500, body: "更新后的评论", token: "secret")
        try await api.lockIssue(number: 91, reason: .resolved, token: "secret")
        try await api.unlockIssue(number: 91, token: "secret")

        let requests = recorder.snapshot
        try expect(requests.contains {
            $0.httpMethod == "POST"
                && $0.url?.path == "/repos/GitMate/mac-client/issues"
        }, "应创建议题")
        let patch = try requests.first(where: {
            $0.httpMethod == "PATCH"
                && $0.url?.path == "/repos/GitMate/mac-client/issues/91"
        }) ?? {
            throw TestFailure(description: "应更新议题")
        }()
        let patchData = try requestBodyData(patch) ?? {
            throw TestFailure(description: "议题更新应包含负载")
        }()
        let patchBody = try JSONSerialization.jsonObject(with: patchData) as? [String: Any]
        try expectEqual(patchBody?["state"] as? String, "closed", "应编码关闭状态")
        try expect(patchBody?["milestone"] is NSNull, "清空里程碑必须显式发送 null")
        try expect(requests.contains {
            $0.httpMethod == "POST"
                && $0.url?.path == "/repos/GitMate/mac-client/issues/91/comments"
        }, "应创建评论")
        try expect(requests.contains {
            $0.httpMethod == "PATCH"
                && $0.url?.path == "/repos/GitMate/mac-client/issues/comments/500"
        }, "应更新精确评论")
        try expect(requests.contains {
            $0.httpMethod == "PUT"
                && $0.url?.path == "/repos/GitMate/mac-client/issues/91/lock"
        }, "应锁定议题")
        try expect(requests.contains {
            $0.httpMethod == "DELETE"
                && $0.url?.path == "/repos/GitMate/mac-client/issues/91/lock"
        }, "应解锁议题")
    },
    TestCase("里程碑与标签 CRUD 使用精确资源路径") {
        let recorder = LockedRecorder<URLRequest>()
        URLProtocolStub.handler = { request in
            recorder.append(request)
            let path = request.url?.path ?? ""
            if request.httpMethod == "DELETE" {
                return try stubResponse(for: request, statusCode: 204, body: "")
            }
            if path.contains("/milestones") {
                return try stubResponse(
                    for: request,
                    body: """
                    {
                      "id": 11,
                      "number": 2,
                      "title": "v2.5",
                      "description": "稳定性",
                      "state": "open",
                      "open_issues": 3,
                      "closed_issues": 7,
                      "created_at": "2026-07-01T08:00:00Z",
                      "updated_at": "2026-07-28T08:00:00Z",
                      "html_url": "https://github.com/GitMate/mac-client/milestone/2"
                    }
                    """
                )
            }
            return try stubResponse(
                for: request,
                body: """
                {
                  "id": 21,
                  "name": "bug",
                  "color": "d73a4a",
                  "description": "错误",
                  "default": true
                }
                """
            )
        }
        let api = URLSessionGitHubIssuesAPI(
            client: GitHubRESTClient(session: makeStubSession()),
            repositoryFullName: "GitMate/mac-client"
        )
        let milestone = MilestoneInput(
            title: "v2.5",
            description: "稳定性",
            state: .open,
            dueOn: nil
        )
        let label = IssueLabelInput(name: "bug", color: "D73A4A", description: "错误")

        _ = try await api.createMilestone(milestone, token: "secret")
        _ = try await api.updateMilestone(number: 2, input: milestone, token: "secret")
        try await api.deleteMilestone(number: 2, token: "secret")
        _ = try await api.createLabel(label, token: "secret")
        _ = try await api.updateLabel(name: "bug", input: label, token: "secret")
        try await api.deleteLabel(name: "bug", token: "secret")

        let requests = recorder.snapshot
        try expect(requests.contains {
            $0.httpMethod == "DELETE"
                && $0.url?.path == "/repos/GitMate/mac-client/milestones/2"
        }, "里程碑删除必须使用编号")
        try expect(requests.contains {
            $0.httpMethod == "PATCH"
                && $0.url?.path == "/repos/GitMate/mac-client/labels/bug"
        }, "标签更新必须使用原标签名")
        try expect(requests.contains {
            $0.httpMethod == "DELETE"
                && $0.url?.path == "/repos/GitMate/mac-client/labels/bug"
        }, "标签删除必须使用精确名称")
    }
]
