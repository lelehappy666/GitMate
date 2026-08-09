import Foundation
import GitMateCore

private let resolverRepository = Repository(
    id: 501,
    name: "cover-repository",
    fullName: "lele/cover-repository",
    isPrivate: false,
    defaultBranch: "main",
    sizeInKilobytes: 1_024,
    cloneURL: URL(
        string: "https://github.com/lele/cover-repository.git"
    )!,
    ownerAvatarURL: nil
)

private final class ResolverGitHubAPI: GitHubWorkspaceAPI,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let readmeResult: Result<GitHubREADME, Error>
    private var readmeRequests = 0

    init(readmeResult: Result<GitHubREADME, Error>) {
        self.readmeResult = readmeResult
    }

    func repositorySummary(
        repository: Repository,
        token: String
    ) async throws -> RepositoryOnlineSummary {
        throw WorkspaceAPIError.invalidResponse
    }

    func readme(
        repository: Repository,
        token: String
    ) async throws -> GitHubREADME {
        lock.withLock {
            readmeRequests += 1
        }
        return try readmeResult.get()
    }

    var readmeRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return readmeRequests
    }
}

private actor ResolverCoverLoader: RepositoryCoverLoading {
    private let entry: RepositoryCoverCacheEntry
    private var requests = 0

    init(entry: RepositoryCoverCacheEntry) {
        self.entry = entry
    }

    func load(
        repositoryID: Int64,
        sourceURL: URL
    ) async throws -> RepositoryCoverCacheEntry {
        requests += 1
        return entry
    }

    func requestCount() -> Int {
        requests
    }
}

private func resolverCache() -> (
    cache: RepositoryCoverCache,
    root: URL,
    entry: RepositoryCoverCacheEntry
) {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "GitMate-Resolver-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    let sourceURL = URL(string: "https://images.example/old.png")!
    let metadata = RepositoryCoverCacheMetadata(
        contentType: "image/png",
        storedAt: Date(timeIntervalSince1970: 1_000),
        pixelWidth: 640,
        pixelHeight: 960
    )
    let cache = RepositoryCoverCache(rootDirectory: root)
    try? cache.save(
        data: Data("old-cover".utf8),
        metadata: metadata,
        repositoryID: resolverRepository.id,
        sourceURL: sourceURL
    )
    let entry = try! cache.latest(repositoryID: resolverRepository.id)!
    return (cache, root, entry)
}

let repositoryCoverResolverTests = [
    TestCase("正常浏览直接复用最近封面且不发网络请求") {
        let fixture = resolverCache()
        defer {
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let github = ResolverGitHubAPI(
            readmeResult: .failure(URLError(.notConnectedToInternet))
        )
        let loader = ResolverCoverLoader(entry: fixture.entry)
        let resolver = RepositoryCoverResolver(
            github: github,
            cache: fixture.cache,
            loader: loader,
            rateLimitGate: WorkspaceRateLimitGate()
        )

        let result = try await resolver.resolve(
            repository: resolverRepository,
            token: "secret",
            policy: .useCache
        )
        let loaderRequests = await loader.requestCount()

        try expectEqual(result, fixture.entry, "已有缓存应直接返回磁盘封面")
        try expectEqual(
            github.readmeRequestCount,
            0,
            "正常浏览不得重复请求 README"
        )
        try expectEqual(loaderRequests, 0, "正常浏览不得重新下载图片")
    },
    TestCase("手动刷新只为当前仓库检查 README 并更新封面") {
        let fixture = resolverCache()
        defer {
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let newURL = URL(string: "https://images.example/new.png")!
        let github = ResolverGitHubAPI(
            readmeResult: .success(
                GitHubREADME(
                    repositoryID: resolverRepository.id,
                    path: "README.md",
                    markdown: "![主图](\(newURL.absoluteString))",
                    downloadURL: URL(
                        string: "https://raw.githubusercontent.com/lele/cover-repository/main/README.md"
                    )
                )
            )
        )
        let newEntry = RepositoryCoverCacheEntry(
            data: Data("new-cover".utf8),
            metadata: RepositoryCoverCacheMetadata(
                contentType: "image/png",
                storedAt: Date(timeIntervalSince1970: 2_000),
                pixelWidth: 640,
                pixelHeight: 960,
                sourceURL: newURL
            )
        )
        let loader = ResolverCoverLoader(entry: newEntry)
        let resolver = RepositoryCoverResolver(
            github: github,
            cache: fixture.cache,
            loader: loader,
            rateLimitGate: WorkspaceRateLimitGate()
        )

        let result = try await resolver.resolve(
            repository: resolverRepository,
            token: "secret",
            policy: .revalidate
        )
        let loaderRequests = await loader.requestCount()

        try expectEqual(
            result?.data,
            newEntry.data,
            "刷新应返回 README 的新封面数据"
        )
        try expectEqual(
            result?.metadata.sourceURL,
            newURL,
            "刷新应记录 README 的新封面地址"
        )
        try expectEqual(github.readmeRequestCount, 1, "只检查当前仓库 README")
        try expectEqual(loaderRequests, 1, "新地址只下载一次")
    },
    TestCase("刷新失败时保留已经加载过的旧封面") {
        let fixture = resolverCache()
        defer {
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let github = ResolverGitHubAPI(
            readmeResult: .failure(URLError(.notConnectedToInternet))
        )
        let loader = ResolverCoverLoader(entry: fixture.entry)
        let resolver = RepositoryCoverResolver(
            github: github,
            cache: fixture.cache,
            loader: loader,
            rateLimitGate: WorkspaceRateLimitGate()
        )

        let result = try await resolver.resolve(
            repository: resolverRepository,
            token: "secret",
            policy: .revalidate
        )

        try expectEqual(result, fixture.entry, "刷新失败不得清空旧封面")
    }
]
