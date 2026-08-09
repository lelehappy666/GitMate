import Foundation
import Observation

public enum CloudRepositoryLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case rateLimited(resetAt: Date)
    case failed(message: String)
}

@MainActor
@Observable
public final class CloudRepositoryViewModel {
    public private(set) var repositories: [Repository] = []
    public private(set) var matchedExcludedRepositories: [Repository] = []
    public private(set) var hasNextPage = true
    public private(set) var phase: CloudRepositoryLoadPhase = .idle
    public var searchText = ""
    public var visibility: RepositoryVisibilityFilter = .all

    @ObservationIgnored
    private let api: any GitHubAPI

    @ObservationIgnored
    private let token: String

    @ObservationIgnored
    private let excludedRepositoryIDs: Set<Int64>

    @ObservationIgnored
    private let excludedRepositoryFullNames: Set<String>

    @ObservationIgnored
    private let pageSize: Int

    @ObservationIgnored
    private var currentPage = 0

    @ObservationIgnored
    private var generation = 0

    @ObservationIgnored
    private var activeLoadTask: Task<GitHubRepositoryPage, Error>?

    public init(
        api: any GitHubAPI,
        token: String,
        excludedRepositoryIDs: Set<Int64>,
        excludedRepositoryFullNames: Set<String> = [],
        pageSize: Int = 30
    ) {
        self.api = api
        self.token = token
        self.excludedRepositoryIDs = excludedRepositoryIDs
        self.excludedRepositoryFullNames = Set(
            excludedRepositoryFullNames.map(
                Repository.normalizedFullName
            )
        )
        self.pageSize = min(max(pageSize, 1), 100)
    }

    public var filteredRepositories: [Repository] {
        let normalizedSearch = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return repositories.filter { repository in
            let matchesVisibility = switch visibility {
            case .all:
                true
            case .publicOnly:
                !repository.isPrivate
            case .privateOnly:
                repository.isPrivate
            }
            let matchesSearch = normalizedSearch.isEmpty
                || repository.fullName.localizedCaseInsensitiveContains(
                    normalizedSearch
                )
            return matchesVisibility && matchesSearch
        }
    }

    public func loadNextPage() async {
        guard activeLoadTask == nil, hasNextPage else {
            return
        }
        let requestGeneration = generation
        let requestedPage = currentPage + 1
        phase = .loading
        let task = Task {
            try await api.repositoryPage(
                token: token,
                page: requestedPage,
                perPage: pageSize
            )
        }
        activeLoadTask = task
        defer {
            if generation == requestGeneration {
                activeLoadTask = nil
            }
        }

        do {
            let page = try await task.value
            guard generation == requestGeneration else {
                return
            }
            var matchedIDs = Set(
                matchedExcludedRepositories.map(\.id)
            )
            matchedExcludedRepositories.append(
                contentsOf: page.repositories.filter {
                    isExcluded($0)
                        && matchedIDs.insert($0.id).inserted
                }
            )
            var knownIDs = Set(repositories.map(\.id))
            let additions = page.repositories.filter {
                !isExcluded($0)
                    && knownIDs.insert($0.id).inserted
            }
            repositories.append(contentsOf: additions)
            currentPage = page.page
            hasNextPage = page.hasNextPage
            phase = .loaded
        } catch is CancellationError {
            if generation == requestGeneration {
                phase = .idle
            }
        } catch let GitHubAPIError.rateLimited(resetAt) {
            guard generation == requestGeneration else {
                return
            }
            hasNextPage = false
            phase = .rateLimited(resetAt: resetAt)
        } catch {
            guard generation == requestGeneration else {
                return
            }
            phase = .failed(message: error.localizedDescription)
        }
    }

    public func refresh() async {
        generation += 1
        activeLoadTask?.cancel()
        activeLoadTask = nil
        repositories = []
        matchedExcludedRepositories = []
        currentPage = 0
        hasNextPage = true
        phase = .idle
        await loadNextPage()
    }

    private func isExcluded(_ repository: Repository) -> Bool {
        excludedRepositoryIDs.contains(repository.id)
            || excludedRepositoryFullNames.contains(
                repository.normalizedFullName
            )
    }
}
