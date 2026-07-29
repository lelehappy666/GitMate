import Foundation
import GitMateCore

private func cloudRepository(_ id: Int64) -> Repository {
    Repository(
        id: id,
        name: "cloud-\(id)",
        fullName: "lele/cloud-\(id)",
        isPrivate: id.isMultiple(of: 2),
        defaultBranch: "main",
        sizeInKilobytes: Int(id) * 100,
        cloneURL: URL(
            string: "https://github.com/lele/cloud-\(id).git"
        )!,
        ownerAvatarURL: nil
    )
}

private actor PagedRepositoryAPI: GitHubAPI {
    private let pages: [Int: GitHubRepositoryPage]
    private let failure: GitHubAPIError?
    private let delayNanoseconds: UInt64
    private var requests: [(page: Int, perPage: Int)] = []

    init(
        pages: [Int: GitHubRepositoryPage] = [:],
        failure: GitHubAPIError? = nil,
        delayNanoseconds: UInt64 = 0
    ) {
        self.pages = pages
        self.failure = failure
        self.delayNanoseconds = delayNanoseconds
    }

    func currentUser(token: String) async throws -> GitHubAccount {
        throw GitHubAPIError.invalidResponse
    }

    func repositories(token: String) async throws -> [Repository] {
        pages.keys.sorted().flatMap {
            pages[$0]?.repositories ?? []
        }
    }

    func repositoryPage(
        token: String,
        page: Int,
        perPage: Int
    ) async throws -> GitHubRepositoryPage {
        requests.append((page, perPage))
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let failure {
            throw failure
        }
        return pages[page] ?? GitHubRepositoryPage(
            repositories: [],
            page: page,
            hasNextPage: false
        )
    }

    func requestedPages() -> [Int] {
        requests.map(\.page)
    }

    func requestedPageSizes() -> [Int] {
        requests.map(\.perPage)
    }
}

private actor RefreshingRepositoryAPI: GitHubAPI {
    private var requestCount = 0

    func currentUser(token: String) async throws -> GitHubAccount {
        throw GitHubAPIError.invalidResponse
    }

    func repositories(token: String) async throws -> [Repository] {
        []
    }

    func repositoryPage(
        token: String,
        page: Int,
        perPage: Int
    ) async throws -> GitHubRepositoryPage {
        requestCount += 1
        let currentRequest = requestCount
        if currentRequest == 1 {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        return GitHubRepositoryPage(
            repositories: [
                cloudRepository(currentRequest == 1 ? 1 : 2)
            ],
            page: 1,
            hasNextPage: false
        )
    }

    func count() -> Int {
        requestCount
    }
}

private func waitForCloudRequest(
    _ api: RefreshingRepositoryAPI
) async throws {
    for _ in 0..<100 {
        if await api.count() > 0 {
            return
        }
        await Task.yield()
    }
    throw TestFailure(description: "云端请求没有开始")
}

let cloudRepositoryViewModelTests = [
    TestCase("云端仓库首次只加载三十条并排除本地仓库") { @MainActor in
        let api = PagedRepositoryAPI(
            pages: [
                1: GitHubRepositoryPage(
                    repositories: [
                        cloudRepository(1),
                        cloudRepository(1),
                        cloudRepository(2),
                        cloudRepository(3)
                    ],
                    page: 1,
                    hasNextPage: true
                )
            ]
        )
        let viewModel = CloudRepositoryViewModel(
            api: api,
            token: "secret",
            excludedRepositoryIDs: [2]
        )

        await viewModel.loadNextPage()

        let requestedPages = await api.requestedPages()
        let requestedPageSizes = await api.requestedPageSizes()
        try expectEqual(
            viewModel.repositories.map(\.id),
            [1, 3],
            "本地集合中的仓库不得出现在云端页"
        )
        try expectEqual(
            requestedPages,
            [1],
            "首次只能请求第一页"
        )
        try expectEqual(
            requestedPageSizes,
            [30],
            "云端列表每页固定三十条"
        )
    },
    TestCase("云端仓库下一页追加时按编号去重") { @MainActor in
        let api = PagedRepositoryAPI(
            pages: [
                1: GitHubRepositoryPage(
                    repositories: [
                        cloudRepository(1),
                        cloudRepository(2)
                    ],
                    page: 1,
                    hasNextPage: true
                ),
                2: GitHubRepositoryPage(
                    repositories: [
                        cloudRepository(2),
                        cloudRepository(3)
                    ],
                    page: 2,
                    hasNextPage: false
                )
            ]
        )
        let viewModel = CloudRepositoryViewModel(
            api: api,
            token: "secret",
            excludedRepositoryIDs: []
        )

        await viewModel.loadNextPage()
        await viewModel.loadNextPage()

        try expectEqual(
            viewModel.repositories.map(\.id),
            [1, 2, 3],
            "分页重复仓库不得重复显示"
        )
        try expect(!viewModel.hasNextPage, "最后一页后不应继续请求")
    },
    TestCase("云端仓库并发重复加载只发起一次请求") { @MainActor in
        let api = PagedRepositoryAPI(
            pages: [
                1: GitHubRepositoryPage(
                    repositories: [cloudRepository(1)],
                    page: 1,
                    hasNextPage: false
                )
            ],
            delayNanoseconds: 40_000_000
        )
        let viewModel = CloudRepositoryViewModel(
            api: api,
            token: "secret",
            excludedRepositoryIDs: []
        )

        async let first: Void = viewModel.loadNextPage()
        async let second: Void = viewModel.loadNextPage()
        _ = await (first, second)

        let requestedPages = await api.requestedPages()
        try expectEqual(
            requestedPages,
            [1],
            "同一页加载中不得重复请求"
        )
    },
    TestCase("云端仓库限流状态保留恢复时间") { @MainActor in
        let resetAt = Date(timeIntervalSince1970: 2_000)
        let api = PagedRepositoryAPI(
            failure: .rateLimited(resetAt: resetAt)
        )
        let viewModel = CloudRepositoryViewModel(
            api: api,
            token: "secret",
            excludedRepositoryIDs: []
        )

        await viewModel.loadNextPage()

        try expectEqual(
            viewModel.phase,
            .rateLimited(resetAt: resetAt),
            "限流后页面必须显示可恢复时间"
        )
        try expect(!viewModel.hasNextPage, "限流后不得自动继续请求")
    },
    TestCase("刷新云端仓库取消旧请求并只保留新结果") { @MainActor in
        let api = RefreshingRepositoryAPI()
        let viewModel = CloudRepositoryViewModel(
            api: api,
            token: "secret",
            excludedRepositoryIDs: []
        )
        let oldLoad = Task { @MainActor in
            await viewModel.loadNextPage()
        }
        try await waitForCloudRequest(api)

        await viewModel.refresh()
        await oldLoad.value

        let requestCount = await api.count()
        try expectEqual(
            viewModel.repositories.map(\.id),
            [2],
            "刷新后的第一页不得被旧请求覆盖"
        )
        try expectEqual(
            requestCount,
            2,
            "刷新应重新请求第一页"
        )
    }
]
