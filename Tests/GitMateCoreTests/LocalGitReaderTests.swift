import Foundation
@testable import GitMateCore

private let commitRecord = """
a81c32f\u{1f}a81c32ffull\u{1f}修复同步索引\u{1f}lele\u{1f}lele@example.com\u{1f}2026-07-29T10:00:00Z\u{1f}8e1d04a 742fd81\u{1f}HEAD -> main, tag: v1.0\u{1e}
"""

private let showOutput = """
a81c32f\u{1f}a81c32ffull\u{1f}修复同步索引\u{1f}lele\u{1f}lele@example.com\u{1f}2026-07-29T10:00:00Z\u{1f}8e1d04a\u{1f}HEAD -> main\u{1f}完整提交消息
第二行\u{1f}G\u{1f}Lele Zhang\u{1e}

2\t1\tSources/App.swift
-\t-\tAssets/logo.png
diff --git a/Sources/App.swift b/Sources/App.swift
--- a/Sources/App.swift
+++ b/Sources/App.swift
@@ -1 +1,2 @@
 line
+new
"""

private let commitDetailOutput = """
a81c32f\u{0}a81c32ffull\u{0}修复同步索引\u{0}lele\u{0}lele@example.com\u{0}2026-07-29T10:00:00Z\u{0}8e1d04a\u{0}HEAD -> main\u{0}G\u{0}Lele Zhang\u{0}完整提交消息
第二行\u{1f}\u{1e}
\u{0}
"""

private let diffOutput = """
a81c32ffull\u{0}

2\t1\tSources/App.swift
-\t-\tAssets/logo.png
diff --git a/Sources/App.swift b/Sources/App.swift
--- a/Sources/App.swift
+++ b/Sources/App.swift
@@ -1 +1,2 @@
 line
+new
"""

private func expectedInvocation(
    _ arguments: [String]
) -> FakeCommandExecutor.ExpectedInvocation {
    .init(arguments: arguments, environment: [:])
}

private struct RealGitFixture: Sendable {
    let repositoryURL: URL
    let binaryData: Data
    let whitespaceText: String
    let commitMessage: String
}

private final class PipeReadTestState: @unchecked Sendable {
    let handlerStarted = DispatchSemaphore(value: 0)
    let releaseHandler = DispatchSemaphore(value: 0)
    let handlerFinished = DispatchSemaphore(value: 0)
    let drainFinished = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var captured = Data()

    func holdAndAppend(_ data: Data) {
        handlerStarted.signal()
        _ = releaseHandler.wait(timeout: .now() + 2)
        append(data)
        handlerFinished.signal()
    }

    func append(_ data: Data) {
        lock.lock()
        captured.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }
}

private func makeRealGitFixture() throws -> RealGitFixture {
    let repositoryURL = FileManager.default.temporaryDirectory
        .appending(
            path: "GitMateLocalGit-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    try FileManager.default.createDirectory(
        at: repositoryURL,
        withIntermediateDirectories: true
    )

    try runGitSetup(
        ["init", "--quiet", "--initial-branch=main"],
        repositoryURL: repositoryURL
    )
    try runGitSetup(
        ["config", "user.name", "GitMate Tests"],
        repositoryURL: repositoryURL
    )
    try runGitSetup(
        ["config", "user.email", "gitmate-tests@example.com"],
        repositoryURL: repositoryURL
    )
    var binaryData = Data()
    for _ in 0..<32_768 {
        binaryData.append(contentsOf: [0x00, 0xFF, 0x41, 0x0A])
    }
    binaryData.append(0x7E)
    let whitespaceText = "  前导空白\n\n尾随空白  \n"
    try binaryData.write(
        to: repositoryURL.appending(path: "binary.dat")
    )
    try Data(whitespaceText.utf8).write(
        to: repositoryURL.appending(path: "Whitespace.txt")
    )
    let sourcesURL = repositoryURL.appending(
        path: "Sources",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
        at: sourcesURL,
        withIntermediateDirectories: true
    )
    try Data("let value = 1\n".utf8).write(
        to: sourcesURL.appending(path: "App.swift")
    )
    try Data("line\n".utf8).write(
        to: repositoryURL.appending(path: "Patch.txt")
    )
    try runGitSetup(["add", "."], repositoryURL: repositoryURL)
    try runGitSetup(
        ["commit", "--quiet", "-m", "初始提交"],
        repositoryURL: repositoryURL
    )

    try Data("line\n  前导新增\n\n结尾\n".utf8).write(
        to: repositoryURL.appending(path: "Patch.txt")
    )
    let commitMessage =
        "无损提交\n\n字段\u{1f}内容\n记录\u{1e}内容\n\n  缩进行\n"
    let messageURL = repositoryURL.appending(
        path: ".git/gitmate-test-message"
    )
    try Data(commitMessage.utf8).write(to: messageURL)
    try runGitSetup(["add", "Patch.txt"], repositoryURL: repositoryURL)
    try runGitSetup(
        [
            "commit", "--quiet", "--cleanup=verbatim",
            "-F", messageURL.path
        ],
        repositoryURL: repositoryURL
    )

    return RealGitFixture(
        repositoryURL: repositoryURL,
        binaryData: binaryData,
        whitespaceText: whitespaceText,
        commitMessage: commitMessage
    )
}

