import Foundation
import GitMateCore

let readmeViewModelTests = [
    TestCase("README 标题生成分级可定位目录并稳定处理重复标题") { @MainActor in
        let viewModel = READMEViewModel(parser: READMEBlockParser())

        viewModel.load(
            markdown: """
            # 安装
            ## 配置
            ## 配置
            # 安装
            """,
            baseURL: nil
        )

        try expectEqual(
            viewModel.state.outline,
            [
                READMEOutlineItem(level: 1, id: "安装", title: "安装"),
                READMEOutlineItem(level: 2, id: "配置", title: "配置"),
                READMEOutlineItem(level: 2, id: "配置-2", title: "配置"),
                READMEOutlineItem(level: 1, id: "安装-2", title: "安装")
            ],
            "目录应保留层级且重复标题锚点必须唯一稳定"
        )
        try expectEqual(
            viewModel.state.loadPhase,
            .loaded,
            "存在安全内容时应进入已加载状态"
        )
    },
    TestCase("README 恶意 HTML 与危险链接不得进入视图状态") { @MainActor in
        let viewModel = READMEViewModel(parser: READMEBlockParser())

        viewModel.load(
            markdown: """
            # 安全
            <script>窃取令牌</script>
            <iframe src="https://evil.example/embed"></iframe>
            [危险](javascript:alert(1))
            [安全链接](https://docs.example/guide)
            ![危险图片](file:///etc/passwd)
            """,
            baseURL: nil
        )

        let document = viewModel.state.document
        try expect(
            document?.plainText.contains("窃取令牌") == false,
            "脚本容器和内容必须完全移除"
        )
        try expectEqual(
            document?.links,
            [
                READMEExternalLink(
                    title: "安全链接",
                    url: URL(string: "https://docs.example/guide")!
                )
            ],
            "只允许 http 和 https 外链"
        )
        try expect(
            document?.blocks.contains(where: { block in
                guard case let .image(url, _) = block else {
                    return false
                }
                return url.isFileURL || url.scheme == "javascript"
            }) == false,
            "危险图片协议不得进入块状态"
        )
    },
    TestCase("恶意嵌套 Markdown 链接只作为纯文本展示") { @MainActor in
        let viewModel = READMEViewModel(parser: READMEBlockParser())
        let markdown = "[外链 [嵌套]](file:///etc/passwd)"

        viewModel.load(markdown: markdown, baseURL: nil)

        guard case let .paragraph(content)? =
            viewModel.state.document?.blocks.first
        else {
            throw TestFailure(description: "恶意嵌套链接应保留为段落")
        }
        let presentation = READMEInlinePresentation(content: content)
        try expectEqual(
            presentation.plainText,
            markdown,
            "无法识别的嵌套链接应原样保留为纯文本"
        )
        try expectEqual(
            presentation.externalLinks,
            [],
            "纯文本中的 Markdown 语法不得被二次激活为可执行链接"
        )
    },
    TestCase("README 空文档显示稳定空状态") { @MainActor in
        let viewModel = READMEViewModel(parser: READMEBlockParser())

        viewModel.load(
            markdown: " \n<!-- 只有注释 -->\n<script>危险</script>",
            baseURL: nil
        )

        try expectEqual(viewModel.state.loadPhase, .empty, "无可见内容应显示空状态")
        try expectEqual(viewModel.state.document, nil, "空文档不应保留无意义对象")
        try expectEqual(viewModel.state.outline, [], "空文档不应生成目录")
    },
    TestCase("只有安全图片的 README 仍是有效文档") { @MainActor in
        let viewModel = READMEViewModel(parser: READMEBlockParser())

        viewModel.load(
            markdown: "![](https://images.example/hero.png)",
            baseURL: nil
        )

        try expectEqual(
            viewModel.state.loadPhase,
            .loaded,
            "图片不含替代文字时也不能被误判为空文档"
        )
        try expectEqual(
            viewModel.state.document?.blocks,
            [
                .image(
                    url: URL(string: "https://images.example/hero.png")!,
                    alt: ""
                )
            ],
            "安全图片块应保留在文档状态"
        )
    },
    TestCase("README 解析失败使用稳定错误状态且可重试") { @MainActor in
        let parser = SequencedREADMEParser(
            outcomes: [
                .failure(.failed),
                .success(READMEBlockParser().parse("# 恢复"))
            ]
        )
        let viewModel = READMEViewModel(parser: parser)

        viewModel.load(markdown: "# 第一次", baseURL: nil)
        try expectEqual(
            viewModel.state.loadPhase,
            .failed(message: "暂时无法解析 README，请稍后重试。"),
            "解析失败不得泄露底层错误"
        )
        try expectEqual(
            viewModel.state.retryAction,
            WorkspaceRetryAction(
                title: "重试",
                accessibilityLabel: "重新加载 README",
                accessibilityIdentifier: "workspace.repository.readme.retry"
            ),
            "README 失败状态应提供稳定且可访问的真实重试动作"
        )

        viewModel.load(markdown: "# 第二次", baseURL: nil)

        try expectEqual(viewModel.state.loadPhase, .loaded, "解析失败后应允许重试")
        try expectEqual(viewModel.state.outline.map(\.title), ["恢复"], "重试结果应写入状态")
    },
    TestCase("README 缓存尚无文档时保持加载直至刷新确认") { @MainActor in
        let repository = readmeRepository()
        let loader = ControlledREADMEUpdatesLoader()
        let viewModel = READMEViewModel(
            repository: repository,
            account: readmeAccount(),
            token: "secret",
            loader: loader,
            parser: READMEBlockParser()
        )

        let load = Task { @MainActor in
            await viewModel.load()
        }
        await loader.waitUntilConnected()
        loader.yield(
            RepositoryContentUpdate(
                content: readmeRepositoryContent(
                    repository: repository,
                    markdown: nil
                ),
                freshness: .cached,
                isFinal: false
            )
        )
        await Task.yield()

        try expectEqual(
            viewModel.state.loadPhase,
            .loading,
            "非最终缓存没有 README 时不得提前显示空状态"
        )

        loader.yield(
            RepositoryContentUpdate(
                content: readmeRepositoryContent(
                    repository: repository,
                    markdown: "# 最新文档"
                ),
                freshness: .refreshed,
                isFinal: true
            )
        )
        loader.finish()
        await load.value

        try expectEqual(viewModel.state.loadPhase, .loaded, "刷新返回 README 后应显示文档")
        try expectEqual(viewModel.state.outline.map(\.title), ["最新文档"], "应使用最终 README")
    },
    TestCase("README 只有最终更新为空时进入空状态") { @MainActor in
        let repository = readmeRepository()
        let loader = ControlledREADMEUpdatesLoader()
        let viewModel = READMEViewModel(
            repository: repository,
            account: readmeAccount(),
            token: "secret",
            loader: loader,
            parser: READMEBlockParser()
        )

        let load = Task { @MainActor in
            await viewModel.load()
        }
        await loader.waitUntilConnected()
        loader.yield(
            RepositoryContentUpdate(
                content: readmeRepositoryContent(
                    repository: repository,
                    markdown: nil
                ),
                freshness: .refreshed,
                isFinal: true
            )
        )
        loader.finish()
        await load.value

        try expectEqual(viewModel.state.loadPhase, .empty, "最终确认无 README 时才显示空状态")
    },
    TestCase("README 后台刷新失败保留缓存文档") { @MainActor in
        let repository = readmeRepository()
        let loader = ControlledREADMEUpdatesLoader()
        let viewModel = READMEViewModel(
            repository: repository,
            account: readmeAccount(),
            token: "secret",
            loader: loader,
            parser: READMEBlockParser()
        )

        let load = Task { @MainActor in
            await viewModel.load()
        }
        await loader.waitUntilConnected()
        loader.yield(
            RepositoryContentUpdate(
                content: readmeRepositoryContent(
                    repository: repository,
                    markdown: "# 缓存文档"
                ),
                freshness: .cached,
                isFinal: false
            )
        )
        while viewModel.state.loadPhase != .loaded {
            await Task.yield()
        }
        loader.yield(
            RepositoryContentUpdate(
                content: readmeRepositoryContent(
                    repository: repository,
                    markdown: "# 缓存文档",
                    panelErrors: [
                        WorkspacePanelError(
                            panel: .readme,
                            repositoryID: repository.id,
                            message: "无法在线读取 README，已保留其他仓库内容。"
                        )
                    ]
                ),
                freshness: .refreshed,
                isFinal: true
            )
        )
        loader.finish()
        await load.value

        try expectEqual(viewModel.state.loadPhase, .loaded, "刷新失败不得覆盖缓存文档")
        try expectEqual(viewModel.state.outline.map(\.title), ["缓存文档"], "旧文档必须保留")
        try expectEqual(
            viewModel.state.nonBlockingErrorMessage,
            "后台刷新失败，已保留缓存内容。",
            "后台错误应以非阻塞方式展示"
        )
    },
    TestCase("README 仓库加载取消不污染状态且随后可以重新加载") { @MainActor in
        let repository = readmeRepository()
        let loader = PausableREADMEContentLoader()
        let viewModel = READMEViewModel(
            repository: repository,
            account: readmeAccount(),
            token: "secret",
            loader: loader,
            parser: READMEBlockParser()
        )
        let stateBeforeLoad = viewModel.state

        let cancelledLoad = Task { @MainActor in
            await viewModel.load()
        }
        while await loader.loadCount < 1 {
            await Task.yield()
        }
        cancelledLoad.cancel()
        await loader.resumeNext(
            with: readmeRepositoryContent(
                repository: repository,
                markdown: "# 旧结果"
            )
        )
        await cancelledLoad.value

        try expectEqual(
            viewModel.state,
            stateBeforeLoad,
            "取消不得把旧仓库 README 写入页面状态"
        )

        let retryLoad = Task { @MainActor in
            await viewModel.load()
        }
        while await loader.loadCount < 2 {
            await Task.yield()
        }
        await loader.resumeNext(
            with: readmeRepositoryContent(
                repository: repository,
                markdown: "# 最新结果"
            )
        )
        await retryLoad.value

        try expectEqual(
            viewModel.state.outline.map(\.title),
            ["最新结果"],
            "取消后重试应加载最新仓库 README"
        )
    },
    TestCase("README 仓库加载失败可重试且成功后去重") { @MainActor in
        let repository = readmeRepository()
        let loader = READMEContentLoaderStub(
            outcomes: [
                .failure(.failed),
                .success(
                    readmeRepositoryContent(
                        repository: repository,
                        markdown: "# 成功"
                    )
                )
            ]
        )
        let viewModel = READMEViewModel(
            repository: repository,
            account: readmeAccount(),
            token: "secret",
            loader: loader,
            parser: READMEBlockParser()
        )

        await viewModel.load()
        try expectEqual(
            viewModel.state.loadPhase,
            .failed(message: "暂时无法加载 README，请稍后重试。"),
            "仓库读取失败应显示稳定错误"
        )

        await viewModel.load()
        await viewModel.load()

        try expectEqual(viewModel.state.outline.map(\.title), ["成功"], "重试应展示 README")
        let loadCount = await loader.currentLoadCount()
        try expectEqual(
            loadCount,
            2,
            "成功后重复调用不得重新读取仓库"
        )
    }
]

