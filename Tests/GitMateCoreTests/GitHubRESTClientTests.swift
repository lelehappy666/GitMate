import Foundation
import GitMateCore

private struct RESTFixtureResponse: Decodable, Equatable {
    let value: String
}

private struct RESTFixtureItem: Decodable, Equatable, Sendable {
    let id: Int
}

let githubRESTClientTests = [
    TestCase("REST 客户端构建认证版本与 JSON 请求") {
        let recorder = LockedRecorder<URLRequest>()
        URLProtocolStub.handler = { request in
            recorder.append(request)
            return try stubResponse(for: request, body: #"{"value":"ok"}"#)
        }
        let client = GitHubRESTClient(session: makeStubSession())
        let request = try GitHubRequest(
            method: .post,
            path: "/repos/GitMate/mac-client/issues",
            queryItems: [URLQueryItem(name: "per_page", value: "100")],
            encodableBody: ["title": "网络恢复异常"]
        )

        let response: RESTFixtureResponse = try await client.send(request, token: "secret")
        let recorded = try recorder.snapshot.first ?? {
            throw TestFailure(description: "应发送 REST 请求")
        }()

        try expectEqual(response.value, "ok", "应解码 JSON 响应")
        try expectEqual(recorded.httpMethod, "POST", "应保留 HTTP 方法")
        try expectEqual(recorded.url?.path, "/repos/GitMate/mac-client/issues", "应拼接 API 路径")
        try expectEqual(recorded.url?.query, "per_page=100", "应编码查询参数")
        try expectEqual(
            recorded.value(forHTTPHeaderField: "Authorization"),
            "Bearer secret",
            "应添加 Bearer 认证"
        )
        try expectEqual(
            recorded.value(forHTTPHeaderField: "X-GitHub-Api-Version"),
            "2022-11-28",
            "应固定 GitHub API 版本"
        )
        try expectEqual(
            recorded.value(forHTTPHeaderField: "Content-Type"),
            "application/json",
            "JSON 请求应声明内容类型"
        )
        let body = try requestBodyData(recorded) ?? {
            throw TestFailure(description: "应发送 JSON 请求体")
        }()
        let object = try JSONSerialization.jsonObject(with: body) as? [String: String]
        try expectEqual(object?["title"], "网络恢复异常", "应编码请求负载")
    },
    TestCase("REST 分页响应解析下一页链接") {
        URLProtocolStub.handler = { request in
            try stubResponse(
                for: request,
                headers: [
                    "Link": "<https://api.github.com/repositories?page=2>; rel=\"next\", <https://api.github.com/repositories?page=5>; rel=\"last\""
                ],
                body: #"[{"id":1}]"#
            )
        }
        let client = GitHubRESTClient(session: makeStubSession())

        let page: GitHubPage<RESTFixtureItem> = try await client.sendPage(
            GitHubRequest(method: .get, path: "/repositories"),
            token: "secret"
        )

        try expectEqual(page.items, [RESTFixtureItem(id: 1)], "应解码当前页项目")
        try expectEqual(
            page.nextPageURL?.absoluteString,
            "https://api.github.com/repositories?page=2",
            "应只读取 rel=next 链接"
        )
    },
    TestCase("REST 客户端接受 204 空响应") {
        URLProtocolStub.handler = { request in
            try stubResponse(for: request, statusCode: 204, body: "")
        }
        let client = GitHubRESTClient(session: makeStubSession())

        try await client.sendWithoutResponse(
            GitHubRequest(method: .delete, path: "/repos/GitMate/mac-client/issues/91/lock"),
            token: "secret"
        )
    },
    TestCase("REST 客户端把 422 映射为字段验证错误") {
        URLProtocolStub.handler = { request in
            try stubResponse(
                for: request,
                statusCode: 422,
                body: """
                {
                  "message": "Validation Failed",
                  "errors": [
                    {"resource": "Issue", "field": "title", "code": "missing_field"}
                  ]
                }
                """
            )
        }
        let client = GitHubRESTClient(session: makeStubSession())

        do {
            let _: RESTFixtureResponse = try await client.send(
                GitHubRequest(method: .post, path: "/repos/GitMate/mac-client/issues"),
                token: "secret"
            )
            throw TestFailure(description: "422 不应被视为成功")
        } catch let GitHubAPIError.validationFailed(message, fields) {
            try expectEqual(message, "Validation Failed", "应保留验证错误摘要")
            try expectEqual(fields, ["title"], "应提取出错字段")
        }
    },
    TestCase("REST 客户端区分权限不足与速率限制") {
        let responses = StubResponseQueue([
            #"{"message":"API rate limit exceeded"}"#,
            #"{"message":"Resource not accessible by personal access token"}"#
        ])
        let requestCount = LockedRecorder<Int>()
        URLProtocolStub.handler = { request in
            let index = requestCount.snapshot.count
            requestCount.append(index)
            let headers = index == 0
                ? ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1785312000"]
                : [:]
            return try stubResponse(
                for: request,
                statusCode: 403,
                headers: headers,
                body: responses.next()
            )
        }
        let client = GitHubRESTClient(session: makeStubSession())
        let request = GitHubRequest(method: .get, path: "/user")

        do {
            let _: RESTFixtureResponse = try await client.send(request, token: "secret")
            throw TestFailure(description: "速率限制不应被视为成功")
        } catch let GitHubAPIError.rateLimited(resetAt, message) {
            try expect(resetAt != nil, "应解析速率限制重置时间")
            try expectEqual(message, "API rate limit exceeded", "应保留速率限制说明")
        }

        do {
            let _: RESTFixtureResponse = try await client.send(request, token: "secret")
            throw TestFailure(description: "权限不足不应被视为成功")
        } catch let GitHubAPIError.forbidden(message) {
            try expectEqual(
                message,
                "Resource not accessible by personal access token",
                "应保留权限不足说明"
            )
        }
    },
    TestCase("REST 客户端区分不存在与写入冲突") {
        let statusCodes = LockedRecorder<Int>()
        URLProtocolStub.handler = { request in
            let statusCode = statusCodes.snapshot.isEmpty ? 404 : 409
            statusCodes.append(statusCode)
            let message = statusCode == 404 ? "Not Found" : "Update is not a fast forward"
            return try stubResponse(
                for: request,
                statusCode: statusCode,
                body: #"{"message":"\#(message)"}"#
            )
        }
        let client = GitHubRESTClient(session: makeStubSession())
        let request = GitHubRequest(method: .get, path: "/repos/GitMate/mac-client")

        do {
            let _: RESTFixtureResponse = try await client.send(request, token: "secret")
            throw TestFailure(description: "404 不应被视为成功")
        } catch let GitHubAPIError.notFound(message) {
            try expectEqual(message, "Not Found", "应保留不存在说明")
        }

        do {
            let _: RESTFixtureResponse = try await client.send(request, token: "secret")
            throw TestFailure(description: "409 不应被视为成功")
        } catch let GitHubAPIError.conflict(message) {
            try expectEqual(message, "Update is not a fast forward", "应保留冲突说明")
        }
    }
]
