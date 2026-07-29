import Foundation
import GitMateCore

let repositoryWallViewModelTests = [
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
        let imageData = Data([0x01, 0x02, 0x03])
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
    }
]

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
