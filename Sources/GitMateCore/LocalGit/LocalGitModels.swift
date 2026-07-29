import Foundation

public struct GitCommit: Identifiable, Equatable, Sendable {
    public var id: String { fullHash }
    public let shortHash: String
    public let fullHash: String
    public let subject: String
    public let authorName: String
    public let authorEmail: String
    public let authoredAt: Date
    public let parentHashes: [String]
    public let decorations: [String]

    public init(
        shortHash: String,
        fullHash: String,
        subject: String,
        authorName: String,
        authorEmail: String,
        authoredAt: Date,
        parentHashes: [String],
        decorations: [String]
    ) {
        self.shortHash = shortHash
        self.fullHash = fullHash
        self.subject = subject
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.authoredAt = authoredAt
        self.parentHashes = parentHashes
        self.decorations = decorations
    }
}

public struct GitFileEntry: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case file
        case directory
        case submodule
        case symlink
    }

    public var id: String { path }
    public let path: String
    public let name: String
    public let kind: Kind
    public let objectID: String
    public let byteCount: Int64?

    public init(
        path: String,
        name: String,
        kind: Kind,
        objectID: String,
        byteCount: Int64?
    ) {
        self.path = path
        self.name = name
        self.kind = kind
        self.objectID = objectID
        self.byteCount = byteCount
    }
}

public struct LocalRepositoryStatus: Equatable, Sendable {
    public let branch: String?
    public let upstream: String?
    public let ahead: Int
    public let behind: Int
    public let stagedCount: Int
    public let unstagedCount: Int
    public let untrackedCount: Int
    public let conflictCount: Int

    public init(
        branch: String?,
        upstream: String?,
        ahead: Int,
        behind: Int,
        stagedCount: Int,
        unstagedCount: Int,
        untrackedCount: Int,
        conflictCount: Int
    ) {
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.stagedCount = stagedCount
        self.unstagedCount = unstagedCount
        self.untrackedCount = untrackedCount
        self.conflictCount = conflictCount
    }
}

public struct GitFileContent: Equatable, Sendable {
    public let path: String
    public let data: Data
    public let text: String?
    public let byteCount: Int
    public let isBinary: Bool

    public init(
        path: String,
        data: Data,
        text: String?,
        byteCount: Int,
        isBinary: Bool
    ) {
        self.path = path
        self.data = data
        self.text = text
        self.byteCount = byteCount
        self.isBinary = isBinary
    }
}

public struct GitCommitPage: Equatable, Sendable {
    public let commits: [GitCommit]
    public let nextCursor: String?

    public init(commits: [GitCommit], nextCursor: String?) {
        self.commits = commits
        self.nextCursor = nextCursor
    }
}

public enum GitSignatureStatus: Equatable, Sendable {
    case verified
    case unverified
    case unknown
}

public struct GitChangedFile: Equatable, Sendable {
    public let path: String
    public let additions: Int?
    public let deletions: Int?
    public let isBinary: Bool

    public init(
        path: String,
        additions: Int?,
        deletions: Int?,
        isBinary: Bool
    ) {
        self.path = path
        self.additions = additions
        self.deletions = deletions
        self.isBinary = isBinary
    }
}

public struct GitCommitDetail: Equatable, Sendable {
    public let commit: GitCommit
    public let message: String
    public let signatureStatus: GitSignatureStatus
    public let signer: String?

    public init(
        commit: GitCommit,
        message: String,
        signatureStatus: GitSignatureStatus,
        signer: String?
    ) {
        self.commit = commit
        self.message = message
        self.signatureStatus = signatureStatus
        self.signer = signer
    }
}

public struct GitDiff: Equatable, Sendable {
    public let commitHash: String
    public let files: [GitChangedFile]
    public let patch: String
    public let additions: Int
    public let deletions: Int

    public init(
        commitHash: String,
        files: [GitChangedFile],
        patch: String,
        additions: Int,
        deletions: Int
    ) {
        self.commitHash = commitHash
        self.files = files
        self.patch = patch
        self.additions = additions
        self.deletions = deletions
    }
}

public struct CommitGraphPage: Equatable, Sendable {
    public let commits: [GitCommit]
    public let nextCursor: String?

    public init(commits: [GitCommit], nextCursor: String?) {
        self.commits = commits
        self.nextCursor = nextCursor
    }
}

public struct ParsedGitShow: Equatable, Sendable {
    public let detail: GitCommitDetail
    public let diff: GitDiff

    public init(detail: GitCommitDetail, diff: GitDiff) {
        self.detail = detail
        self.diff = diff
    }
}

public enum GitOutputParsingError: Error, Equatable, LocalizedError, Sendable {
    case malformedCommit(String)
    case malformedTreeEntry(String)
    case malformedStatus(String)
    case malformedShow(String)
    case malformedNumstat(String)
    case invalidUTF8(String)

    public var errorDescription: String? {
        switch self {
        case let .malformedCommit(value):
            "无法解析 Git 提交记录：\(value)"
        case let .malformedTreeEntry(value):
            "无法解析 Git 文件树记录：\(value)"
        case let .malformedStatus(value):
            "无法解析 Git 仓库状态：\(value)"
        case let .malformedShow(value):
            "无法解析 Git 提交详情：\(value)"
        case let .malformedNumstat(value):
            "无法解析 Git 差异统计：\(value)"
        case let .invalidUTF8(context):
            "Git \(context) 输出不是有效 UTF-8"
        }
    }
}

public enum LocalGitReaderError: Error, Equatable, LocalizedError, Sendable {
    case invalidRepositoryURL(String)
    case invalidRevision(String)
    case invalidPath(String)
    case invalidLimit(Int)
    case invalidCursor(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidRepositoryURL(value):
            "本地仓库地址无效：\(value)"
        case let .invalidRevision(value):
            "Git revision 或哈希无效：\(value)"
        case let .invalidPath(value):
            "仓库相对路径无效：\(value)"
        case let .invalidLimit(value):
            "分页数量必须位于 1...200：\(value)"
        case let .invalidCursor(value):
            "分页游标必须为非负十进制整数：\(value)"
        }
    }
}
