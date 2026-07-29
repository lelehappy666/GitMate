import Foundation
import GitMateCore

private actor ViewportResolver: RepositoryCoverResolving {
    private var activeCount = 0
    private var maximumActiveCount = 0
    private var requestedIDs: [Int64] = []

    func resolve(
        repository: Repository,
        token: String,
        policy: RepositoryCoverResolvePolicy
    ) async throws -> RepositoryCoverCacheEntry? {
        requestedIDs.append(repository.id)
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        defer {
            activeCount -= 1
        }
        try await Task.sleep(for: .milliseconds(20))
        return nil
    }

    func maximumConcurrency() -> Int {
        maximumActiveCount
    }

    func requests() -> [Int64] {
        requestedIDs
    }
}

private func viewportRepository(_ id: Int64) -> Repository {
    Repository(
        id: id,
        name: "viewport-\(id)",
        fullName: "lele/viewport-\(id)",
        isPrivate: false,
        defaultBranch: "main",
        sizeInKilobytes: 1_024,
        cloneURL: URL(
            string: "https://github.com/lele/viewport-\(id).git"
        )!,
        ownerAvatarURL: nil
    )
}

let repositoryCoverViewportSchedulerTests = [
    TestCase("封面需求只包含当前窗口和下一行") {
        let demand = RepositoryCoverViewportDemand.make(
            orderedRepositoryIDs: Array(1...20).map(Int64.init),
            visibleRepositoryIDs: [5, 6, 7, 8],
            columnCount: 4
        )

        try expectEqual(
            demand.visible,
            [5, 6, 7, 8],
            "当前窗口卡片必须优先"
        )
        try expectEqual(
            demand.prefetch,
            [9, 10, 11, 12],
            "只预加载下一行"
        )
    },
    TestCase("封面调度最多并发三路且不加载远处仓库") {
        let resolver = ViewportResolver()
        let scheduler = RepositoryCoverViewportScheduler(
            resolver: resolver,
            maximumConcurrentLoads: 3
        )
        let repositories = Dictionary(
            uniqueKeysWithValues: (1...20).map {
                let repository = viewportRepository(Int64($0))
                return (repository.id, repository)
            }
        )
        let demand = RepositoryCoverViewportDemand.make(
            orderedRepositoryIDs: Array(1...20).map(Int64.init),
            visibleRepositoryIDs: [5, 6, 7, 8],
            columnCount: 4
        )

        _ = await scheduler.load(
            demand: demand,
            repositories: repositories,
            token: "secret",
            refreshIDs: []
        )
        let maximumConcurrency = await resolver.maximumConcurrency()
        let requests = await resolver.requests()

        try expect(
            maximumConcurrency <= 3,
            "封面网络请求最多并发三路"
        )
        try expectEqual(
            Set(requests),
            Set([5, 6, 7, 8, 9, 10, 11, 12]),
            "不可加载窗口和下一行之外的封面"
        )
    }
]
