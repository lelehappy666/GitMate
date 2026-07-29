import Foundation
import Observation

@MainActor
@Observable
public final class CommitGraphViewModel {
    public var viewport = GraphViewport()
    public private(set) var layout = CommitGraphLayoutResult()
    public private(set) var selectedCommit: GitCommitDetail?
    public private(set) var selectedDiff: GitDiff?
    public private(set) var isSelectedDiffTruncated = false
    public private(set) var selectedHash: String?
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var nextCursor: String?
    public private(set) var errorMessage: String?

    @ObservationIgnored
    private let reader: any LocalGitReading

    @ObservationIgnored
    private let repositoryURL: URL

    @ObservationIgnored
    private let pageSize: Int

    @ObservationIgnored
    private let maximumPatchCharacters: Int

    @ObservationIgnored
    private let graphLayout: CommitGraphLayout

    @ObservationIgnored
    private var commits: [GitCommit] = []

    @ObservationIgnored
    private var graphTask: Task<CommitGraphPage, Error>?

    @ObservationIgnored
    private var detailTask: Task<GitCommitDetail, Error>?

    @ObservationIgnored
    private var diffTask: Task<GitDiff, Error>?

    @ObservationIgnored
    private var graphRequestID = UUID()

    @ObservationIgnored
    private var selectionRequestID = UUID()

    public init(
        reader: any LocalGitReading,
        repositoryURL: URL,
        pageSize: Int = 200,
        maximumPatchCharacters: Int = 200_000,
        layout: CommitGraphLayout = CommitGraphLayout()
    ) {
        self.reader = reader
        self.repositoryURL = repositoryURL
        self.pageSize = min(max(pageSize, 1), 200)
        self.maximumPatchCharacters = max(maximumPatchCharacters, 1)
        graphLayout = layout
    }

    public func load() async {
        graphTask?.cancel()
        let requestID = UUID()
        graphRequestID = requestID
        isLoading = true
        isLoadingMore = false
        errorMessage = nil

        let reader = reader
        let repositoryURL = repositoryURL
        let pageSize = pageSize
        let task = Task {
            try await reader.graph(
                repositoryURL: repositoryURL,
                cursor: nil,
                limit: pageSize
            )
        }
        graphTask = task

        do {
            let page = try await task.value
            guard graphRequestID == requestID else { return }
            commits = uniqueCommits(page.commits)
            layout = graphLayout.layout(
                page: CommitGraphPage(
                    commits: commits,
                    nextCursor: page.nextCursor
                )
            )
            nextCursor = page.nextCursor
            isLoading = false
        } catch is CancellationError {
            if graphRequestID == requestID {
                isLoading = false
            }
        } catch {
            guard graphRequestID == requestID else { return }
            isLoading = false
            errorMessage = "无法读取提交图，请稍后重试。"
        }
    }

    public func loadOlderCommits() async {
        guard !isLoading,
              !isLoadingMore,
              let cursor = nextCursor
        else {
            return
        }

        let requestID = UUID()
        graphRequestID = requestID
        isLoadingMore = true
        errorMessage = nil

        let reader = reader
        let repositoryURL = repositoryURL
        let pageSize = pageSize
        let task = Task {
            try await reader.graph(
                repositoryURL: repositoryURL,
                cursor: cursor,
                limit: pageSize
            )
        }
        graphTask = task

        do {
            let page = try await task.value
            guard graphRequestID == requestID else { return }
            commits = uniqueCommits(commits + page.commits)
            layout = graphLayout.layout(
                page: CommitGraphPage(
                    commits: commits,
                    nextCursor: page.nextCursor
                ),
                preserving: layout
            )
            nextCursor = page.nextCursor
            isLoadingMore = false
        } catch is CancellationError {
            if graphRequestID == requestID {
                isLoadingMore = false
            }
        } catch {
            guard graphRequestID == requestID else { return }
            isLoadingMore = false
            errorMessage = "无法加载更早提交，请稍后重试。"
        }
    }

