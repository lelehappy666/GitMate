import Foundation
import Observation

public enum FilesCommitsMode: String, CaseIterable, Equatable, Sendable {
    case files
    case commits
}

public enum FilesCommitsFileDisplayState: Equatable, Sendable {
    case empty
    case loading(path: String)
    case text(path: String, text: String, byteCount: Int)
    case binary(path: String, byteCount: Int)
    case tooLarge(path: String, byteCount: Int)
    case invalidUTF8(path: String, byteCount: Int)
    case failed(path: String, message: String)
}

public struct FilesCommitsState: Equatable, Sendable {
    public var mode: FilesCommitsMode
    public var pathQuery: String
    public var tree: [GitFileEntry]
    public var selectedFile: GitFileContent?
    public var fileDisplayState: FilesCommitsFileDisplayState
    public var commits: [GitCommit]
    public var selectedCommit: GitCommitDetail?
    public var selectedDiff: GitDiff?
    public var nextCommitCursor: String?
    public var isLoadingTree: Bool
    public var isLoadingCommits: Bool
    public var isLoadingMore: Bool
    public var selectedFilePath: String?
    public var selectedCommitHash: String?
    public var commitAuthorQuery: String
    public var commitKeywordQuery: String
    public var commitSince: Date?
    public var commitUntil: Date?
    public var isSelectedDiffTruncated: Bool
    public var errorMessage: String?

    public init() {
        mode = .files
        pathQuery = ""
        tree = []
        selectedFile = nil
        fileDisplayState = .empty
        commits = []
        selectedCommit = nil
        selectedDiff = nil
        nextCommitCursor = nil
        isLoadingTree = false
        isLoadingCommits = false
        isLoadingMore = false
        selectedFilePath = nil
        selectedCommitHash = nil
        commitAuthorQuery = ""
        commitKeywordQuery = ""
        commitSince = nil
        commitUntil = nil
        isSelectedDiffTruncated = false
        errorMessage = nil
    }

    public var filteredTree: [GitFileEntry] {
        let query = pathQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty else {
            return tree
        }
        return tree.filter {
            $0.path.localizedCaseInsensitiveContains(query)
        }
    }

    public var filteredCommits: [GitCommit] {
        let author = commitAuthorQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let keyword = commitKeywordQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return commits.filter { commit in
            let matchesAuthor = author.isEmpty
                || commit.authorName.localizedCaseInsensitiveContains(author)
                || commit.authorEmail.localizedCaseInsensitiveContains(author)
            let searchableText = (
                [commit.subject, commit.fullHash, commit.shortHash]
                    + commit.decorations
            ).joined(separator: " ")
            let matchesKeyword = keyword.isEmpty
                || searchableText.localizedCaseInsensitiveContains(keyword)
            let matchesStart = commitSince.map {
                commit.authoredAt >= $0
            } ?? true
            let matchesEnd = commitUntil.map {
                commit.authoredAt <= $0
            } ?? true
            return matchesAuthor
                && matchesKeyword
                && matchesStart
                && matchesEnd
        }
    }
}

@MainActor
@Observable
public final class FilesCommitsViewModel {
    public private(set) var state = FilesCommitsState()

    @ObservationIgnored
    private let reader: any LocalGitReading

    @ObservationIgnored
    private let repositoryURL: URL

    @ObservationIgnored
    private let revision: String

    @ObservationIgnored
    private let commitPageSize: Int

    @ObservationIgnored
    private let maximumDisplayedFileBytes: Int

    @ObservationIgnored
    private let maximumPatchCharacters: Int

    @ObservationIgnored
    private var treeTask: Task<[GitFileEntry], Error>?

    @ObservationIgnored
    private var fileTask: Task<GitFileContent, Error>?

    @ObservationIgnored
    private var commitPageTask: Task<GitCommitPage, Error>?

    @ObservationIgnored
    private var commitDetailTask: Task<GitCommitDetail, Error>?

    @ObservationIgnored
    private var diffTask: Task<GitDiff, Error>?

    @ObservationIgnored
    private var treeRequestID = UUID()

    @ObservationIgnored
    private var fileRequestID = UUID()

    @ObservationIgnored
    private var commitPageRequestID = UUID()

    @ObservationIgnored
    private var commitDetailRequestID = UUID()

    @ObservationIgnored
    private var diffRequestID = UUID()

