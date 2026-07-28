import Foundation
import GitMateCore

let githubAPITests = [
    TestCase("GitHub API 解析用户头像与账户权限") {
        let recorder = LockedRecorder<URLRequest>()
        URLProtocolStub.handler = { request in
            recorder.append(request)
            return try stubResponse(
                for: request,
                headers: ["X-OAuth-Scopes": "repo, read:user"],
                body: """
                {
                  "id": 1,
                  "login": "lele",
                  "name": "Lele",
                  "avatar_url": "https://avatars.githubusercontent.com/u/1"
                }
                """
            )
        }
        let api = URLSessionGitHubAPI(session: makeStubSession())

        let account = try await api.currentUser(token: "secret")
        let request = recorder.snapshot.first

        try expectEqual(account.login, "lele", "应解析账户名")
        try expectEqual(account.avatarURL?.absoluteString, "https://avatars.githubusercontent.com/u/1", "应使用真实 GitHub 头像")
        try expectEqual(account.scopes, ["repo", "read:user"], "应解析令牌权限")
        try expectEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer secret", "应附带 Bearer 令牌")
        try expectEqual(request?.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28", "应固定 API 版本")
    },
    TestCase("GitHub API 解析仓库大小和同步所需字段") {
        URLProtocolStub.handler = { request in
            try stubResponse(
                for: request,
                body: """
                [{
                  "id": 101,
                  "name": "mac-client",
                  "full_name": "GitMate/mac-client",
                  "private": true,
                  "default_branch": "main",
                  "size": 2457600,
                  "clone_url": "https://github.com/GitMate/mac-client.git",
                  "owner": {
                    "avatar_url": "https://avatars.githubusercontent.com/u/1"
                  }
                }]
                """
            )
        }
        let api = URLSessionGitHubAPI(session: makeStubSession())

        let repositories = try await api.repositories(token: "secret")
        let repository = try repositories.first ?? {
            throw TestFailure(description: "应返回仓库")
        }()

        try expectEqual(repository.sizeInKilobytes, 2_457_600, "应保留 GitHub 返回的仓库大小")
        try expect(repository.isPrivate, "应解析私有仓库状态")
        try expectEqual(repository.defaultBranch, "main", "应解析默认分支")
        try expectEqual(repository.cloneURL.absoluteString, "https://github.com/GitMate/mac-client.git", "应解析克隆地址")
        try expectEqual(repository.ownerAvatarURL?.absoluteString, "https://avatars.githubusercontent.com/u/1", "应解析仓库所有者头像")
    },
    TestCase("GitHub API 错误响应包含状态码") {
        URLProtocolStub.handler = { request in
            try stubResponse(
                for: request,
                statusCode: 401,
                body: #"{"message":"Bad credentials"}"#
            )
        }
        let api = URLSessionGitHubAPI(session: makeStubSession())

        do {
            _ = try await api.currentUser(token: "expired")
            throw TestFailure(description: "401 响应不应被视为成功")
        } catch let GitHubAPIError.httpStatus(statusCode, message) {
            try expectEqual(statusCode, 401, "应保留 HTTP 状态码")
            try expectEqual(message, "Bad credentials", "应解析 GitHub 错误说明")
        }
    }
]
