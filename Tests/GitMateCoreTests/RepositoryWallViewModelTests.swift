import AppKit
import Foundation
import GitMateCore

let repositoryWallViewModelTests = [
    TestCase("云端仓库海报保留 GitHub 返回的主要语言") {
        let repositories = [
            Repository(
                id: 99,
                name: "mac-client",
                fullName: "gitmate/mac-client",
                isPrivate: true,
                defaultBranch: "main",
                sizeInKilobytes: 2_048,
                cloneURL: URL(
                    string: "https://github.com/gitmate/mac-client.git"
                )!,
                ownerAvatarURL: nil,
                primaryLanguage: "Swift"
            ),
            Repository(
                id: 100,
                name: "web-client",
                fullName: "gitmate/web-client",
                isPrivate: false,
                defaultBranch: "main",
                sizeInKilobytes: 1_024,
                cloneURL: URL(
                    string: "https://github.com/gitmate/web-client.git"
                )!,
                ownerAvatarURL: nil,
                primaryLanguage: "TypeScript"
            )
        ]
        let items = RepositoryPosterBuilder.makeCloud(
            repositories: repositories
        )
        let viewModel = await MainActor.run {
            RepositoryWallViewModel(items: items)
        }

        try expectEqual(
            items.map(\.language),
            ["Swift", "TypeScript"],
            "语言菜单应获得真实的主要语言"
        )
        try expect(items.allSatisfy { $0.syncMode == .never }, "云端仓库默认不自动下载")
        try expect(
            items.allSatisfy { $0.syncState == .notSynchronized },
            "云端仓库应标记为尚未同步"
        )
        await MainActor.run {
            viewModel.language = "TypeScript"
        }
        let visibleRepositoryIDs = await MainActor.run {
            viewModel.visibleItems.map(\.id)
        }
        try expectEqual(
            visibleRepositoryIDs,
            [100],
            "选择语言后只应显示对应云端仓库"
        )
    },
    TestCase("仓库墙组合搜索可见性语言和同步状态筛选") { @MainActor in
        let items = [
            repositoryPosterFixture(
                id: 3,
                fullName: "studio/asset-console",
                language: "TypeScript",
                syncState: .needsAttention,
                updatedAt: Date(timeIntervalSince1970: 300)
            ),
            repositoryPosterFixture(
                id: 2,
                fullName: "GitMate/server",
                language: "Swift",
                isPrivate: false,
                syncState: .synchronized,
                updatedAt: Date(timeIntervalSince1970: 200)
            ),
            repositoryPosterFixture(
                id: 1,
                fullName: "GitMate/mac-client",
                language: "Swift",
                isPrivate: true,
                syncState: .synchronized,
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        ]
        let viewModel = RepositoryWallViewModel(items: items)

        viewModel.searchText = "gitmate"
        viewModel.visibility = .privateOnly
        viewModel.language = "swift"
        viewModel.syncState = .synchronized
        viewModel.sort = .recentlyUpdated

        try expectEqual(
            viewModel.visibleItems.map(\.repository.fullName),
            ["GitMate/mac-client"],
            "搜索所有者后应继续组合应用可见性、语言和同步状态筛选"
        )
    },
    TestCase("仓库墙同步状态筛选只保留需要处理的仓库") { @MainActor in
        let viewModel = RepositoryWallViewModel(
            items: [
                repositoryPosterFixture(
                    id: 1,
                    fullName: "owner/clean",
                    syncState: .synchronized
                ),
                repositoryPosterFixture(
                    id: 2,
                    fullName: "owner/pending",
                    syncState: .needsAttention
                ),
                repositoryPosterFixture(
                    id: 3,
                    fullName: "owner/missing",
                    syncState: .notSynchronized
                )
            ]
        )

        viewModel.syncState = .needsAttention

        try expectEqual(
            viewModel.visibleItems.map(\.repository.fullName),
            ["owner/pending"],
            "同步状态筛选不得混入正常或尚未同步的仓库"
        )
    },
    TestCase("仓库墙增量更新海报时保留用户筛选与排序") { @MainActor in
        let viewModel = RepositoryWallViewModel(
            items: [
                repositoryPosterFixture(
                    id: 1,
                    fullName: "owner/first",
                    language: nil,
                    syncState: .needsAttention
                )
            ]
        )
        viewModel.searchText = "second"
        viewModel.visibility = .publicOnly
        viewModel.language = "Swift"
        viewModel.syncState = .synchronized
        viewModel.sort = .name

        viewModel.updateItems([
            repositoryPosterFixture(
                id: 1,
                fullName: "owner/first",
                language: "Swift",
                syncState: .synchronized
            ),
            repositoryPosterFixture(
                id: 2,
                fullName: "owner/second",
                language: "Swift",
                syncState: .synchronized
            )
        ])

        try expectEqual(viewModel.searchText, "second", "增量更新不得清空搜索词")
        try expectEqual(viewModel.visibility, .publicOnly, "增量更新不得重置可见性")
        try expectEqual(viewModel.language, "Swift", "增量更新不得重置语言")
        try expectEqual(viewModel.syncState, .synchronized, "增量更新不得重置同步状态")
        try expectEqual(viewModel.sort, .name, "增量更新不得重置排序")
        try expectEqual(
            viewModel.visibleItems.map(\.id),
            [2],
            "新海报应立即使用现有筛选条件"
        )
    },
    TestCase("仓库墙最近更新排序使用仓库全名和编号稳定消除同值抖动") {
        let sameDate = Date(timeIntervalSince1970: 200)
        let sorted = RepositoryWallFilter.apply(
            [
                repositoryPosterFixture(
                    id: 4,
                    fullName: "zeta/repo",
                    updatedAt: nil
                ),
                repositoryPosterFixture(
                    id: 3,
                    fullName: "beta/repo",
                    updatedAt: sameDate
                ),
                repositoryPosterFixture(
                    id: 2,
                    fullName: "alpha/repo",
                    updatedAt: sameDate
                ),
                repositoryPosterFixture(
                    id: 1,
                    fullName: "alpha/repo",
                    updatedAt: sameDate
                )
            ],
            searchText: "",
            visibility: .all,
            language: nil,
            syncState: .all,
            sort: .recentlyUpdated
        )

        try expectEqual(
            sorted.map(\.repository.id),
            [1, 2, 3, 4],
            "更新时间相同应按全名再按编号稳定排序，未知更新时间排在最后"
        )
    },
    TestCase("仓库墙名称和大小排序都使用固定次级键") {
        let fixtures = [
            repositoryPosterFixture(
                id: 4,
                fullName: "zeta/repo",
                sizeInKilobytes: 800
            ),
            repositoryPosterFixture(
                id: 3,
                fullName: "alpha/repo",
                sizeInKilobytes: 400
            ),
            repositoryPosterFixture(
                id: 2,
                fullName: "beta/repo",
                sizeInKilobytes: 800
            ),
            repositoryPosterFixture(
                id: 1,
                fullName: "alpha/repo",
                sizeInKilobytes: 400
            )
        ]

        let byName = RepositoryWallFilter.apply(
            fixtures,
            searchText: "",
            visibility: .all,
            language: nil,
            syncState: .all,
            sort: .name
        )
        let bySize = RepositoryWallFilter.apply(
            fixtures,
            searchText: "",
            visibility: .all,
            language: nil,
            syncState: .all,
            sort: .size
        )

        try expectEqual(
            byName.map(\.repository.id),
            [1, 3, 2, 4],
            "名称相同应使用编号作为固定次级键"
        )
        try expectEqual(
            bySize.map(\.repository.id),
            [2, 4, 1, 3],
            "大小应从大到小，同值按全名再按编号排序"
        )
    },
    TestCase("仓库墙从 README 提取封面并优先读取磁盘缓存") {
        let sourceURL = URL(string: "https://cdn.example.com/hero.png")!
        let imageData = validRepositoryWallCoverData()
        let cache = RepositoryWallCoverCacheStub(
            entries: [
                sourceURL: RepositoryCoverCacheEntry(
                    data: imageData,
                    metadata: RepositoryCoverCacheMetadata(
                        contentType: "image/png",
                        storedAt: Date(timeIntervalSince1970: 100),
                        pixelWidth: 1_200,
                        pixelHeight: 800
                    )
                )
            ]
        )
        let card = repositoryCardFixture(
            id: 9,
            fullName: "owner/covered",
            readme: GitHubREADME(
                repositoryID: 9,
                path: "README.md",
                markdown: "![产品头图](https://cdn.example.com/hero.png)",
                downloadURL: URL(
                    string: "https://raw.example.com/owner/covered/main/README.md"
                )
            )
        )

        let item = RepositoryPosterBuilder.make(
            contents: [card],
            extractor: RepositoryCoverExtractor(),
            cache: cache
        ).first

        try expectEqual(
            item?.cover,
            .cached(
                data: imageData,
                sourceURL: sourceURL,
                fallback: FallbackRepositoryCover.make(
                    repository: card.content.repository,
                    language: "Swift"
                )
            ),
            "有效 README 图片已有缓存时应直接提供缓存封面"
        )
    },
    TestCase("仓库墙无图时生成稳定回退封面并提供真实路由与可访问标识") {
        let card = repositoryCardFixture(
            id: 42,
            fullName: "owner/no-cover",
            readme: GitHubREADME(
                repositoryID: 42,
                path: "README.md",
                markdown: "# 没有图片",
                downloadURL: nil
            )
        )

        let first = RepositoryPosterBuilder.make(
            contents: [card],
            extractor: RepositoryCoverExtractor(),
            cache: RepositoryWallCoverCacheStub()
        )[0]
        let second = RepositoryPosterBuilder.make(
            contents: [card],
            extractor: RepositoryCoverExtractor(),
            cache: RepositoryWallCoverCacheStub()
        )[0]

        try expectEqual(first.cover, second.cover, "同一仓库的回退封面必须稳定")
        try expectEqual(
            first.destination,
            .repositoryOverview(repositoryID: 42),
            "点击海报必须进入对应仓库总览"
        )
        try expectEqual(
            first.accessibilityIdentifier,
            "workspace.repositories.poster.42",
            "海报应提供由仓库编号稳定生成的可访问标识"
        )
    },
    TestCase("仓库墙解析远程封面成功转缓存失败转稳定回退") { @MainActor in
        let successURL = URL(string: "https://images.example/success.png")!
        let failureURL = URL(string: "https://images.example/failure.png")!
        let success = remoteRepositoryPosterFixture(
            id: 51,
            sourceURL: successURL
        )
        let failure = remoteRepositoryPosterFixture(
            id: 52,
            sourceURL: failureURL
        )
        let data = validRepositoryWallCoverData()
        let loader = RepositoryWallLoaderStub(
            successfulEntries: [
                successURL: RepositoryCoverCacheEntry(
                    data: data,
                    metadata: RepositoryCoverCacheMetadata(
                        contentType: "image/png",
                        storedAt: Date(timeIntervalSince1970: 10),
                        pixelWidth: 320,
                        pixelHeight: 280
                    )
                )
            ]
        )
        let viewModel = RepositoryWallViewModel(
            items: [success, failure],
            coverLoader: loader
        )

        try expect(
            !success.cover.usesREADMEImage,
            "远程图片尚未验证前不得计为 README 封面"
        )
        await viewModel.resolvePendingCovers()

        try expectEqual(
            viewModel.items[0].cover,
            .cached(
                data: data,
                sourceURL: successURL,
                fallback: success.cover.fallback
            ),
            "成功加载后应转为真实缓存封面"
        )
        try expectEqual(
            viewModel.items[1].cover,
            .fallback(failure.cover.fallback),
            "远程失败后应转为稳定回退封面"
        )
    },
    TestCase("仓库墙解析远程封面取消后保持待加载状态") { @MainActor in
        let item = remoteRepositoryPosterFixture(
            id: 61,
            sourceURL: URL(string: "https://images.example/slow.png")!
        )
        let loader = SuspendingRepositoryWallLoader()
        let viewModel = RepositoryWallViewModel(
            items: [item],
            coverLoader: loader
        )
        let task = Task { @MainActor in
            await viewModel.resolvePendingCovers()
        }

        while await !loader.hasStarted {
            await Task.yield()
        }
        task.cancel()
        await task.value

        try expectEqual(
            viewModel.items[0].cover,
            item.cover,
            "取消不得把尚未完成的远程封面错误标记为失败"
        )
    },
    TestCase("仓库墙只把当前窗口调度结果写回对应海报") { @MainActor in
        let repositories = (1...12).map {
            repositoryPosterFixture(
                id: Int64($0),
                fullName: String(
                    format: "owner/repository-%02d",
                    $0
                )
            )
        }
        let resolver = ViewportCoverResolverStub(
            data: validRepositoryWallCoverData()
        )
        let scheduler = RepositoryCoverViewportScheduler(
            resolver: resolver,
            maximumConcurrentLoads: 3
        )
        let viewModel = RepositoryWallViewModel(
            items: repositories,
            coverScheduler: scheduler,
            token: "secret"
        )

        await viewModel.updateVisibleCovers(
            visibleRepositoryIDs: [1, 2, 3, 4],
            columnCount: 4
        )

        try expectEqual(
            Set(viewModel.items.filter(\.cover.usesREADMEImage).map(\.id)),
            Set(Array(1...8).map(Int64.init)),
            "只应写回当前窗口与下一行的封面"
        )
    }
]

private enum RepositoryWallLoaderError: Error, Sendable {
    case failed
}

private actor RepositoryWallLoaderStub: RepositoryCoverLoading {
    let successfulEntries: [URL: RepositoryCoverCacheEntry]

    init(successfulEntries: [URL: RepositoryCoverCacheEntry]) {
        self.successfulEntries = successfulEntries
    }

    func load(
        repositoryID _: Int64,
        sourceURL: URL
    ) async throws -> RepositoryCoverCacheEntry {
        guard let entry = successfulEntries[sourceURL] else {
            throw RepositoryWallLoaderError.failed
        }
        return entry
    }
}

private actor SuspendingRepositoryWallLoader: RepositoryCoverLoading {
    private(set) var hasStarted = false

    func load(
        repositoryID _: Int64,
        sourceURL _: URL
    ) async throws -> RepositoryCoverCacheEntry {
        hasStarted = true
        try await Task.sleep(for: .seconds(30))
        throw RepositoryWallLoaderError.failed
    }
}

private actor ViewportCoverResolverStub: RepositoryCoverResolving {
    let data: Data

    init(data: Data) {
        self.data = data
    }

    func resolve(
        repository: Repository,
        token _: String,
        policy _: RepositoryCoverResolvePolicy
    ) async throws -> RepositoryCoverCacheEntry? {
        RepositoryCoverCacheEntry(
            data: data,
            metadata: RepositoryCoverCacheMetadata(
                contentType: "image/png",
                storedAt: Date(timeIntervalSince1970: 100),
                pixelWidth: 320,
                pixelHeight: 280,
                sourceURL: URL(
                    string: "https://images.example/\(repository.id).png"
                )
            )
        )
    }
}

private final class RepositoryWallCoverCacheStub: RepositoryCoverCaching,
    @unchecked Sendable
{
    private let entries: [URL: RepositoryCoverCacheEntry]

    init(entries: [URL: RepositoryCoverCacheEntry] = [:]) {
        self.entries = entries
    }

    func load(
        repositoryID _: Int64,
        sourceURL: URL
    ) throws -> RepositoryCoverCacheEntry? {
        entries[sourceURL]
    }

    func save(
        data _: Data,
        metadata _: RepositoryCoverCacheMetadata,
        repositoryID _: Int64,
        sourceURL _: URL
    ) throws {}

    func clear(repositoryID _: Int64) throws {}
}

private func repositoryPosterFixture(
    id: Int64,
    fullName: String,
    language: String? = "Swift",
    isPrivate: Bool = false,
    sizeInKilobytes: Int = 1_024,
    syncState: RepositorySyncState = .synchronized,
    updatedAt: Date? = nil
) -> RepositoryPosterItem {
    let repository = repositoryWallRepository(
        id: id,
        fullName: fullName,
        isPrivate: isPrivate,
        sizeInKilobytes: sizeInKilobytes
    )
    return RepositoryPosterItem(
        repository: repository,
        language: language,
        syncMode: .automatic,
        syncState: syncState,
        updatedAt: updatedAt,
        cover: .fallback(
            FallbackRepositoryCover.make(
                repository: repository,
                language: language
            )
        )
    )
}

private func remoteRepositoryPosterFixture(
    id: Int64,
    sourceURL: URL
) -> RepositoryPosterItem {
    let repository = repositoryWallRepository(
        id: id,
        fullName: "owner/repository-\(id)"
    )
    let fallback = FallbackRepositoryCover.make(
        repository: repository,
        language: "Swift"
    )
    return RepositoryPosterItem(
        repository: repository,
        language: "Swift",
        syncMode: .automatic,
        syncState: .synchronized,
        updatedAt: nil,
        cover: .remote(sourceURL: sourceURL, fallback: fallback)
    )
}

private func repositoryCardFixture(
    id: Int64,
    fullName: String,
    readme: GitHubREADME?
) -> RepositoryCardContent {
    let repository = repositoryWallRepository(id: id, fullName: fullName)
    return RepositoryCardContent(
        content: RepositoryContent(
            repository: repository,
            localRecord: LocalRepositoryRecord(
                repository: repository,
                localURL: URL(filePath: "/tmp/\(repository.name)"),
                availability: .available,
                localSizeInBytes: 1_024,
                lastInspectedAt: Date(timeIntervalSince1970: 1_000)
            ),
            localStatus: LocalRepositoryStatus(
                branch: "main",
                upstream: "origin/main",
                ahead: 0,
                behind: 0,
                stagedCount: 0,
                unstagedCount: 0,
                untrackedCount: 0,
                conflictCount: 0
            ),
            onlineSummary: RepositoryOnlineSummary(
                repositoryID: id,
                primaryLanguage: "Swift",
                openIssueCount: 0,
                openPullRequestCount: 0,
                failedWorkflowCount: 0,
                remoteUpdatedAt: Date(timeIntervalSince1970: 2_000)
            ),
            recentCommits: [],
            readme: readme,
            connectivity: .online,
            panelErrors: []
        ),
        syncMode: .automatic
    )
}

private func repositoryWallRepository(
    id: Int64,
    fullName: String,
    isPrivate: Bool = false,
    sizeInKilobytes: Int = 1_024
) -> Repository {
    Repository(
        id: id,
        name: fullName.split(separator: "/").last.map(String.init) ?? fullName,
        fullName: fullName,
        isPrivate: isPrivate,
        defaultBranch: "main",
        sizeInKilobytes: sizeInKilobytes,
        cloneURL: URL(string: "https://github.example/\(fullName).git")!,
        ownerAvatarURL: nil
    )
}

private func validRepositoryWallCoverData() -> Data {
    let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 320,
        pixelsHigh: 280,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    return representation.representation(
        using: .png,
        properties: [:]
    )!
}