private func runGitSetup(
    _ arguments: [String],
    repositoryURL: URL
) throws {
    let process = Process()
    let standardError = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", repositoryURL.path] + arguments
    process.standardError = standardError
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        throw TestFailure(
            description: String(decoding: errorData, as: UTF8.self)
        )
    }
}

let localGitReaderTests = [
    TestCase("提交解析保留作者头像关联字段和父提交") {
        let data = """
        a81c32f\u{1f}a81c32ffull\u{1f}修复同步索引\u{1f}lele\u{1f}lele@example.com\u{1f}2026-07-29T10:00:00Z\u{1f}8e1d04a 742fd81\u{1e}
        """

        let commits = try GitOutputParser.parseCommits(data)

        try expectEqual(commits[0].shortHash, "a81c32f", "应解析短哈希")
        try expectEqual(
            commits[0].parentHashes,
            ["8e1d04a", "742fd81"],
            "应解析多个父提交"
        )
        try expectEqual(
            commits[0].authorEmail,
            "lele@example.com",
            "应保留作者邮箱用于头像关联"
        )
    },
    TestCase("文件树拒绝逃逸路径") {
        let entries = try GitOutputParser.parseTree(
            "100644 blob abc 12\tREADME.md\u{0}"
                + "100644 blob def 6\tnested/../secret\u{0}"
        )

        try expectEqual(entries.map(\.path), ["README.md"], "路径逃逸项不得进入文件树")
    },
    TestCase("提交解析兼容装饰字段并拒绝畸形日期") {
        let commits = try GitOutputParser.parseCommits(commitRecord)

        try expectEqual(
            commits[0].decorations,
            ["HEAD -> main", "tag: v1.0"],
            "第八字段应解析为装饰列表"
        )

        do {
            _ = try GitOutputParser.parseCommits(
                "a\u{1f}b\u{1f}c\u{1f}d\u{1f}e\u{1f}非日期\u{1f}\u{1e}"
            )
            throw TestFailure(description: "畸形提交日期必须被拒绝")
        } catch is GitOutputParsingError {
            // 预期路径
        }
    },
    TestCase("文件树解析四种类型与大小并拒绝畸形记录") {
        let output = [
            "100644 blob a1 12\tREADME.md",
            "040000 tree b2 -\tSources",
            "160000 commit c3 -\tVendor/SDK",
            "120000 blob d4 8\tcurrent"
        ].joined(separator: "\u{0}") + "\u{0}"

        let entries = try GitOutputParser.parseTree(output)

        try expectEqual(
            entries.map(\.kind),
            [.file, .directory, .submodule, .symlink],
            "mode 与 type 应映射为四种文件类型"
        )
        try expectEqual(
            entries.map(\.byteCount),
            [12, nil, nil, 8],
            "短横线大小应解析为 nil"
        )

        do {
            _ = try GitOutputParser.parseTree("100644 blob missing-tab\u{0}")
            throw TestFailure(description: "畸形文件树记录必须被拒绝")
        } catch is GitOutputParsingError {
            // 预期路径
        }
    },
    TestCase("状态解析分支领先落后与工作区计数") {
        let output = [
            "# branch.oid a81c32f",
            "# branch.head main",
            "# branch.upstream origin/main",
            "# branch.ab +3 -2",
            "1 M. N... 100644 100644 100644 a1 b1 staged.swift",
            "1 .M N... 100644 100644 100644 a2 b2 unstaged.swift",
            "2 R. N... 100644 100644 100644 a3 b3 R100 renamed.swift",
            "old.swift",
            "? notes.txt",
            "u UU N... 100644 100644 100644 100644 a4 b4 c4 conflict.swift",
            "! ignored.tmp",
            "x unknown"
        ].joined(separator: "\u{0}") + "\u{0}"

        let status = try GitOutputParser.parseStatus(output)

        try expectEqual(status.branch, "main", "应解析当前分支")
        try expectEqual(status.upstream, "origin/main", "应解析上游分支")
        try expectEqual(status.ahead, 3, "应解析领先提交数")
        try expectEqual(status.behind, 2, "应解析落后提交数")
        try expectEqual(status.stagedCount, 2, "应统计暂存与重命名记录")
        try expectEqual(status.unstagedCount, 1, "应统计未暂存记录")
        try expectEqual(status.untrackedCount, 1, "应统计未跟踪记录")
        try expectEqual(status.conflictCount, 1, "应统计冲突记录")
    },
    TestCase("状态解析拒绝畸形领先落后字段") {
        do {
            _ = try GitOutputParser.parseStatus("# branch.ab +x -2\u{0}")
            throw TestFailure(description: "畸形领先落后字段必须被拒绝")
        } catch is GitOutputParsingError {
            // 预期路径
        }
    },
    TestCase("type-2 重命名原路径不得被误计为状态记录") {
        let output = [
            "2 R. N... 100644 100644 100644 a1 b1 R100 first.swift",
            "? old-untracked.swift",
            "2 R. N... 100644 100644 100644 a2 b2 R100 second.swift",
            "u old-conflict.swift",
            "2 R. N... 100644 100644 100644 a3 b3 R100 third.swift",
            "1 old-ordinary.swift"
        ].joined(separator: "\u{0}") + "\u{0}"

        let status = try GitOutputParser.parseStatus(output)

        try expectEqual(status.stagedCount, 3, "只应统计三个 type-2 新路径记录")
        try expectEqual(status.unstagedCount, 0, "原路径不得增加未暂存计数")
        try expectEqual(status.untrackedCount, 0, "? 开头原路径不得计为未跟踪")
        try expectEqual(status.conflictCount, 0, "u 开头原路径不得计为冲突")
    },
    TestCase("提交详情和差异按记录边界分离") {
        let parsed = try GitOutputParser.parseShow(showOutput)

        try expectEqual(parsed.detail.commit.fullHash, "a81c32ffull", "应解析完整提交哈希")
        try expectEqual(parsed.detail.message, "完整提交消息\n第二行", "应保留完整提交消息")
        try expectEqual(parsed.detail.signatureStatus, .verified, "G 签名应标记已验证")
        try expectEqual(parsed.detail.signer, "Lele Zhang", "应保留签名人")
        try expectEqual(
            parsed.diff.files,
            [
                GitChangedFile(
                    path: "Sources/App.swift",
                    additions: 2,
                    deletions: 1,
                    isBinary: false
                ),
                GitChangedFile(
                    path: "Assets/logo.png",
                    additions: nil,
                    deletions: nil,
                    isBinary: true
                )
            ],
            "numstat 应解析文本和二进制文件"
        )
        try expectEqual(parsed.diff.additions, 2, "应汇总新增行")
        try expectEqual(parsed.diff.deletions, 1, "应汇总删除行")
        try expect(
            parsed.diff.patch.hasPrefix("diff --git a/Sources/App.swift"),
            "patch 应从 diff --git 开始"
        )
    },
    TestCase("提交详情拒绝缺少记录边界的输出") {
        do {
            _ = try GitOutputParser.parseShow("没有记录分隔符")
            throw TestFailure(description: "缺少元数据边界必须被拒绝")
        } catch is GitOutputParsingError {
            // 预期路径
        }
    },
    TestCase("提交详情区分未验证与未知签名") {
        let unverified = try GitOutputParser.parseShow(
            showOutput.replacingOccurrences(
                of: "\u{1f}G\u{1f}",
                with: "\u{1f}B\u{1f}"
            )
        )
        let unknown = try GitOutputParser.parseShow(
            showOutput.replacingOccurrences(
                of: "\u{1f}G\u{1f}",
                with: "\u{1f}N\u{1f}"
            )
        )

        try expectEqual(
            unverified.detail.signatureStatus,
            .unverified,
            "B 签名必须标记未验证"
        )
        try expectEqual(
            unknown.detail.signatureStatus,
            .unknown,
            "N 签名必须标记未知"
        )
    },
    TestCase("差异解析拒绝畸形 numstat 行") {
        let malformed = showOutput.replacingOccurrences(
            of: "2\t1\tSources/App.swift",
            with: "不是-numstat"
        )

        do {
            _ = try GitOutputParser.parseShow(malformed)
            throw TestFailure(description: "畸形 numstat 必须被拒绝")
        } catch is GitOutputParsingError {
            // 预期路径
        }
    },
    TestCase("状态读取仅执行只读命令并解析结果") {
        let output = "# branch.head main\u{0}# branch.ab +0 -0\u{0}? README.md\u{0}"
        let executor = FakeCommandExecutor(results: [
            .success([.standardOutput(output)])
        ], expectedInvocations: [
            expectedInvocation([
                "-C", "/tmp/gitmate-repository", "status",
                "--porcelain=v2", "--branch", "-z"
            ])
        ])
        let reader = CommandLocalGitReader(executor: executor)
        let repositoryURL = URL(fileURLWithPath: "/tmp/gitmate-repository")

        let status = try await reader.status(repositoryURL: repositoryURL)

        try expectEqual(
            executor.commands,
            [["-C", "/tmp/gitmate-repository", "status", "--porcelain=v2", "--branch", "-z"]],
            "状态读取命令参数必须精确匹配白名单"
        )
        try expectEqual(executor.environments, [[:]], "本地只读 Git 不应注入环境凭据")
        try expectEqual(status.untrackedCount, 1, "应返回真实解析状态")
        try executor.verifyComplete()
    },
    TestCase("文件树规范化根路径和目录 pathspec 并安全读取文件") {
        let executor = FakeCommandExecutor(results: [
            .success([
                .standardOutput("100644 blob a1 6\tSources/App.swift\u{0}")
            ]),
            .success([
                .standardOutput("100644 blob a2 9\tREADME.md\u{0}")
            ]),
            .success([
                .standardOutput("第一行\n"),
                .standardOutput("第二行")
            ])
        ], expectedInvocations: [
            expectedInvocation([
                "-C", "/tmp/gitmate-repository", "ls-tree", "-z", "-l",
                "refs/heads/main~2", "--", "Sources/"
            ]),
            expectedInvocation([
                "-C", "/tmp/gitmate-repository", "ls-tree", "-z", "-l",
                "main", "--", "."
            ]),
            expectedInvocation([
                "-C", "/tmp/gitmate-repository", "show",
                "main:README.md"
            ])
        ])
        let reader = CommandLocalGitReader(executor: executor)
        let repositoryURL = URL(fileURLWithPath: "/tmp/gitmate-repository")

        let tree = try await reader.tree(
            repositoryURL: repositoryURL,
            revision: "refs/heads/main~2",
            path: "Sources/"
        )
        let rootTree = try await reader.tree(
            repositoryURL: repositoryURL,
            revision: "main",
            path: ""
        )
        let file = try await reader.file(
            repositoryURL: repositoryURL,
            revision: "main",
            path: "README.md"
        )

        try expectEqual(
            executor.commands,
            [
                [
                    "-C", "/tmp/gitmate-repository", "ls-tree", "-z", "-l",
                    "refs/heads/main~2", "--", "Sources/"
                ],
                [
                    "-C", "/tmp/gitmate-repository", "ls-tree", "-z", "-l",
                    "main", "--", "."
                ],
                [
                    "-C", "/tmp/gitmate-repository", "show",
                    "main:README.md"
                ]
            ],
            "文件树与文件内容命令必须精确匹配白名单"
        )
        try expectEqual(tree.map(\.path), ["Sources/App.swift"], "文件树应返回真实解析项")
        try expectEqual(rootTree.map(\.path), ["README.md"], "空路径应读取仓库根目录")
        try expectEqual(file.text, "第一行\n第二行", "多段输出应恢复换行")
        try expectEqual(file.byteCount, 19, "字节数应按 UTF-8 汇总")
        try expect(!file.isBinary, "普通 UTF-8 文件不应标记为二进制")
        try executor.verifyComplete()
    },
    TestCase("含空字节的文件内容标记为二进制") {
        let executor = FakeCommandExecutor(results: [
            .success([.standardOutput("GIF\u{0}89a")])
        ], expectedInvocations: [
            expectedInvocation([
                "-C", "/tmp/gitmate-repository", "show", "main:logo.gif"
            ])
        ])
        let reader = CommandLocalGitReader(executor: executor)

        let file = try await reader.file(
            repositoryURL: URL(fileURLWithPath: "/tmp/gitmate-repository"),
            revision: "main",
            path: "logo.gif"
        )

        try expect(file.isBinary, "含 NUL 的内容必须标记为二进制")
        try expect(file.text == nil, "二进制内容不得暴露为文本")
        try expectEqual(file.data, Data("GIF\u{0}89a".utf8), "应保留 UTF-8 汇总数据")
        try executor.verifyComplete()
    },
    TestCase("无空字节的非 UTF-8 内容标记为无法解码") {
        let rawData = Data([0xFF, 0xFE, 0x41])
        let executor = FakeCommandExecutor(results: [
            .success([.standardOutputData(rawData)])
        ], expectedInvocations: [
            expectedInvocation([
                "-C", "/tmp/gitmate-repository", "show", "main:legacy.txt"
            ])
        ])
        let reader = CommandLocalGitReader(executor: executor)

        let file = try await reader.file(
            repositoryURL: URL(fileURLWithPath: "/tmp/gitmate-repository"),
            revision: "main",
            path: "legacy.txt"
        )

        try expectEqual(
            file.kind,
            .invalidUTF8,
            "无 NUL 且无法解码的内容必须使用独立类型"
        )
        try expect(!file.isBinary, "无法解码文本不得伪装成二进制")
        try expect(file.text == nil, "无法解码内容不得暴露伪文本")
        try expectEqual(file.data, rawData, "原始字节不得丢失")
        try executor.verifyComplete()
    },
    TestCase("提交列表分页命令和游标完全由验证后数值构造") {
        let executor = FakeCommandExecutor(results: [
            .success([.standardOutput(commitRecord)])
        ], expectedInvocations: [
            expectedInvocation([
                "-C", "/tmp/gitmate-repository", "log",
                "--format=%h%x1f%H%x1f%s%x1f%an%x1f%ae%x1f%aI%x1f%P%x1f%D%x1e",
                "-n", "1", "--skip", "20"
            ])
        ])
        let reader = CommandLocalGitReader(executor: executor)

        let page = try await reader.commits(
            repositoryURL: URL(fileURLWithPath: "/tmp/gitmate-repository"),
            cursor: "20",
            limit: 1
        )

        try expectEqual(
            executor.commands,
            [[
                "-C", "/tmp/gitmate-repository", "log",
                "--format=%h%x1f%H%x1f%s%x1f%an%x1f%ae%x1f%aI%x1f%P%x1f%D%x1e",
                "-n", "1", "--skip", "20"
            ]],
            "分页提交命令必须精确匹配白名单"
        )
        try expectEqual(page.commits.map(\.fullHash), ["a81c32ffull"], "应解析提交页")
        try expectEqual(page.nextCursor, "21", "满页时游标应等于 skip 加返回数")
        try executor.verifyComplete()
    },
    TestCase("提交详情和差异只执行 show 白名单命令") {
        let executor = FakeCommandExecutor(results: [
            .success([.standardOutput(commitDetailOutput)]),
            .success([.standardOutput(diffOutput)])
        ], expectedInvocations: [
            expectedInvocation([
                "-C", "/tmp/gitmate-repository", "show",
                "--no-patch",
                "--format=%h%x00%H%x00%s%x00%an%x00%ae%x00%aI%x00%P%x00%D%x00%G?%x00%GS%x00%B%x00",
                "a81c32f"
            ]),
            expectedInvocation([
                "-C", "/tmp/gitmate-repository", "show",
                "--format=%H%x00",
                "--numstat", "--patch", "a81c32f"
            ])
        ])
        let reader = CommandLocalGitReader(executor: executor)
        let repositoryURL = URL(fileURLWithPath: "/tmp/gitmate-repository")

        let detail = try await reader.commit(
            repositoryURL: repositoryURL,
            hash: "a81c32f"
        )
        let diff = try await reader.diff(
            repositoryURL: repositoryURL,
            hash: "a81c32f"
        )

        let expectedDetailArguments = [
            "-C", "/tmp/gitmate-repository", "show",
            "--no-patch",
            "--format=%h%x00%H%x00%s%x00%an%x00%ae%x00%aI%x00%P%x00%D%x00%G?%x00%GS%x00%B%x00",
            "a81c32f"
        ]
        let expectedDiffArguments = [
            "-C", "/tmp/gitmate-repository", "show",
            "--format=%H%x00",
            "--numstat", "--patch", "a81c32f"
        ]
        try expectEqual(
            executor.commands,
            [expectedDetailArguments, expectedDiffArguments],
            "详情与差异应分别执行无损的只读 show 形态"
        )
        try expectEqual(detail.commit.shortHash, "a81c32f", "应返回真实提交详情")
        try expectEqual(diff.commitHash, "a81c32ffull", "差异应关联完整提交哈希")
        try executor.verifyComplete()
    },
    TestCase("提交图复用只读日志并返回独立图分页模型") {
        let executor = FakeCommandExecutor(results: [
            .success([.standardOutput(commitRecord)])
        ], expectedInvocations: [
            expectedInvocation([
                "-C", "/tmp/gitmate-repository", "log",
                "--format=%h%x1f%H%x1f%s%x1f%an%x1f%ae%x1f%aI%x1f%P%x1f%D%x1e",
                "-n", "10"
            ])
        ])
        let reader = CommandLocalGitReader(executor: executor)

        let page = try await reader.graph(
            repositoryURL: URL(fileURLWithPath: "/tmp/gitmate-repository"),
            cursor: nil,
            limit: 10
        )

        try expectEqual(page.commits.count, 1, "提交图应解析提交")
        try expect(page.nextCursor == nil, "不足一页时不应返回下一游标")
        try expectEqual(
            executor.commands[0],
            [
                "-C", "/tmp/gitmate-repository", "log",
                "--format=%h%x1f%H%x1f%s%x1f%an%x1f%ae%x1f%aI%x1f%P%x1f%D%x1e",
                "-n", "10"
            ],
            "首个提交图页面不得附带 skip"
        )
        try executor.verifyComplete()
    },
    TestCase("不安全 revision hash path limit cursor 在执行前拒绝") {
        let executor = FakeCommandExecutor()
        let reader = CommandLocalGitReader(executor: executor)
        let repositoryURL = URL(fileURLWithPath: "/tmp/gitmate-repository")

        let operations: [@Sendable () async throws -> Void] = [
            {
                _ = try await reader.tree(
                    repositoryURL: repositoryURL,
                    revision: "--help",
                    path: "Sources"
                )
            },
            {
                _ = try await reader.commit(
                    repositoryURL: repositoryURL,
                    hash: "abc;reset"
                )
            },
            {
                _ = try await reader.file(
                    repositoryURL: repositoryURL,
                    revision: "main",
                    path: "../secret"
                )
            },
            {
                _ = try await reader.file(
                    repositoryURL: repositoryURL,
                    revision: "main",
                    path: "/etc/passwd"
                )
            },
            {
                _ = try await reader.commits(
                    repositoryURL: repositoryURL,
                    cursor: nil,
                    limit: 0
                )
            },
            {
                _ = try await reader.graph(
                    repositoryURL: repositoryURL,
                    cursor: "-1",
                    limit: 20
                )
            },
            {
                _ = try await reader.graph(
                    repositoryURL: repositoryURL,
                    cursor: nil,
                    limit: 201
                )
            }
        ]

        for operation in operations {
            do {
                try await operation()
                throw TestFailure(description: "不安全输入必须抛错")
            } catch is LocalGitReaderError {
                // 预期路径
            }
        }
        try expect(executor.commands.isEmpty, "输入校验失败前不得执行任何 Git 命令")
    },
    TestCase("执行器错误原样传播且命令参数不含凭据") {
        let executor = FakeCommandExecutor(results: [
            .failure(.commandFailed("仓库损坏"))
        ], expectedInvocations: [
            expectedInvocation([
                "-C", "/tmp/gitmate-repository", "status",
                "--porcelain=v2", "--branch", "-z"
            ])
        ])
        let reader = CommandLocalGitReader(executor: executor)

        do {
            _ = try await reader.status(
                repositoryURL: URL(fileURLWithPath: "/tmp/gitmate-repository")
            )
            throw TestFailure(description: "执行错误必须传播")
        } catch let failure as SyncFailure {
            try expectEqual(failure, .commandFailed("仓库损坏"), "应原样传播执行器错误")
        }

        let sensitiveMarkers = ["Authorization", "Token", "token"]
        try expect(
            executor.commands[0].allSatisfy { argument in
                !sensitiveMarkers.contains(where: argument.contains)
            },
            "本地 Git 命令参数不得包含凭据"
        )
        try executor.verifyComplete()
    },
    TestCase("真实执行器原样读取非 UTF-8 blob") {
        let fixture = try makeRealGitFixture()
        defer { try? FileManager.default.removeItem(at: fixture.repositoryURL) }
        let reader = CommandLocalGitReader()

        let file = try await reader.file(
            repositoryURL: fixture.repositoryURL,
            revision: "HEAD",
            path: "binary.dat"
        )

        try expectEqual(file.data, fixture.binaryData, "二进制 blob 字节不得丢失")
        try expectEqual(file.byteCount, 131_073, "多 chunk 二进制字节数必须准确")
        try expect(file.isBinary, "非 UTF-8 blob 必须标记为二进制")
        try expect(file.text == nil, "非 UTF-8 blob 不得暴露为文本")
    },
    TestCase("真实执行器保留文本空白并读取根目录与目录子项") {
        let fixture = try makeRealGitFixture()
        defer { try? FileManager.default.removeItem(at: fixture.repositoryURL) }
        let reader = CommandLocalGitReader()

        let rootEntries = try await reader.tree(
            repositoryURL: fixture.repositoryURL,
            revision: "HEAD",
            path: ""
        )
        let sourceEntries = try await reader.tree(
            repositoryURL: fixture.repositoryURL,
            revision: "HEAD",
            path: "Sources/"
        )
        let file = try await reader.file(
            repositoryURL: fixture.repositoryURL,
            revision: "HEAD",
            path: "Whitespace.txt"
        )

        try expect(
            rootEntries.map(\.path).contains("Sources"),
            "点号 pathspec 应列出根目录项"
        )
        try expectEqual(
            sourceEntries.map(\.path),
            ["Sources/App.swift"],
            "末尾斜杠 pathspec 应列出目录子项"
        )
        try expectEqual(file.text, fixture.whitespaceText, "文本空白和空行必须无损")
        try expectEqual(file.data, Data(fixture.whitespaceText.utf8), "文本字节必须无损")
    },
    TestCase("真实执行器保留完整提交消息与 patch 空白") {
        let fixture = try makeRealGitFixture()
        defer { try? FileManager.default.removeItem(at: fixture.repositoryURL) }
        let reader = CommandLocalGitReader()

        let detail = try await reader.commit(
            repositoryURL: fixture.repositoryURL,
            hash: "HEAD"
        )
        let diff = try await reader.diff(
            repositoryURL: fixture.repositoryURL,
            hash: "HEAD"
        )

        try expectEqual(detail.message, fixture.commitMessage, "提交消息不得 trim")
        try expect(
            diff.patch.contains("+  前导新增\n+\n+结尾\n"),
            "patch 必须保留新增行前导空白与空行，实际：\(diff.patch)"
        )
    },
    TestCase("命令 fake 拒绝预期之外的额外调用") {
        let output = "# branch.head main\u{0}"
        let arguments = [
            "-C", "/tmp/gitmate-repository", "status",
            "--porcelain=v2", "--branch", "-z"
        ]
        let executor = FakeCommandExecutor(
            results: [.success([.standardOutput(output)])],
            expectedInvocations: [expectedInvocation(arguments)]
        )
        let reader = CommandLocalGitReader(executor: executor)
        let repositoryURL = URL(fileURLWithPath: "/tmp/gitmate-repository")

        let firstStatus = try await reader.status(repositoryURL: repositoryURL)
        try expectEqual(firstStatus.branch, "main", "首次预期调用应返回真实解析状态")
        do {
            _ = try await reader.status(repositoryURL: repositoryURL)
            throw TestFailure(description: "额外调用必须被 fake 拒绝")
        } catch is TestFailure {
            throw TestFailure(description: "额外调用未被 fake 拒绝")
        } catch {
            // 预期路径
        }
        do {
            try executor.verifyComplete()
            throw TestFailure(description: "额外调用的契约失败必须持续报告")
        } catch is TestFailure {
            throw TestFailure(description: "verifyComplete 未报告额外调用")
        } catch {
            // 预期路径
        }
    },
    TestCase("命令 fake 报告未消费的预期调用和结果") {
        let executor = FakeCommandExecutor(
            results: [.success([])],
            expectedInvocations: [
                expectedInvocation([
                    "-C", "/tmp/gitmate-repository", "status",
                    "--porcelain=v2", "--branch", "-z"
                ])
            ]
        )

        do {
            try executor.verifyComplete()
            throw TestFailure(description: "剩余预期必须被 fake 报告")
        } catch is TestFailure {
            throw TestFailure(description: "fake 未报告剩余预期")
        } catch {
            // 预期路径
        }
    },
    TestCase("命令 fake 参数不匹配后保留预期结果并持续报告失败") {
        let output = "# branch.head main\u{0}"
        let expectedArguments = [
            "-C", "/tmp/gitmate-repository", "status",
            "--porcelain=v2", "--branch", "-z"
        ]
        let executor = FakeCommandExecutor(
            results: [.success([.standardOutput(output)])],
            expectedInvocations: [expectedInvocation(expectedArguments)]
        )

        do {
            for try await _ in executor.execute(
                arguments: ["错误命令"],
                environment: [:]
            ) {}
            throw TestFailure(description: "参数不匹配必须立即失败")
        } catch is TestFailure {
            throw TestFailure(description: "参数不匹配未被 fake 拒绝")
        } catch {
            // 预期路径
        }

        let reader = CommandLocalGitReader(executor: executor)
        let status = try await reader.status(
            repositoryURL: URL(fileURLWithPath: "/tmp/gitmate-repository")
        )
        try expectEqual(status.branch, "main", "不匹配调用不得消费正确结果")

        do {
            try executor.verifyComplete()
            throw TestFailure(description: "历史契约失败必须持续报告")
        } catch is TestFailure {
            throw TestFailure(description: "verifyComplete 未报告历史契约失败")
        } catch {
            // 预期路径
        }
    },
    TestCase("进程管道 drain 等待在途读取并保持字节顺序") {
        let pipe = Pipe()
        let reader = ProcessPipeReader()
        let state = PipeReadTestState()
        pipe.fileHandleForWriting.write(Data("A".utf8))

        DispatchQueue.global().async {
            reader.consumeAvailable(
                from: pipe.fileHandleForReading,
                consume: state.holdAndAppend
            )
        }
        try expectEqual(
            state.handlerStarted.wait(timeout: .now() + 2),
            .success,
            "在途读取应先取得 A"
        )
        pipe.fileHandleForWriting.write(Data("B".utf8))
        try pipe.fileHandleForWriting.close()

        DispatchQueue.global().async {
            reader.drain(
                from: pipe.fileHandleForReading,
                consume: state.append
            )
            state.drainFinished.signal()
        }
        try expectEqual(
            state.drainFinished.wait(timeout: .now() + 0.05),
            .timedOut,
            "drain 必须等待在途 handler 完成"
        )

        state.releaseHandler.signal()
        try expectEqual(
            state.handlerFinished.wait(timeout: .now() + 2),
            .success,
            "在途 handler 应完成"
        )
        try expectEqual(
            state.drainFinished.wait(timeout: .now() + 2),
            .success,
            "drain 应在 handler 后完成"
        )
        try expectEqual(state.data, Data("AB".utf8), "管道字节顺序必须保持 A 后 B")
    }
]
