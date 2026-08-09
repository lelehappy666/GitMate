import Foundation

public enum RepositoryCoverResolvePolicy: Equatable, Sendable {
    case useCache
    case revalidate
}

public protocol RepositoryCoverResolving: Sendable {
    func resolve(
        repository: Repository,
        token: String,
        policy: RepositoryCoverResolvePolicy
    ) async throws -> RepositoryCoverCacheEntry?
}

public final class RepositoryCoverResolver:
    RepositoryCoverResolving,
    @unchecked Sendable
{
    private let github: any GitHubWorkspaceAPI
    private let cache: any RepositoryCoverCaching
    private let loader: any RepositoryCoverLoading
    private let rateLimitGate: WorkspaceRateLimitGate
    private let now: @Sendable () -> Date
    private let extractor = RepositoryCoverExtractor()

    public init(
        github: any GitHubWorkspaceAPI,
        cache: any RepositoryCoverCaching,
        loader: any RepositoryCoverLoading,
        rateLimitGate: WorkspaceRateLimitGate,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.github = github
        self.cache = cache
        self.loader = loader
        self.rateLimitGate = rateLimitGate
        self.now = now
    }

    public func resolve(
        repository: Repository,
        token: String,
        policy: RepositoryCoverResolvePolicy
    ) async throws -> RepositoryCoverCacheEntry? {
        try Task.checkCancellation()
        let cached = try cache.latest(repositoryID: repository.id)
        if policy == .useCache, let cached {
            return cached
        }

        do {
            try rateLimitGate.check(now: now())
            let readme = try await github.readme(
                repository: repository,
                token: token
            )
            try Task.checkCancellation()
            guard let candidate = extractor.firstCandidate(
                markdown: readme.markdown,
                baseURL: readme.downloadURL
            ) else {
                return cached
            }
            if let cached,
               cached.metadata.sourceURL == candidate.url {
                try cache.save(
                    data: cached.data,
                    metadata: refreshedMetadata(
                        cached.metadata,
                        sourceURL: candidate.url
                    ),
                    repositoryID: repository.id,
                    sourceURL: candidate.url
                )
                return try cache.latest(repositoryID: repository.id) ?? cached
            }
            let loaded = try await loader.load(
                repositoryID: repository.id,
                sourceURL: candidate.url
            )
            try Task.checkCancellation()
            try cache.save(
                data: loaded.data,
                metadata: refreshedMetadata(
                    loaded.metadata,
                    sourceURL: candidate.url
                ),
                repositoryID: repository.id,
                sourceURL: candidate.url
            )
            return try cache.latest(repositoryID: repository.id) ?? loaded
        } catch is CancellationError {
            throw CancellationError()
        } catch let WorkspaceAPIError.rateLimited(resetAt) {
            rateLimitGate.pause(until: resetAt)
            if let cached {
                return cached
            }
            throw WorkspaceAPIError.rateLimited(resetAt: resetAt)
        } catch {
            if let cached {
                return cached
            }
            throw error
        }
    }

    private func refreshedMetadata(
        _ metadata: RepositoryCoverCacheMetadata,
        sourceURL: URL
    ) -> RepositoryCoverCacheMetadata {
        RepositoryCoverCacheMetadata(
            contentType: metadata.contentType,
            storedAt: now(),
            pixelWidth: metadata.pixelWidth,
            pixelHeight: metadata.pixelHeight,
            sourceURL: sourceURL,
            contentHash: metadata.contentHash,
            etag: metadata.etag,
            lastModified: metadata.lastModified,
            needsRefresh: false
        )
    }
}
