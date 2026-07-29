import Foundation

public enum GitDiffSource: Equatable, Sendable {
    case workingTree
    case index
}

public struct GitDiffOptions: Equatable, Sendable {
    public var ignoreWhitespace: Bool
    public var contextLines: Int

    public init(
        ignoreWhitespace: Bool = false,
        contextLines: Int = 3
    ) {
        self.ignoreWhitespace = ignoreWhitespace
        self.contextLines = max(0, contextLines)
    }

    public static let `default` = GitDiffOptions()
}

public enum GitDiffLoadingMode: Equatable, Sendable {
    case full
    case summary
}

public enum GitDiffLineKind: Equatable, Sendable {
    case context
    case addition
    case deletion
    case metadata
}

public struct GitDiffLine: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: GitDiffLineKind
    public let text: String

    public init(id: String, kind: GitDiffLineKind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

public struct GitDiffFile: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let oldPath: String?
    public let path: String
    public let isBinary: Bool

    public init(oldPath: String?, path: String, isBinary: Bool) {
        self.oldPath = oldPath
        self.path = path
        self.isBinary = isBinary
    }
}

public struct GitDiffHunk: Identifiable, Equatable, Sendable {
    public let id: String
    public let header: String
    public let lines: [GitDiffLine]
    public let patch: Data
    public let addedLineCount: Int
    public let deletedLineCount: Int

    public init(
        id: String,
        header: String,
        lines: [GitDiffLine],
        patch: Data,
        addedLineCount: Int,
        deletedLineCount: Int
    ) {
        self.id = id
        self.header = header
        self.lines = lines
        self.patch = patch
        self.addedLineCount = addedLineCount
        self.deletedLineCount = deletedLineCount
    }
}

public struct GitDiffDocument: Equatable, Sendable {
    public let path: String
    public let files: [GitDiffFile]
    public let hunks: [GitDiffHunk]
    public let byteCount: Int
    public let lineCount: Int
    public let addedLineCount: Int
    public let deletedLineCount: Int
    public let loadingMode: GitDiffLoadingMode

    public init(
        path: String,
        files: [GitDiffFile],
        hunks: [GitDiffHunk],
        byteCount: Int,
        lineCount: Int,
        addedLineCount: Int,
        deletedLineCount: Int,
        loadingMode: GitDiffLoadingMode
    ) {
        self.path = path
        self.files = files
        self.hunks = hunks
        self.byteCount = byteCount
        self.lineCount = lineCount
        self.addedLineCount = addedLineCount
        self.deletedLineCount = deletedLineCount
        self.loadingMode = loadingMode
    }
}