    public func pan(by translation: GraphPoint) {
        viewport.offsetX += translation.x
        viewport.offsetY += translation.y
    }

    public func zoom(by multiplier: Double, anchor: GraphPoint) {
        guard multiplier.isFinite, multiplier > 0 else { return }
        let oldScale = viewport.scale
        let newScale = min(max(oldScale * multiplier, 0.35), 2)
        guard newScale != oldScale else { return }
        let ratio = newScale / oldScale
        viewport.offsetX = anchor.x
            - (anchor.x - viewport.offsetX) * ratio
        viewport.offsetY = anchor.y
            - (anchor.y - viewport.offsetY) * ratio
        viewport.scale = newScale
    }

    public func resetLayout() {
        layout = graphLayout.layout(
            page: CommitGraphPage(
                commits: commits,
                nextCursor: nextCursor
            )
        )
        viewport = GraphViewport()
    }

    public func focusCurrentBranch(
        canvasWidth: Double = 1_040,
        canvasHeight: Double = 680
    ) {
        guard let node = layout.nodes.first(where: {
            $0.decorations.contains {
                $0.contains("HEAD") || $0.contains("main")
            }
        }) ?? layout.nodes.first else {
            return
        }
        viewport.offsetX = canvasWidth / 2 - node.x * viewport.scale
        viewport.offsetY = canvasHeight / 3 - node.y * viewport.scale
    }

    public func select(hash: String) async {
        detailTask?.cancel()
        diffTask?.cancel()
        let requestID = UUID()
        selectionRequestID = requestID
        selectedCommit = nil
        selectedDiff = nil
        isSelectedDiffTruncated = false
        errorMessage = nil

        guard commits.contains(where: { $0.fullHash == hash }) else {
            selectedHash = nil
            errorMessage = "只能查看提交图中的提交。"
            return
        }

        selectedHash = hash
        let reader = reader
        let repositoryURL = repositoryURL
        let detailTask = Task {
            try await reader.commit(
                repositoryURL: repositoryURL,
                hash: hash
            )
        }
        let diffTask = Task {
            try await reader.diff(
                repositoryURL: repositoryURL,
                hash: hash
            )
        }
        self.detailTask = detailTask
        self.diffTask = diffTask

        do {
            let detail = try await detailTask.value
            guard selectionRequestID == requestID,
                  detail.commit.fullHash == hash
            else {
                return
            }
            selectedCommit = detail
        } catch is CancellationError {
            return
        } catch {
            guard selectionRequestID == requestID else { return }
            errorMessage = "无法读取提交详情，请稍后重试。"
            diffTask.cancel()
            return
        }

        do {
            let diff = try await diffTask.value
            guard selectionRequestID == requestID,
                  diff.commitHash == hash
            else {
                return
            }
            selectedDiff = safeDiff(diff)
        } catch is CancellationError {
            return
        } catch {
            guard selectionRequestID == requestID else { return }
            errorMessage = "提交详情已打开，但暂时无法读取差异。"
        }
    }

    public func dismissDetail() {
        detailTask?.cancel()
        diffTask?.cancel()
        selectionRequestID = UUID()
        selectedHash = nil
        selectedCommit = nil
        selectedDiff = nil
        isSelectedDiffTruncated = false
    }

    private func uniqueCommits(_ values: [GitCommit]) -> [GitCommit] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.fullHash).inserted }
    }

    private func safeDiff(_ diff: GitDiff) -> GitDiff {
        let plainPatch = diff.patch.replacingOccurrences(
            of: "\0",
            with: "\u{FFFD}"
        )
        let truncated = plainPatch.count > maximumPatchCharacters
        isSelectedDiffTruncated = truncated
        return GitDiff(
            commitHash: diff.commitHash,
            files: diff.files,
            patch: String(plainPatch.prefix(maximumPatchCharacters)),
            additions: diff.additions,
            deletions: diff.deletions
        )
    }
}
