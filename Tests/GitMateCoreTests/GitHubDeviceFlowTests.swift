import Foundation
import GitMateCore

let githubDeviceFlowTests = [
    TestCase("设备授权请求包含客户端编号与权限范围") {
        let requests = LockedRecorder<URLRequest>()
        URLProtocolStub.handler = { request in
            requests.append(request)
            return try stubResponse(
                for: request,
                body: """
                {
                  "device_code": "device-code",
                  "user_code": "ABCD-EFGH",
                  "verification_uri": "https://github.com/login/device",
                  "expires_in": 900,
                  "interval": 5
                }
                """
            )
        }

        let flow = GitHubDeviceFlow(
            clientID: "client-id",
            scopes: ["repo", "read:user"],
            session: makeStubSession(),
            sleeper: { _ in }
        )
        let code = try await flow.start()
        let request = requests.snapshot.first
        let body = request
            .flatMap(requestBodyData)
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""

        try expectEqual(code.userCode, "ABCD-EFGH", "应解析用户验证码")
        try expectEqual(request?.url?.path, "/login/device/code", "应调用设备授权地址")
        try expectEqual(request?.httpMethod, "POST", "设备授权应使用 POST")
        try expect(body.contains("client_id=client-id"), "请求体应包含客户端编号")
        try expect(body.contains("scope=repo%20read:user"), "请求体应包含权限范围")
    },
    TestCase("设备授权轮询处理等待与降速后返回令牌") {
        let requests = LockedRecorder<URLRequest>()
        let delays = LockedRecorder<Int>()
        let responses = StubResponseQueue([
            #"{"error":"authorization_pending"}"#,
            #"{"error":"slow_down","interval":2}"#,
            #"{"access_token":"secret","token_type":"bearer","scope":"repo,read:user"}"#
        ])

        URLProtocolStub.handler = { request in
            requests.append(request)
            return try stubResponse(for: request, body: responses.next())
        }

        let flow = GitHubDeviceFlow(
            clientID: "client-id",
            scopes: ["repo"],
            session: makeStubSession(),
            sleeper: { seconds in
                delays.append(seconds)
            }
        )
        let token = try await flow.poll(deviceCode: "device-code", interval: 1)

        try expectEqual(token.accessToken, "secret", "轮询成功后应返回访问令牌")
        try expectEqual(requests.snapshot.count, 3, "等待授权期间应继续轮询")
        try expectEqual(delays.snapshot, [1, 1, 3], "slow_down 应增加后续轮询间隔")
    },
    TestCase("设备授权拒绝时返回明确错误") {
        URLProtocolStub.handler = { request in
            try stubResponse(for: request, body: #"{"error":"access_denied"}"#)
        }
        let flow = GitHubDeviceFlow(
            clientID: "client-id",
            scopes: ["repo"],
            session: makeStubSession(),
            sleeper: { _ in }
        )

        do {
            _ = try await flow.poll(deviceCode: "device-code", interval: 1)
            throw TestFailure(description: "用户拒绝授权时不应返回令牌")
        } catch GitHubAPIError.accessDenied {
            // 预期错误。
        }
    }
]
