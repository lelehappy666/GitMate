import Foundation
import Observation

@MainActor
@Observable
public final class WorkingTreeViewModel {
    public private(set) var snapshot: WorkingTreeSnapshot?
    public private(set) var visibleFiles: [WorkingTreeFile] = []
    public private(set) var selection: Set<WorkingTreeFile.ID> = []
    public private(set) var error: LocalGitUserFacingError?
    public private(set) var searchText = ""
    public var filter: WorkingTreeFilter = .all {
        didSet {
            scheduleFullFilter()
        }
    }

    private let repositoryURL: URL
    private let reader: any WorkingTreeReading
    private let watcher: (any RepositoryFileSystemWatching)?
    private let mutationService: (any GitDiffServicing)?
    private var allFiles: [WorkingTreeFile] = []
    private var refreshGeneration: UInt64 = 0
    private var filterGeneration: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    private var filterTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?

    public init(
        repositoryURL: URL,
        reader: any WorkingTreeReading,
        watcher: (any RepositoryFileSystemWatching)? = nil,
        mutationService: (any GitDiffServicing)? = nil
    ) {
        self.repositoryURL = repositoryURL
        self.reader = reader
        self.watcher = watcher
        self.mutationService = mutationService
    }

    public func refresh() async {
        refreshTask?.cancel()
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let task = Task { [weak self] in
            guard let self else {
                return
            }
            await self.load(generation: generation)
        }
        refreshTask = task
        await task.value
    }

    public func updateSearch(_ text: String) {
        searchText = text
        scheduleFullFilter()
    }

    public func toggleSelection(_ id: WorkingTreeFile.ID) {
        guard allFiles.contains(where: { $0.id == id }) else {
            return
        }
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    public func stageSelection() async {
        guard let mutationService else {
            return
        }
        let paths = allFiles
            .filter {
                selection.contains($0.id)
                    && $0.category != .staged
                    && $0.category != .conflicted
            }
            .map(\.path)
        guard !paths.isEmpty else {
            return
        }
        await performMutation {
            try await mutationService.stage(
                repositoryURL: repositoryURL,
                paths: paths
            )
        }
    }

    public func unstageSelection() async {
        guard let mutationService else {
            return
        }
        let paths = allFiles
            .filter {
                selection.contains($0.id) && $0.category == .staged
            }
            .map(\.path)
        guard !paths.isEmpty else {
            return
        }
        await performMutation {
            try await mutationService.unstage(
                repositoryURL: repositoryURL,
                paths: paths
            )
        }
    }

    public func startAutomaticRefresh() {
        guard watchTask == nil, let watcher else {
            return
        }
        let repositoryURL = repositoryURL
        watchTask = Task { [weak self, watcher] in
            for await _ in watcher.events(repositoryURL: repositoryURL) {
                guard !Task.isCancelled else {
                    return
                }
                guard let self else {
                    return
                }
                await self.refresh()
            }
        }
    }

    public func stopAutomaticRefresh() {
        watchTask?.cancel()
        watchTask = nil
    }

    private func load(generation: UInt64) async {
        do {
            let tracked = try await reader.trackedSnapshot(
                repositoryURL: repositoryURL,
                generation: generation
            )
            guard generation == refreshGeneration,
                  !Task.isCancelled
            else {
                return
            }

            allFiles = tracked.files
            publishSnapshot(
                branch: tracked.branch,
                untrackedScan: .loading(received: 0),
                generation: generation
            )
            selection.formIntersection(Set(allFiles.map(\.id)))
            applyFullFilterSynchronously()

            var untrackedCount = 0
            for try await batch in reader.untrackedBatches(
                repositoryURL: repositoryURL,
                generation: generation,
                batchSize: 200
            ) {
                guard generation == refreshGeneration,
                      batch.generation == generation,
                      !Task.isCancelled
                else {
                    return
                }
                allFiles.append(contentsOf: batch.files)
                untrackedCount += batch.files.count
                publishSnapshot(
                    branch: tracked.branch,
                    untrackedScan: batch.isLast
                        ? .completed(total: untrackedCount)
                        : .loading(received: untrackedCount),
                    generation: generation
                )
                appendVisibleFiles(from: batch.files)
            }

            guard generation == refreshGeneration,
                  !Task.isCancelled
            else {
                return
            }
            publishSnapshot(
                branch: tracked.branch,
                untrackedScan: .completed(total: untrackedCount),
                generation: generation
            )
            selection.formIntersection(Set(allFiles.map(\.id)))
            error = nil
        } catch is CancellationError {
            return
        } catch GitCommandError.cancelled {
            return
        } catch {
            guard generation == refreshGeneration else {
                return
            }
            self.error = LocalGitUserFacingError(
                message: GitOutputRedactor.redact(
                    error.localizedDescription
                ),
                recoverySuggestion: "请刷新仓库状态后重试。"
            )
        }
    }

    private func performMutation(
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            selection.removeAll()
            await refresh()
        } catch {
            self.error = LocalGitUserFacingError(
                message: GitOutputRedactor.redact(
                    error.localizedDescription
                ),
                recoverySuggestion: "请刷新状态后重试。"
            )
        }
    }

    private func publishSnapshot(
        branch: LocalBranchStatus,
        untrackedScan: UntrackedScanState,
        generation: UInt64
    ) {
        snapshot = WorkingTreeSnapshot(
            branch: branch,
            files: allFiles,
            untrackedScan: untrackedScan,
            generation: generation
        )
    }

    private func appendVisibleFiles(from files: [WorkingTreeFile]) {
        if searchText.isEmpty, filter == .all {
            visibleFiles = allFiles
            return
        }
        visibleFiles.append(
            contentsOf: Self.filtered(
                files,
                searchText: searchText,
                filter: filter
            )
        )
    }

    private func scheduleFullFilter() {
        filterTask?.cancel()
        filterGeneration &+= 1
        let generation = filterGeneration
        let files = allFiles
        let searchText = searchText
        let filter = filter

        filterTask = Task { [weak self] in
            let filteredFiles = await Task.detached(
                priority: .userInitiated
            ) {
                Self.filtered(
                    files,
                    searchText: searchText,
                    filter: filter
                )
            }.value
            guard let self,
                  generation == self.filterGeneration,
                  !Task.isCancelled
            else {
                return
            }
            self.visibleFiles = filteredFiles
        }
    }

    private func applyFullFilterSynchronously() {
        visibleFiles = Self.filtered(
            allFiles,
            searchText: searchText,
            filter: filter
        )
    }

    private nonisolated static func filtered(
        _ files: [WorkingTreeFile],
        searchText: String,
        filter: WorkingTreeFilter
    ) -> [WorkingTreeFile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return files.filter { file in
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .conflicted:
                matchesFilter = file.category == .conflicted
            case .staged:
                matchesFilter = file.category == .staged
            case .unstaged:
                matchesFilter = file.category == .unstaged
            case .untracked:
                matchesFilter = file.category == .untracked
            }
            let matchesSearch = query.isEmpty
                || file.path.localizedCaseInsensitiveContains(query)
            return matchesFilter && matchesSearch
        }
    }
}
