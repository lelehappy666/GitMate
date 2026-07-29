import Foundation
import Observation

public enum RepositoryWallSort: String, CaseIterable, Equatable, Sendable {
    case recentlyUpdated
    case name
    case size
}

public enum RepositoryVisibilityFilter: String, CaseIterable, Equatable, Sendable {
    case all
    case publicOnly
    case privateOnly
}

public enum RepositorySyncState: String, CaseIterable, Equatable, Sendable {
    case synchronized
    case needsAttention
    case notSynchronized
    case unavailable
}

public enum RepositorySyncStateFilter: String, CaseIterable, Equatable, Sendable {
    case all
    case synchronized
    case needsAttention
    case notSynchronized
    case unavailable
}

public struct RepositoryCardContent: Equatable, Sendable {
    public let content: RepositoryContent
    public let syncMode: RepositorySyncMode

    public init(
        content: RepositoryContent,
        syncMode: RepositorySyncMode
    ) {
        self.content = content
        self.syncMode = syncMode
    }
}

public enum RepositoryPosterCover: Equatable, Sendable {
    case cached(
        data: Data,
        sourceURL: URL,
        fallback: FallbackRepositoryCover
    )
    case remote(
        sourceURL: URL,
        fallback: FallbackRepositoryCover
    )
    case fallback(FallbackRepositoryCover)

    public var fallback: FallbackRepositoryCover {
        switch self {
        case let .cached(_, _, fallback),
             let .remote(_, fallback),
             let .fallback(fallback):
            fallback
        }
    }

    public var usesREADMEImage: Bool {
        switch self {
        case .cached:
            true
        case .remote, .fallback:
            false
        }
    }
}

public struct RepositoryPosterItem: Identifiable, Equatable, Sendable {
    public var id: Int64 { repository.id }

    public let repository: Repository
    public let language: String?
    public let syncMode: RepositorySyncMode
    public let syncState: RepositorySyncState
    public let updatedAt: Date?
    public let cover: RepositoryPosterCover

    public init(
        repository: Repository,
        language: String?,
        syncMode: RepositorySyncMode,
        syncState: RepositorySyncState,
        updatedAt: Date?,
        cover: RepositoryPosterCover
    ) {
        self.repository = repository
        self.language = language
        self.syncMode = syncMode
        self.syncState = syncState
        self.updatedAt = updatedAt
        self.cover = cover
    }

    public var owner: String {
        repository.fullName.split(
            separator: "/",
            maxSplits: 1,
            omittingEmptySubsequences: true
        ).first.map(String.init) ?? repository.fullName
    }

    public var destination: WorkspaceRoute {
        .repositoryOverview(repositoryID: repository.id)
    }

    public var accessibilityIdentifier: String {
        "workspace.repositories.poster.\(repository.id)"
    }

    public func replacingCover(
        _ cover: RepositoryPosterCover
    ) -> RepositoryPosterItem {
        RepositoryPosterItem(
            repository: repository,
            language: language,
            syncMode: syncMode,
            syncState: syncState,
            updatedAt: updatedAt,
            cover: cover
        )
    }
}

public enum RepositoryPosterBuilder {
    public static func make(
        contents: [RepositoryCardContent],
        extractor: RepositoryCoverExtractor,
        cache: any RepositoryCoverCaching
    ) -> [RepositoryPosterItem] {
        contents.map {
            make(content: $0, extractor: extractor, cache: cache)
        }
    }

    private static func make(
        content card: RepositoryCardContent,
        extractor: RepositoryCoverExtractor,
        cache: any RepositoryCoverCaching
    ) -> RepositoryPosterItem {
        let content = card.content
        let language = content.onlineSummary?.primaryLanguage
        let fallback = FallbackRepositoryCover.make(
            repository: content.repository,
            language: language
        )
        let cover = cover(
            content: content,
            fallback: fallback,
            extractor: extractor,
            cache: cache
        )
        return RepositoryPosterItem(
            repository: content.repository,
            language: language,
            syncMode: card.syncMode,
            syncState: syncState(for: card),
            updatedAt: updatedAt(for: content),
            cover: cover
        )
    }

