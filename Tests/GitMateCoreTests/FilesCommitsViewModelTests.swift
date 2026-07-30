import Foundation
import GitMateCore

let filesCommitsViewModelTests = [
    TestCase("切换文件时旧结果不得覆盖新文件") { @MainActor in
        let reader = ControlledFilesReader()
        let viewModel = FilesCommitsViewModel(
            reader: reader,
            repositoryURL: filesCommitsRepositoryURL
        )
        await viewModel.loadTree()

        let first = Task { @MainActor in
            await viewModel.selectFile(path: "A.swift")
        }
        await reader.waitForFileRequest(path: "A.swift")
        let second = Task { @MainActor in
            await viewModel.selectFile(path: "B.swift")
        }
        await reader.waitForFileRequest(path: "B.swift")

        await reader.resumeFile(path: "B.swift", text: "新文件")
        await second.value
        await reader.resumeFile(path: "A.swift", text: "旧文件")
        await first.value

        try expectEqual(
            viewModel.state.selectedFile?.path,
            "B.swift",
            "较慢的旧文件请求不得覆盖最新选择"
        )
    },
    TestCase("切换提交时旧详情与差异不得覆盖新提交") { @MainActor in
        let reader = ControlledCommitReader()
        let viewModel = FilesCommitsViewModel(
            reader: reader,
            repositoryURL: filesCommitsRepositoryURL
        )
        await viewModel.loadInitialCommits()

        let first = Task { @MainActor in
            await viewModel.selectCommit(hash: "hash-a")
        }
        await reader.waitForCommitRequests(hash: "hash-a")
        let second = Task { @MainActor in
            await viewModel.selectCommit(hash: "hash-b")
        }
        await reader.waitForCommitRequests(hash: "hash-b")

        await reader.resumeCommitRequests(hash: "hash-b")
        await second.value
        await reader.resumeCommitRequests(hash: "hash-a")
        await first.value

        try expectEqual(
            viewModel.state.selectedCommit?.commit.fullHash,
            "hash-b",
            "旧提交详情不得覆盖最新提交"
        )
        try expectEqual(
            viewModel.state.selectedDiff?.commitHash,
            "hash-b",
            "旧提交差异不得覆盖最新提交"
        )
    },
    TestCase("提交分页按完整哈希去重并更新游标") { @MainActor in
        let reader = PagedCommitsReader()
        let viewModel = FilesCommitsViewModel(
            reader: reader,
            repositoryURL: filesCommitsRepositoryURL,
            commitPageSize: 2
        )

        await viewModel.loadInitialCommits()
        await viewModel.loadMoreCommits()

        try expectEqual(
            viewModel.state.commits.map(\.fullHash),
            ["hash-a", "hash-b", "hash-c"],
            "分页结果应稳定保序并按完整哈希去重"
        )
        try expectEqual(
            viewModel.state.nextCommitCursor,
            "400",
            "应采用最新分页响应的游标"
        )
    },
    TestCase("并发加载更多只发起一次请求") { @MainActor in
        let reader = PausedLoadMoreReader()
        let viewModel = FilesCommitsViewModel(
            reader: reader,
            repositoryURL: filesCommitsRepositoryURL,
            commitPageSize: 1
        )
        await viewModel.loadInitialCommits()

        let first = Task { @MainActor in
            await viewModel.loadMoreCommits()
        }
        await reader.waitUntilLoadMoreStarts()
        let second = Task { @MainActor in
            await viewModel.loadMoreCommits()
        }
        await Task.yield()
        await reader.resumeLoadMore()
        await first.value
        await second.value
        let loadMoreRequestCount = await reader.loadMoreRequestCount

        try expectEqual(
            loadMoreRequestCount,
            1,
            "同一游标只允许一个加载更多请求"
        )
        try expectEqual(
            viewModel.state.commits.map(\.fullHash),
            ["hash-a", "hash-b"],
            "并发保护不得丢失成功的下一页"
        )
    },
    TestCase("拒绝读取不在文件树中的路径与非普通文件") { @MainActor in
        let reader = StaticFilesCommitsReader()
        let viewModel = FilesCommitsViewModel(
            reader: reader,
            repositoryURL: filesCommitsRepositoryURL
        )
        await viewModel.loadTree()

        await viewModel.selectFile(path: "../secret")
        var fileRequestCount = await reader.fileRequestCount
        try expectEqual(
            fileRequestCount,
            0,
            "文件树外路径不得传给本地 Git 读取器"
        )
        try expectEqual(
            viewModel.state.errorMessage,
            "只能查看文件树中的普通文件。",
            "文件树外路径应显示稳定错误"
        )

        await viewModel.selectFile(path: "Sources")
        fileRequestCount = await reader.fileRequestCount
        try expectEqual(
            fileRequestCount,
            0,
            "目录不得作为文件读取"
        )
    },
    TestCase("路径与提交筛选只派生视图结果不改写源数据") { @MainActor in
        let reader = StaticFilesCommitsReader()
        let viewModel = FilesCommitsViewModel(
            reader: reader,
            repositoryURL: filesCommitsRepositoryURL
        )
        await viewModel.loadTree()
        await viewModel.loadInitialCommits()
        let originalTree = viewModel.state.tree
        let originalCommits = viewModel.state.commits

        viewModel.updatePathQuery("B.swift")
        viewModel.updateCommitFilters(
            authorQuery: "lele",
            keywordQuery: "修复",
            since: Date(timeIntervalSince1970: 50),
            until: Date(timeIntervalSince1970: 150)
        )

        try expectEqual(
            viewModel.state.filteredTree.map(\.path),
            ["B.swift"],
            "路径筛选应仅返回匹配结果"
        )
        try expectEqual(
            viewModel.state.filteredCommits.map(\.fullHash),
            ["hash-a"],
            "作者、关键词和时间筛选应组合生效"
        )
        try expectEqual(
            viewModel.state.tree,
            originalTree,
            "路径筛选不得改写原始文件树"
        )
        try expectEqual(
            viewModel.state.commits,
            originalCommits,
            "提交筛选不得改写原始分页结果"
        )
    },
    TestCase("目录展开向读取器传递规范化斜杠路径") { @MainActor in
        let reader = RecordingTreeReader()
        let viewModel = FilesCommitsViewModel(
            reader: reader,
            repositoryURL: filesCommitsRepositoryURL
        )

        await viewModel.loadTree()
        await viewModel.loadTree(path: "Sources")

        let requestedPaths = await reader.requestedPaths
        try expectEqual(
            requestedPaths,
            ["", "Sources/"],
            "目录 pathspec 必须以单个斜杠结尾"
        )
    },
    TestCase("快速展开不同目录时各自结果都合并进文件树") { @MainActor in
        let reader = ConcurrentTreeReader()
        let viewModel = FilesCommitsViewModel(
            reader: reader,
            repositoryURL: filesCommitsRepositoryURL
        )
        await viewModel.loadTree()

        let sources = Task { @MainActor in
            await viewModel.loadTree(path: "Sources/")
        }
        await reader.waitForRequest(path: "Sources/")
        let tests = Task { @MainActor in
            await viewModel.loadTree(path: "Tests/")
        }
        await reader.waitForRequest(path: "Tests/")

        await reader.resume(path: "Tests/")
        await tests.value
        await reader.resume(path: "Sources/")
        await sources.value

        try expectEqual(
            Set(viewModel.state.tree.map(\.path)),
            Set([
                "Sources",
                "Tests",
                "Sources/App.swift",
                "Tests/AppTests.swift"
            ]),
            "不同目录的并发展开不得互相取消或丢失结果"
        )
    },
    TestCase("文件树已知超大文件在读取内容前直接拒绝") { @MainActor in
        let reader = KnownLargeFileReader()
        let viewModel = FilesCommitsViewModel(
            reader: reader,
            repositoryURL: filesCommitsRepositoryURL,
            maximumDisplayedFileBytes: 8
        )
        await viewModel.loadTree()

        await viewModel.selectFile(path: "Archive.txt")

        let fileRequestCount = await reader.fileRequestCount
        try expectEqual(
            fileRequestCount,
            0,
            "已知大小超过上限时不得读取 blob 内容"
        )
        try expectEqual(
            viewModel.state.fileDisplayState,
            .tooLarge(path: "Archive.txt", byteCount: 20),
            "预拒绝后应直接显示超大文件状态"
        )
    },
    TestCase("无法解码文件进入独立 UTF-8 空状态") { @MainActor in
        let reader = InvalidUTF8FileReader()
        let viewModel = FilesCommitsViewModel(
            reader: reader,
            repositoryURL: filesCommitsRepositoryURL
        )
        await viewModel.loadTree()

        await viewModel.selectFile(path: "Legacy.txt")

        try expectEqual(
            viewModel.state.fileDisplayState,
            .preview(
                FilePreviewDocument(
                    path: "Legacy.txt",
                    data: Data([0xFF, 0xFE, 0x41]),
                    text: nil,
                    kind: .invalidText,
                    byteCount: 3
                )
            ),
            "生产内容类型必须直达无法解码空状态"
        )
    },
    TestCase("图片和 PDF 二进制进入富媒体预览") { @MainActor in
        let png = Data([
            0x89, 0x50, 0x4E, 0x47,
            0x0D, 0x0A, 0x1A, 0x0A
        ])
        let imageReader = StaticPreviewFileReader(
            content: GitFileContent(
                path: "Assets/cover.png",
                data: png,
                text: nil,
                byteCount: png.count,
                kind: .binary
            )
        )
        let imageViewModel = FilesCommitsViewModel(
            reader: imageReader,
            repositoryURL: filesCommitsRepositoryURL
        )
        await imageViewModel.loadTree()
        await imageViewModel.selectFile(path: "Assets/cover.png")

        guard case let .preview(imageDocument) =
            imageViewModel.state.fileDisplayState else {
            throw TestFailure(description: "PNG 必须进入统一预览状态")
        }
        try expectEqual(
            imageDocument.kind,
            .rasterImage,
            "二进制标记不得阻止真实图片预览"
        )

        let pdf = Data("%PDF-1.7".utf8)
        let pdfReader = StaticPreviewFileReader(
            content: GitFileContent(
                path: "Docs/manual.pdf",
                data: pdf,
                text: nil,
                byteCount: pdf.count,
                kind: .binary
            )
        )
        let pdfViewModel = FilesCommitsViewModel(
            reader: pdfReader,
            repositoryURL: filesCommitsRepositoryURL
        )
        await pdfViewModel.loadTree()
        await pdfViewModel.selectFile(path: "Docs/manual.pdf")
        guard case let .preview(pdfDocument) =
            pdfViewModel.state.fileDisplayState else {
            throw TestFailure(description: "PDF 必须进入统一预览状态")
        }
        try expectEqual(pdfDocument.kind, .pdf, "PDF 签名必须保留")
    },
    TestCase("HTML Markdown 与脚本进入可显示预览") { @MainActor in
        let values: [(String, String, FilePreviewKind)] = [
            (
                "Preview/index.html",
                "<html><body>预览</body></html>",
                .html
            ),
            ("README.md", "# 标题", .source(.markdown)),
            ("Scripts/build.py", "print('ok')", .source(.python))
        ]

        for (path, text, expectedKind) in values {
            let data = Data(text.utf8)
            let reader = StaticPreviewFileReader(
                content: GitFileContent(
                    path: path,
                    data: data,
                    text: text,
                    byteCount: data.count,
                    kind: .text
                )
            )
            let viewModel = FilesCommitsViewModel(
                reader: reader,
                repositoryURL: filesCommitsRepositoryURL
            )
            await viewModel.loadTree()
            await viewModel.selectFile(path: path)

            guard case let .preview(document) =
                viewModel.state.fileDisplayState else {
                throw TestFailure(
                    description: "\(path) 必须进入统一预览状态"
                )
            }
            try expectEqual(
                document.kind,
                expectedKind,
                "\(path) 应使用对应预览器"
            )
        }
    }
]

