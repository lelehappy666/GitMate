import Foundation

public struct RepositoryCoverViewportDemand: Equatable, Sendable {
    public let visible: [Int64]
    public let prefetch: [Int64]

    public init(visible: [Int64], prefetch: [Int64]) {
        self.visible = visible
        self.prefetch = prefetch
    }

    public static func make(
        orderedRepositoryIDs: [Int64],
        visibleRepositoryIDs: Set<Int64>,
        columnCount: Int
    ) -> RepositoryCoverViewportDemand {
        let visible = orderedRepositoryIDs.filter(
            visibleRepositoryIDs.contains
        )
        guard !visible.isEmpty else {
            return RepositoryCoverViewportDemand(
                visible: [],
                prefetch: []
            )
        }

        let columns = max(columnCount, 1)
        let lastVisibleIndex = orderedRepositoryIDs.indices.last {
            visibleRepositoryIDs.contains(
                orderedRepositoryIDs[$0]
            )
        } ?? 0
        let nextRowStart = ((lastVisibleIndex / columns) + 1) * columns
        guard nextRowStart < orderedRepositoryIDs.count else {
            return RepositoryCoverViewportDemand(
                visible: visible,
                prefetch: []
            )
        }
        let nextRowEnd = min(
            nextRowStart + columns,
            orderedRepositoryIDs.count
        )
        let prefetch = orderedRepositoryIDs[
            nextRowStart..<nextRowEnd
        ].filter {
            !visibleRepositoryIDs.contains($0)
        }
        return RepositoryCoverViewportDemand(
            visible: visible,
            prefetch: Array(prefetch)
        )
    }
}

public struct RepositoryCoverViewportResult: Equatable, Sendable {
    public let repositoryID: Int64
    public let entry: RepositoryCoverCacheEntry?

    public init(
        repositoryID: Int64,
        entry: RepositoryCoverCacheEntry?
    ) {
        self.repositoryID = repositoryID
        self.entry = entry
    }
}

public actor RepositoryCoverViewportScheduler {
    private let resolver: any RepositoryCoverResolving
    private let maximumConcurrentLoads: Int

    public init(
        resolver: any RepositoryCoverResolving,
        maximumConcurrentLoads: Int = 3
    ) {
        self.resolver = resolver
        self.maximumConcurrentLoads = max(
            maximumConcurrentLoads,
            1
        )
    }

    public func load(
        demand: RepositoryCoverViewportDemand,
        repositories: [Int64: Repository],
        token: String,
        refreshIDs: Set<Int64>
    ) async -> [RepositoryCoverViewportResult] {
        var seen = Set<Int64>()
        let queue = (demand.visible + demand.prefetch).filter {
            seen.insert($0).inserted && repositories[$0] != nil
        }
        guard !queue.isEmpty else {
            return []
        }

        let resolver = self.resolver
        let maximumConcurrentLoads = self.maximumConcurrentLoads
        var iterator = queue.makeIterator()
        var results: [RepositoryCoverViewportResult] = []
        await withTaskGroup(
            of: RepositoryCoverViewportResult?.self
        ) { group in
            func addNext() {
                guard
                    let repositoryID = iterator.next(),
                    let repository = repositories[repositoryID]
                else {
                    return
                }
                group.addTask {
                    guard !Task.isCancelled else {
                        return nil
                    }
                    let policy: RepositoryCoverResolvePolicy =
                        refreshIDs.contains(repositoryID)
                        ? .revalidate
                        : .useCache
                    do {
                        let entry = try await resolver.resolve(
                            repository: repository,
                            token: token,
                            policy: policy
                        )
                        return RepositoryCoverViewportResult(
                            repositoryID: repositoryID,
                            entry: entry
                        )
                    } catch is CancellationError {
                        return nil
                    } catch {
                        return RepositoryCoverViewportResult(
                            repositoryID: repositoryID,
                            entry: nil
                        )
                    }
                }
            }

            for _ in 0..<min(
                maximumConcurrentLoads,
                queue.count
            ) {
                addNext()
            }
            while let result = await group.next() {
                if let result {
                    results.append(result)
                }
                if !Task.isCancelled {
                    addNext()
                }
            }
        }

        let order = Dictionary(
            uniqueKeysWithValues: queue.enumerated().map {
                ($0.element, $0.offset)
            }
        )
        return results.sorted {
            order[$0.repositoryID, default: .max]
                < order[$1.repositoryID, default: .max]
        }
    }
}