    private static func cover(
        content: RepositoryContent,
        fallback: FallbackRepositoryCover,
        extractor: RepositoryCoverExtractor,
        cache: any RepositoryCoverCaching
    ) -> RepositoryPosterCover {
        guard let readme = content.readme,
              let candidate = extractor.firstCandidate(
                  markdown: readme.markdown,
                  baseURL: readme.downloadURL
              )
        else {
            return .fallback(fallback)
        }
        if let cached = try? cache.load(
            repositoryID: content.repository.id,
            sourceURL: candidate.url
        ), (try? RepositoryCoverImageValidator.dimensions(
            data: cached.data,
            minimumPixelDimension: 240
        )) != nil {
            return .cached(
                data: cached.data,
                sourceURL: candidate.url,
                fallback: fallback
            )
        }
        return .remote(
            sourceURL: candidate.url,
            fallback: fallback
        )
    }

    private static func syncState(
        for card: RepositoryCardContent
    ) -> RepositorySyncState {
        let content = card.content
        if card.syncMode == .never
            || content.localRecord.availability == .missing
        {
            return .notSynchronized
        }
        if content.localRecord.availability == .damaged
            || content.panelErrors.contains(where: {
                $0.repositoryID == content.repository.id
                    && ($0.panel == .localRepository || $0.panel == .localStatus)
            })
        {
            return .unavailable
        }
        guard let status = content.localStatus else {
            return .needsAttention
        }
        let hasPendingChanges = status.ahead > 0
            || status.behind > 0
            || status.stagedCount > 0
            || status.unstagedCount > 0
            || status.untrackedCount > 0
            || status.conflictCount > 0
        return hasPendingChanges ? .needsAttention : .synchronized
    }

    private static func updatedAt(for content: RepositoryContent) -> Date? {
        content.onlineSummary?.remoteUpdatedAt
            ?? content.recentCommits.map(\.authoredAt).max()
    }
}

public enum RepositoryWallFilter {
    public static func apply(
        _ items: [RepositoryPosterItem],
        searchText: String,
        visibility: RepositoryVisibilityFilter,
        language: String?,
        syncState: RepositorySyncStateFilter,
        sort: RepositoryWallSort
    ) -> [RepositoryPosterItem] {
        let query = normalized(searchText)
        let selectedLanguage = language.map(normalized)
        return items
            .filter { item in
                matchesSearch(item, query: query)
                    && matchesVisibility(item, filter: visibility)
                    && matchesLanguage(item, language: selectedLanguage)
                    && matchesSyncState(item, filter: syncState)
            }
            .sorted { comesFirst($0, $1, sort: sort) }
    }

    private static func matchesSearch(
        _ item: RepositoryPosterItem,
        query: String
    ) -> Bool {
        query.isEmpty
            || normalized(item.repository.name).contains(query)
            || normalized(item.owner).contains(query)
            || normalized(item.repository.fullName).contains(query)
    }

    private static func matchesVisibility(
        _ item: RepositoryPosterItem,
        filter: RepositoryVisibilityFilter
    ) -> Bool {
        switch filter {
        case .all:
            true
        case .publicOnly:
            !item.repository.isPrivate
        case .privateOnly:
            item.repository.isPrivate
        }
    }

    private static func matchesLanguage(
        _ item: RepositoryPosterItem,
        language: String?
    ) -> Bool {
        guard let language else {
            return true
        }
        return item.language.map(normalized) == language
    }

    private static func matchesSyncState(
        _ item: RepositoryPosterItem,
        filter: RepositorySyncStateFilter
    ) -> Bool {
        switch filter {
        case .all:
            true
        case .synchronized:
            item.syncState == .synchronized
        case .needsAttention:
            item.syncState == .needsAttention
        case .notSynchronized:
            item.syncState == .notSynchronized
        case .unavailable:
            item.syncState == .unavailable
        }
    }