private let filesCommitsRepositoryURL = URL(
    fileURLWithPath: "/tmp/GitMateFilesCommits"
)

private protocol FilesCommitsTestReading: LocalGitReading {}

private extension FilesCommitsTestReading {
    func status(repositoryURL _: URL) async throws -> LocalRepositoryStatus {
        LocalRepositoryStatus(
            branch: "main",
            upstream: "origin/main",
            ahead: 0,
            behind: 0,
            stagedCount: 0,
            unstagedCount: 0,
            untrackedCount: 0,
            conflictCount: 0
        )
    }

    func tree(
        repositoryURL _: URL,
        revision _: String,
        path _: String
    ) async throws -> [GitFileEntry] {
        []
    }

    func file(
        repositoryURL _: URL,
        revision _: String,
        path: String
    ) async throws -> GitFileContent {
        throw LocalGitReaderError.invalidPath(path)
    }

    func commits(
        repositoryURL _: URL,
        cursor _: String?,
        limit _: Int
    ) async throws -> GitCommitPage {
        GitCommitPage(commits: [], nextCursor: nil)
    }

    func commit(
        repositoryURL _: URL,
        hash: String
    ) async throws -> GitCommitDetail {
        makeCommitDetail(hash: hash)
    }

    func diff(
        repositoryURL _: URL,
        hash: String
    ) async throws -> GitDiff {
        makeDiff(hash: hash)
    }