    public init(
        reader: any LocalGitReading,
        repositoryURL: URL,
        revision: String = "HEAD",
        commitPageSize: Int = 50,
        maximumDisplayedFileBytes: Int = 1_000_000,
        maximumPatchCharacters: Int = 200_000
    ) {
        self.reader = reader
        self.repositoryURL = repositoryURL
        self.revision = revision
        self.commitPageSize = min(max(commitPageSize, 1), 200)
        self.maximumDisplayedFileBytes = max(maximumDisplayedFileBytes, 1)
        self.maximumPatchCharacters = max(maximumPatchCharacters, 1)
    }

    public func load() async {
        async let tree: Void = loadTree()
        async let commits: Void = loadInitialCommits()
        _ = await (tree, commits)
    }

    public func selectMode(_ mode: FilesCommitsMode) {
        state.mode = mode
        state.errorMessage = nil
    }

    public func updatePathQuery(_ query: String) {
        state.pathQuery = query
    }

    public func updateCommitFilters(
        authorQuery: String,
        keywordQuery: String,
        since: Date?,
        until: Date?
    ) {
        state.commitAuthorQuery = authorQuery
        state.commitKeywordQuery = keywordQuery
        state.commitSince = since
        state.commitUntil = until
    }

    public func loadTree(path: String = "") async {
        treeTask?.cancel()
        let requestID = UUID()
        treeRequestID = requestID
        state.isLoadingTree = true
        state.errorMessage = nil

        let reader = reader
        let repositoryURL = repositoryURL
        let revision = revision
        let task = Task {
            try await reader.tree(
                repositoryURL: repositoryURL,
                revision: revision,
                path: path
            )
        }
        treeTask = task

        do {
            let entries = try await task.value
            guard treeRequestID == requestID else {
                return
            }
            if path.isEmpty {
                state.tree = uniqueEntries(entries)
            } else {
                state.tree = uniqueEntries(state.tree + entries)
            }
            state.isLoadingTree = false
        } catch is CancellationError {
            if treeRequestID == requestID {
                state.isLoadingTree = false
            }
        } catch {
            guard treeRequestID == requestID else {
                return
            }
            state.isLoadingTree = false
            state.errorMessage = "无法读取文件树，请稍后重试。"
        }
    }

    public func selectFile(path: String) async {
        fileTask?.cancel()
        let requestID = UUID()
        fileRequestID = requestID
        state.selectedFilePath = path
        state.selectedFile = nil
        state.errorMessage = nil

        guard state.tree.contains(where: {
            $0.path == path && $0.kind == .file
        }) else {
            state.selectedFilePath = nil
            state.fileDisplayState = .empty
            state.errorMessage = "只能查看文件树中的普通文件。"
            return
        }

        state.fileDisplayState = .loading(path: path)
        let reader = reader
        let repositoryURL = repositoryURL
        let revision = revision
        let task = Task {
            try await reader.file(
                repositoryURL: repositoryURL,
                revision: revision,
                path: path
            )
        }
        fileTask = task

        do {
            let content = try await task.value
            guard fileRequestID == requestID else {
                return
            }
            guard content.path == path else {
                state.selectedFilePath = nil
                state.fileDisplayState = .failed(
                    path: path,
                    message: "文件读取结果与所选路径不一致。"
                )
                state.errorMessage = "无法显示所选文件。"
                return
            }
            state.selectedFile = content
            state.fileDisplayState = displayState(for: content)
        } catch is CancellationError {
            if fileRequestID == requestID {
                state.selectedFile = nil
                state.fileDisplayState = .empty
            }
        } catch {
            guard fileRequestID == requestID else {
                return
            }
            state.selectedFile = nil
            state.fileDisplayState = .failed(
                path: path,
                message: "无法读取文件内容，请稍后重试。"
            )
            state.errorMessage = "无法读取文件内容，请稍后重试。"
        }
    }

    public func loadInitialCommits() async {
        commitPageTask?.cancel()
        let requestID = UUID()
        commitPageRequestID = requestID
        state.isLoadingCommits = true
        state.isLoadingMore = false
        state.errorMessage = nil

        let reader = reader
        let repositoryURL = repositoryURL
        let limit = commitPageSize
        let task = Task {
            try await reader.commits(
                repositoryURL: repositoryURL,
                cursor: nil,
                limit: limit
            )
        }
        commitPageTask = task

        do {
            let page = try await task.value
            guard commitPageRequestID == requestID else {
                return
            }
            state.commits = uniqueCommits(page.commits)
            state.nextCommitCursor = page.nextCursor
            state.isLoadingCommits = false
        } catch is CancellationError {
            if commitPageRequestID == requestID {
                state.isLoadingCommits = false
            }
        } catch {
            guard commitPageRequestID == requestID else {
                return
            }
            state.isLoadingCommits = false
            state.errorMessage = "无法读取提交历史，请稍后重试。"
        }
    }

