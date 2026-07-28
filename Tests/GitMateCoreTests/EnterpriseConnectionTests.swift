import Foundation
import GitMateCore

let enterpriseConnectionTests = [
    TestCase("企业 GitHub 地址自动补全 API 路径") {
        let endpoint = try EnterpriseEndpoint(
            serverURL: URL(string: "https://github.company.com")!
        )

        try expectEqual(
            endpoint.serverURL.absoluteString,
            "https://github.company.com/",
            "企业服务器地址应标准化"
        )
        try expectEqual(
            endpoint.apiBaseURL.absoluteString,
            "https://github.company.com/api/v3/",
            "企业 API 应使用 /api/v3/"
        )
    },
    TestCase("企业 GitHub 默认拒绝不安全连接") {
        do {
            _ = try EnterpriseEndpoint(
                serverURL: URL(string: "http://github.company.com")!
            )
            throw TestFailure(description: "非 HTTPS 企业地址不应通过验证")
        } catch EnterpriseConnectionError.insecureServerURL {
            // 预期错误。
        }
    },
    TestCase("企业令牌验证返回真实用户账户") {
        let requests = LockedRecorder<URLRequest>()
        URLProtocolStub.handler = { request in
            requests.append(request)
            return try stubResponse(
                for: request,
                headers: ["X-OAuth-Scopes": "repo, read:user"],
                body: """
                {
                  "id": 8,
                  "login": "enterprise-user",
                  "name": "企业用户",
                  "avatar_url": "https://github.company.com/avatars/u/8"
                }
                """
            )
        }
        let service = EnterpriseConnectionService(session: makeStubSession())

        let account = try await service.verify(
            serverURL: URL(string: "https://github.company.com")!,
            token: "enterprise-token"
        )

        try expectEqual(account.kind, .enterprise, "应标记为企业账户")
        try expectEqual(account.serverURL.absoluteString, "https://github.company.com/", "应保存企业服务器地址")
        try expectEqual(requests.snapshot.first?.url?.path, "/api/v3/user", "应请求企业 API 用户端点")
    },
    TestCase("企业令牌失效映射为重新授权状态") {
        URLProtocolStub.handler = { request in
            try stubResponse(
                for: request,
                statusCode: 401,
                body: #"{"message":"Bad credentials"}"#
            )
        }
        let service = EnterpriseConnectionService(session: makeStubSession())

        do {
            _ = try await service.verify(
                serverURL: URL(string: "https://github.company.com")!,
                token: "expired"
            )
            throw TestFailure(description: "失效令牌不应通过验证")
        } catch EnterpriseConnectionError.authorizationExpired {
            // 预期错误。
        }
    }
]