    func graph(
        repositoryURL _: URL,
        cursor _: String?,
        limit _: Int
    ) async throws -> CommitGraphPage {
        CommitGraphPage(commits: [], nextCursor: nil)
    }
}

private actor ControlledFilesReader: FilesCommitsTestReading {
    private var fileContinuations: [
        String: CheckedContinuation<GitFileContent, Error>
    ] = [:]

    func tree(
        repositoryURL _: URL,
        revision _: String,
        path _: String
    ) async throws -> [GitFileEntry] {
        [
            makeFileEntry(path: "A.swift"),
            makeFileEntry(path: "B.swift")
        ]
    }

    func file(
        repositoryURL _: URL,
        revision _: String,
        path: String
    ) async throws -> GitFileContent {
        try await withCheckedThrowingContinuation { continuation in
            fileContinuations[path] = continuation
        }
    }

    func waitForFileRequest(path: String) async {
        while fileContinuations[path] == nil {
            await Task.yield()
        }
    }

    func resumeFile(path: String, text: String) {
        let data = Data(text.utf8)
        fileContinuations.removeValue(forKey: path)?.resume(
            returning: GitFileContent(
                path: path,
                data: data,
                text: text,
                byteCount: data.count,
                isBinary: false
            )
        )
    }
}

private actor ControlledCommitReader: FilesCommitsTestReading {
    private var detailContinuations: [
        String: CheckedContinuation<GitCommitDetail, Error>
    ] = [:]
    private var diffContinuations: [
        String: CheckedContinuation<GitDiff, Error>
    ] = [:]

    func commits(
        repositoryURL _: URL,
        cursor _: String?,
        limit _: Int
    ) async throws -> GitCommitPage {
        GitCommitPage(
            commits: [makeCommit(hash: "hash-a"), makeCommit(hash: "hash-b")],
            nextCursor: nil
        )
    }

    func commit(
        repositoryURL _: URL,
        hash: String
    ) async throws -> GitCommitDetail {
        try await withCheckedThrowingContinuation { continuation in
            detailContinuations[hash] = continuation
        }
    }

    func diff(
        repositoryURL _: URL,
        hash: String
    ) async throws -> GitDiff {
        try await withCheckedThrowingContinuation { continuation in
            diffContinuations[hash] = continuation
        }
    }

    func waitForCommitRequests(hash: String) async {
        while detailContinuations[hash] == nil
            || diffContinuations[hash] == nil {
            await Task.yield()
        }
    }

    func resumeCommitRequests(hash: String) {
        detailContinuations.removeValue(forKey: hash)?.resume(
            returning: makeCommitDetail(hash: hash)
        )
        diffContinuations.removeValue(forKey: hash)?.resume(
            returning: makeDiff(hash: hash)
        )
    }
}