private enum READMEFixtureError: Error, Sendable {
    case failed
}

private final class ControlledREADMEUpdatesLoader:
    RepositoryContentLoading,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var continuation:
        AsyncThrowingStream<RepositoryContentUpdate, Error>.Continuation?

    func repositoryContent(
        repository _: Repository,
        account _: GitHubAccount,
        token _: String
    ) async throws -> RepositoryContent {
        throw READMEFixtureError.failed
    }

    func repositoryContentUpdates(
        repository _: Repository,
        account _: GitHubAccount,
        token _: String
    ) -> AsyncThrowingStream<RepositoryContentUpdate, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock {
                self.continuation = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock {
                    self?.continuation = nil
                }
            }
        }
    }

    func waitUntilConnected() async {
        while lock.withLock({ continuation == nil }) {
            await Task.yield()
        }
    }

    func yield(_ update: RepositoryContentUpdate) {
        lock.withLock { continuation }?.yield(update)
    }

    func finish(throwing error: Error? = nil) {
        lock.withLock { continuation }?.finish(throwing: error)
    }
}

private final class SequencedREADMEParser: READMEParsing, @unchecked Sendable {
    enum Outcome: Sendable {
        case success(READMEDocument)
        case failure(READMEFixtureError)
    }

    private let lock = NSLock()
    private var outcomes: [Outcome]

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func parse(
        _ markdown: String,
        baseURL: URL?
    ) throws -> READMEDocument {
        lock.lock()
        defer { lock.unlock() }
        guard !outcomes.isEmpty else {
            throw READMEFixtureError.failed
        }
        switch outcomes.removeFirst() {
        case let .success(document):
            return document
        case let .failure(error):
            throw error
        }
    }
}

