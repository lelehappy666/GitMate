import Foundation

public enum WorkingTreeCategory: Equatable, Sendable {
    case conflicted
    case staged
    case unstaged
    case untracked
}

public struct WorkingTreeFile: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let originalPath: String?
    public let category: WorkingTreeCategory
    public let indexStatus: Character?
    public let workTreeStatus: Character?

    public init(
        path: String,
        originalPath: String? = nil,
        category: WorkingTreeCategory,
        indexStatus: Character? = nil,
        workTreeStatus: Character? = nil
    ) {
        self.path = path
        self.originalPath = originalPath
        self.category = category
        self.indexStatus = indexStatus
        self.workTreeStatus = workTreeStatus
    }
}

public struct LocalBranchStatus: Equatable, Sendable {
    public let name: String?
    public let upstream: String?
    public let ahead: Int
    public let behind: Int

    public init(
        name: String?,
        upstream: String?,
        ahead: Int,
        behind: Int
    ) {
        self.name = name
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
    }
}

public enum UntrackedScanState: Equatable, Sendable {
    case notStarted
    case loading(received: Int)
    case completed(total: Int)
}

public struct WorkingTreeBatch: Equatable, Sendable {
    public let generation: UInt64
    public let files: [WorkingTreeFile]
    public let isLast: Bool

    public init(
        generation: UInt64,
        files: [WorkingTreeFile],
        isLast: Bool
    ) {
        self.generation = generation
        self.files = files
        self.isLast = isLast
    }
}

public enum WorkingTreeFilter: Equatable, Sendable {
    case all
    case conflicted
    case staged
    case unstaged
    case untracked
}

public struct WorkingTreeSnapshot: Equatable, Sendable {
    public let branch: LocalBranchStatus
    public let files: [WorkingTreeFile]
    public let untrackedScan: UntrackedScanState
    public let generation: UInt64

    public init(
        branch: LocalBranchStatus,
        files: [WorkingTreeFile],
        untrackedScan: UntrackedScanState,
        generation: UInt64
    ) {
        self.branch = branch
        self.files = files
        self.untrackedScan = untrackedScan
        self.generation = generation
    }
}