private actor PagedCommitsReader: FilesCommitsTestReading {
    func commits(
        repositoryURL _: URL,
        cursor: String?,
        limit _: Int
    ) async throws -> GitCommitPage {
        if cursor == nil {
            return GitCommitPage(
                commits: [
                    makeCommit(hash: "hash-a"),
                    makeCommit(hash: "hash-b")
                ],
                nextCursor: "2"
            )
        }
        return GitCommitPage(
            commits: [
                makeCommit(hash: "hash-b"),
                makeCommit(hash: "hash-c")
            ],
            nextCursor: "400"
        )
    }
}

private actor PausedLoadMoreReader: FilesCommitsTestReading {
    private var loadMoreContinuation: CheckedContinuation<Void, Never>?
    private(set) var loadMoreRequestCount = 0

    func commits(
        repositoryURL _: URL,
        cursor: String?,
        limit _: Int
    ) async throws -> GitCommitPage {
        guard cursor != nil else {
            return GitCommitPage(
                commits: [makeCommit(hash: "hash-a")],
                nextCursor: "1"
            )
        }
        loadMoreRequestCount += 1
        await withCheckedContinuation { continuation in
            loadMoreContinuation = continuation
        }
        return GitCommitPage(
            commits: [makeCommit(hash: "hash-b")],
            nextCursor: nil
        )
    }

    func waitUntilLoadMoreStarts() async {
        while loadMoreContinuation == nil {
            await Task.yield()
        }
    }

    func resumeLoadMore() {
        loadMoreContinuation?.resume()
        loadMoreContinuation = nil
    }
}