    private static func comesFirst(
        _ lhs: RepositoryPosterItem,
        _ rhs: RepositoryPosterItem,
        sort: RepositoryWallSort
    ) -> Bool {
        switch sort {
        case .recentlyUpdated:
            if lhs.updatedAt != rhs.updatedAt {
                switch (lhs.updatedAt, rhs.updatedAt) {
                case let (.some(lhsDate), .some(rhsDate)):
                    return lhsDate > rhsDate
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    break
                }
            }
        case .name:
            break
        case .size:
            if lhs.repository.sizeInKilobytes != rhs.repository.sizeInKilobytes {
                return lhs.repository.sizeInKilobytes
                    > rhs.repository.sizeInKilobytes
            }
        }

        let lhsName = normalized(lhs.repository.fullName)
        let rhsName = normalized(rhs.repository.fullName)
        if lhsName != rhsName {
            return lhsName < rhsName
        }
        return lhs.repository.id < rhs.repository.id
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }
}

@MainActor
@Observable
public final class RepositoryWallViewModel {
    public var searchText = ""
    public var visibility: RepositoryVisibilityFilter = .all
    public var language: String?
    public var syncState: RepositorySyncStateFilter = .all
    public var sort: RepositoryWallSort = .recentlyUpdated
    public private(set) var items: [RepositoryPosterItem]

    @ObservationIgnored
    private let coverLoader: (any RepositoryCoverLoading)?

    public init(
        items: [RepositoryPosterItem],
        coverLoader: (any RepositoryCoverLoading)? = nil
    ) {
        self.items = items
        self.coverLoader = coverLoader
    }

    public var visibleItems: [RepositoryPosterItem] {
        RepositoryWallFilter.apply(
            items,
            searchText: searchText,
            visibility: visibility,
            language: language,
            syncState: syncState,
            sort: sort
        )
    }

    public var availableLanguages: [String] {
        let sortedLanguages = items.compactMap(\.language).sorted {
            let lhs = normalizedLanguage($0)
            let rhs = normalizedLanguage($1)
            return lhs == rhs ? $0 < $1 : lhs < rhs
        }
        return sortedLanguages.reduce(into: []) { result, language in
            guard !result.contains(where: {
                normalizedLanguage($0) == normalizedLanguage(language)
            }) else {
                return
            }
            result.append(language)
        }
    }

    public func updateItems(_ items: [RepositoryPosterItem]) {
        self.items = items
    }

    public func resolvePendingCovers() async {
        guard let coverLoader else {
            return
        }
        let pending = items.compactMap { item -> PendingRepositoryCover? in
            guard case let .remote(sourceURL, fallback) = item.cover else {
                return nil
            }
            return PendingRepositoryCover(
                repositoryID: item.id,
                sourceURL: sourceURL,
                fallback: fallback
            )
        }
        guard !pending.isEmpty else {
            return
        }

        do {
            let resolutions = try await withThrowingTaskGroup(
                of: RepositoryCoverResolution.self
            ) { group in
                for cover in pending {
                    group.addTask {
                        try Task.checkCancellation()
                        do {
                            let entry = try await coverLoader.load(
                                repositoryID: cover.repositoryID,
                                sourceURL: cover.sourceURL
                            )
                            try Task.checkCancellation()
                            return RepositoryCoverResolution(
                                repositoryID: cover.repositoryID,
                                cover: .cached(
                                    data: entry.data,
                                    sourceURL: cover.sourceURL,
                                    fallback: cover.fallback
                                )
                            )
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            return RepositoryCoverResolution(
                                repositoryID: cover.repositoryID,
                                cover: .fallback(cover.fallback)
                            )
                        }
                    }
                }

                var results: [RepositoryCoverResolution] = []
                for try await resolution in group {
                    results.append(resolution)
                }
                return results
            }
            try Task.checkCancellation()
            let covers = Dictionary(
                uniqueKeysWithValues: resolutions.map {
                    ($0.repositoryID, $0.cover)
                }
            )
            items = items.map { item in
                covers[item.id].map(item.replacingCover) ?? item
            }
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    private func normalizedLanguage(_ language: String) -> String {
        language.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

private struct PendingRepositoryCover: Sendable {
    let repositoryID: Int64
    let sourceURL: URL
    let fallback: FallbackRepositoryCover
}

private struct RepositoryCoverResolution: Sendable {
    let repositoryID: Int64
    let cover: RepositoryPosterCover
}