    public func loadMoreCommits() async {
        guard !state.isLoadingMore,
              !state.isLoadingCommits,
              let cursor = state.nextCommitCursor
        else {
            return
        }

        let requestID = UUID()
        commitPageRequestID = requestID
        state.isLoadingMore = true
        state.errorMessage = nil

        let reader = reader
        let repositoryURL = repositoryURL
        let limit = commitPageSize
        let task = Task {
            try await reader.commits(
                repositoryURL: repositoryURL,
                cursor: cursor,
                limit: limit
            )
        }
        commitPageTask = task

        do {
            let page = try await task.value
            guard commitPageRequestID == requestID else {
                return
            }
            state.commits = uniqueCommits(
                state.commits + page.commits
            )
            state.nextCommitCursor = page.nextCursor
            state.isLoadingMore = false
        } catch is CancellationError {
            if commitPageRequestID == requestID {
                state.isLoadingMore = false
            }
        } catch {
            guard commitPageRequestID == requestID else {
                return
            }
            state.isLoadingMore = false
            state.errorMessage = "无法加载更多提交，请稍后重试。"
        }
    }

    public func selectCommit(hash: String) async {
        commitDetailTask?.cancel()
        diffTask?.cancel()
        let detailID = UUID()
        let selectedDiffID = UUID()
        commitDetailRequestID = detailID
        diffRequestID = selectedDiffID
        state.selectedCommit = nil
        state.selectedDiff = nil
        state.isSelectedDiffTruncated = false
        state.errorMessage = nil

        guard state.commits.contains(where: { $0.fullHash == hash }) else {
            state.selectedCommitHash = nil
            state.errorMessage = "只能查看提交列表中的提交。"
            return
        }

        state.selectedCommitHash = hash
        let reader = reader
        let repositoryURL = repositoryURL
        let detailTask = Task {
            try await reader.commit(
                repositoryURL: repositoryURL,
                hash: hash
            )
        }
        let selectedDiffTask = Task {
            try await reader.diff(
                repositoryURL: repositoryURL,
                hash: hash
            )
        }
        commitDetailTask = detailTask
        diffTask = selectedDiffTask

        do {
            let detail = try await detailTask.value
            if commitDetailRequestID == detailID,
               detail.commit.fullHash == hash {
                state.selectedCommit = detail
            }
        } catch is CancellationError {
            // 新选择会接管详情区域。
        } catch {
            if commitDetailRequestID == detailID {
                state.errorMessage = "无法读取提交详情，请稍后重试。"
            }
        }

        do {
            let diff = try await selectedDiffTask.value
            if diffRequestID == selectedDiffID,
               diff.commitHash == hash {
                let result = truncated(diff: diff)
                state.selectedDiff = result.diff
                state.isSelectedDiffTruncated = result.wasTruncated
            }
        } catch is CancellationError {
            // 新选择会接管差异区域。
        } catch {
            if diffRequestID == selectedDiffID {
                state.errorMessage = "无法读取提交差异，请稍后重试。"
            }
        }
    }

    private func displayState(
        for content: GitFileContent
    ) -> FilesCommitsFileDisplayState {
        if content.isBinary {
            return .binary(
                path: content.path,
                byteCount: content.byteCount
            )
        }
        if content.byteCount > maximumDisplayedFileBytes {
            return .tooLarge(
                path: content.path,
                byteCount: content.byteCount
            )
        }
        guard let text = content.text else {
            return .invalidUTF8(
                path: content.path,
                byteCount: content.byteCount
            )
        }
        return .text(
            path: content.path,
            text: text,
            byteCount: content.byteCount
        )
    }

    private func truncated(
        diff: GitDiff
    ) -> (diff: GitDiff, wasTruncated: Bool) {
        guard diff.patch.count > maximumPatchCharacters else {
            return (diff, false)
        }
        return (
            GitDiff(
                commitHash: diff.commitHash,
                files: diff.files,
                patch: String(
                    diff.patch.prefix(maximumPatchCharacters)
                ) + "\n…差异内容已截断…",
                additions: diff.additions,
                deletions: diff.deletions
            ),
            true
        )
    }

    private func uniqueEntries(
        _ entries: [GitFileEntry]
    ) -> [GitFileEntry] {
        var seen = Set<String>()
        return entries.filter { seen.insert($0.path).inserted }
    }

    private func uniqueCommits(
        _ commits: [GitCommit]
    ) -> [GitCommit] {
        var seen = Set<String>()
        return commits.filter { seen.insert($0.fullHash).inserted }
    }
}