private actor StaticFilesCommitsReader: FilesCommitsTestReading {
    private(set) var fileRequestCount = 0

    func tree(
        repositoryURL _: URL,
        revision _: String,
        path _: String
    ) async throws -> [GitFileEntry] {
        [
            makeFileEntry(path: "A.swift"),
            makeFileEntry(path: "B.swift"),
            GitFileEntry(
                path: "Sources",
                name: "Sources",
                kind: .directory,
                objectID: "tree-sources",
                byteCount: nil
            )
        ]
    }

    func file(
        repositoryURL _: URL,
        revision _: String,
        path: String
    ) async throws -> GitFileContent {
        fileRequestCount += 1
        throw LocalGitReaderError.invalidPath(path)
    }

    func commits(
        repositoryURL _: URL,
        cursor _: String?,
        limit _: Int
    ) async throws -> GitCommitPage {
        GitCommitPage(
            commits: [
                makeCommit(
                    hash: "hash-a",
                    subject: "修复同步",
                    author: "Lele",
                    authoredAt: Date(timeIntervalSince1970: 100)
                ),
                makeCommit(
                    hash: "hash-b",
                    subject: "发布版本",
                    author: "Release Bot",
                    authoredAt: Date(timeIntervalSince1970: 200)
                ),
                makeCommit(
                    hash: "hash-c",
                    subject: "更新文档",
                    author: "Lele",
                    authoredAt: Date(timeIntervalSince1970: 300)
                )
            ],
            nextCursor: nil
        )
    }

}

private actor RecordingTreeReader: FilesCommitsTestReading {
    private(set) var requestedPaths: [String] = []

    func tree(
        repositoryURL _: URL,
        revision _: String,
        path: String
    ) async throws -> [GitFileEntry] {
        requestedPaths.append(path)
        if path.isEmpty {
            return [makeDirectoryEntry(path: "Sources")]
        }
        return [makeFileEntry(path: "Sources/App.swift")]
    }
}