private actor READMEContentLoaderStub: RepositoryContentLoading {
    enum Outcome: Sendable {
        case success(RepositoryContent)
        case failure(READMEFixtureError)
    }

    private var outcomes: [Outcome]
    private var loadCount = 0

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func repositoryContent(
        repository _: Repository,
        account _: GitHubAccount,
        token _: String
    ) async throws -> RepositoryContent {
        loadCount += 1
        guard !outcomes.isEmpty else {
            throw READMEFixtureError.failed
        }
        switch outcomes.removeFirst() {
        case let .success(content):
            return content
        case let .failure(error):
            throw error
        }
    }

    func currentLoadCount() -> Int {
        loadCount
    }
}

private actor PausableREADMEContentLoader: RepositoryContentLoading {
    private(set) var loadCount = 0
    private var continuations: [
        CheckedContinuation<RepositoryContent, Never>
    ] = []

    func repositoryContent(
        repository _: Repository,
        account _: GitHubAccount,
        token _: String
    ) async throws -> RepositoryContent {
        loadCount += 1
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeNext(with content: RepositoryContent) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: content)
    }
}

private func readmeRepository() -> Repository {
    Repository(
        id: 101,
        name: "mac-client",
        fullName: "GitMate/mac-client",
        isPrivate: true,
        defaultBranch: "main",
        sizeInKilobytes: 1_024,
        cloneURL: URL(
            string: "https://github.example/GitMate/mac-client.git"
        )!,
        ownerAvatarURL: nil
    )
}

private func readmeAccount() -> GitHubAccount {
    GitHubAccount(
        id: "readme-account",
        login: "lele",
        name: "Lele",
        avatarURL: nil,
        serverURL: URL(string: "https://github.example")!,
        kind: .enterprise,
        scopes: ["repo"]
    )
}

private func readmeRepositoryContent(
    repository: Repository,
    markdown: String?,
    panelErrors: [WorkspacePanelError] = []
) -> RepositoryContent {
    RepositoryContent(
        repository: repository,
        localRecord: LocalRepositoryRecord(
            repository: repository,
            localURL: URL(filePath: "/tmp/\(repository.name)"),
            availability: .available,
            localSizeInBytes: 1_024,
            lastInspectedAt: Date(timeIntervalSince1970: 100)
        ),
        localStatus: nil,
        onlineSummary: nil,
        recentCommits: [],
        readme: markdown.map {
            GitHubREADME(
                repositoryID: repository.id,
                path: "README.md",
                markdown: $0,
                downloadURL: URL(
                    string: "https://raw.example/GitMate/mac-client/main/README.md"
                )
            )
        },
        connectivity: .online,
        panelErrors: panelErrors
    )
}