private actor ConcurrentTreeReader: FilesCommitsTestReading {
    private var continuations: [
        String: CheckedContinuation<[GitFileEntry], Never>
    ] = [:]

    func tree(
        repositoryURL _: URL,
        revision _: String,
        path: String
    ) async throws -> [GitFileEntry] {
        if path.isEmpty {
            return [
                makeDirectoryEntry(path: "Sources"),
                makeDirectoryEntry(path: "Tests")
            ]
        }
        return await withCheckedContinuation { continuation in
            continuations[path] = continuation
        }
    }

    func waitForRequest(path: String) async {
        while continuations[path] == nil {
            await Task.yield()
        }
    }

    func resume(path: String) {
        let entry = path == "Sources/"
            ? makeFileEntry(path: "Sources/App.swift")
            : makeFileEntry(path: "Tests/AppTests.swift")
        continuations.removeValue(forKey: path)?.resume(returning: [entry])
    }
}

private actor KnownLargeFileReader: FilesCommitsTestReading {
    private(set) var fileRequestCount = 0

    func tree(
        repositoryURL _: URL,
        revision _: String,
        path _: String
    ) async throws -> [GitFileEntry] {
        [makeFileEntry(path: "Archive.txt", byteCount: 20)]
    }

    func file(
        repositoryURL _: URL,
        revision _: String,
        path: String
    ) async throws -> GitFileContent {
        fileRequestCount += 1
        let text = String(repeating: "A", count: 20)
        return GitFileContent(
            path: path,
            data: Data(text.utf8),
            text: text,
            byteCount: 20,
            isBinary: false
        )
    }
}

private actor InvalidUTF8FileReader: FilesCommitsTestReading {
    func tree(
        repositoryURL _: URL,
        revision _: String,
        path _: String
    ) async throws -> [GitFileEntry] {
        [makeFileEntry(path: "Legacy.txt")]
    }

    func file(
        repositoryURL _: URL,
        revision _: String,
        path: String
    ) async throws -> GitFileContent {
        GitFileContent(
            path: path,
            data: Data([0xFF, 0xFE, 0x41]),
            text: nil,
            byteCount: 3,
            kind: .invalidUTF8
        )
    }
}

private actor StaticPreviewFileReader: FilesCommitsTestReading {
    private let content: GitFileContent

    init(content: GitFileContent) {
        self.content = content
    }

    func tree(
        repositoryURL _: URL,
        revision _: String,
        path _: String
    ) async throws -> [GitFileEntry] {
        [
            makeFileEntry(
                path: content.path,
                byteCount: Int64(content.byteCount)
            )
        ]
    }

    func file(
        repositoryURL _: URL,
        revision _: String,
        path _: String
    ) async throws -> GitFileContent {
        content
    }
}

private func makeFileEntry(
    path: String,
    byteCount: Int64? = nil
) -> GitFileEntry {
    GitFileEntry(
        path: path,
        name: URL(fileURLWithPath: path).lastPathComponent,
        kind: .file,
        objectID: "blob-\(path)",
        byteCount: byteCount
    )
}

private func makeDirectoryEntry(path: String) -> GitFileEntry {
    GitFileEntry(
        path: path,
        name: URL(fileURLWithPath: path).lastPathComponent,
        kind: .directory,
        objectID: "tree-\(path)",
        byteCount: nil
    )
}

private func makeCommit(
    hash: String,
    subject: String = "提交 \(UUID().uuidString)",
    author: String = "Lele",
    authoredAt: Date = Date(timeIntervalSince1970: 100)
) -> GitCommit {
    GitCommit(
        shortHash: String(hash.prefix(7)),
        fullHash: hash,
        subject: subject,
        authorName: author,
        authorEmail: "\(author.lowercased())@example.com",
        authoredAt: authoredAt,
        parentHashes: [],
        decorations: hash == "hash-a" ? ["HEAD -> main", "tag: v1.0"] : []
    )
}

private func makeCommitDetail(hash: String) -> GitCommitDetail {
    GitCommitDetail(
        commit: makeCommit(hash: hash),
        message: "提交详情 \(hash)",
        signatureStatus: .unknown,
        signer: nil
    )
}

private func makeDiff(hash: String) -> GitDiff {
    GitDiff(
        commitHash: hash,
        files: [],
        patch: "diff --git a/\(hash) b/\(hash)",
        additions: 0,
        deletions: 0
    )
}
