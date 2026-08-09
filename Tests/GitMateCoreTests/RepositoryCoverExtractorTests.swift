import Foundation
import GitMateCore

let repositoryCoverExtractorTests = [
    TestCase("封面缓存按仓库读取最近记录并可标记刷新") {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "GitMate-Cover-Latest-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        let cache = RepositoryCoverCache(rootDirectory: rootDirectory)
        let sourceURL = URL(
            string: "https://images.example/latest.png"
        )!
        let data = Data("latest-cover".utf8)
        try cache.save(
            data: data,
            metadata: RepositoryCoverCacheMetadata(
                contentType: "image/png",
                storedAt: Date(timeIntervalSince1970: 1_000),
                pixelWidth: 640,
                pixelHeight: 960
            ),
            repositoryID: 99,
            sourceURL: sourceURL
        )

        let first = try cache.latest(repositoryID: 99)
        try expectEqual(first?.data, data, "应直接读取仓库最近封面")
        try expectEqual(
            first?.metadata.sourceURL,
            sourceURL,
            "最近封面必须保留原始地址"
        )

        try cache.markNeedsRefresh(repositoryIDs: [99])
        let marked = try cache.latest(repositoryID: 99)
        try expect(
            marked?.metadata.needsRefresh == true,
            "手动刷新后只标记缓存需要检查"
        )
    },
    TestCase("封面跳过徽章并选择第一张有效大图") {
        let markdown = """
        ![build](https://img.shields.io/badge/build-passing.svg)
        <img src="icon.png" width="32">
        ![界面](docs/screenshots/dashboard.png)
        """
        let extractor = RepositoryCoverExtractor()
        let candidate = extractor.firstCandidate(
            markdown: markdown,
            baseURL: URL(
                string: "https://github.com/GitMate/mac-client/blob/main/README.md"
            )!
        )

        try expectEqual(
            candidate?.url.absoluteString,
            "https://github.com/GitMate/mac-client/blob/main/docs/screenshots/dashboard.png",
            "应跳过徽章和小图标"
        )
    },
    TestCase("封面拒绝受阻主机小尺寸状态文件和 SVG") {
        let rejectedMarkdown = [
            "![badge](https://badge.fury.io/js/gitmate.svg)",
            "![coverage](https://sub.coveralls.io/project/cover.png)",
            "<img src=\"https://example.com/hero.png\" width=\"239\">",
            "<img src=\"https://example.com/hero.png\" height=\"100\">",
            "![状态](https://example.com/build-status.png)",
            "![图标](https://example.com/app-icon.png)",
            "![矢量](https://example.com/architecture.svg)"
        ]

        for markdown in rejectedMarkdown {
            try expectEqual(
                RepositoryCoverExtractor().firstCandidate(
                    markdown: markdown,
                    baseURL: nil
                ),
                nil,
                "徽章、状态、小图和 SVG 不得成为仓库封面：\(markdown)"
            )
        }
    },
    TestCase("封面忽略危险容器和围栏代码中的伪图片") {
        let markdown = """
        <script>
        ![脚本图片](https://example.com/script.png)
        </script>
        ```markdown
        ![代码图片](https://example.com/code.png)
        ```
        <!-- ![注释图片](https://example.com/comment.png) -->
        ![真实截图](https://example.com/screenshots/dashboard.png)
        """

        try expectEqual(
            RepositoryCoverExtractor().firstCandidate(
                markdown: markdown,
                baseURL: nil
            )?.url.absoluteString,
            "https://example.com/screenshots/dashboard.png",
            "代码与危险容器中的图片不得参与封面筛选"
        )
    },
    TestCase("封面忽略多行及未闭合 HTML 状态中的图片") {
        let closedStates = """
        <!--
        ![注释图片](https://example.com/comment.png)
        -->
        <script
          type="text/javascript">
        ![脚本图片](https://example.com/script.png)
        </script>
        <img
          src="https://example.com/hero.png"
          alt="真实封面"
          width="900"
          height="600"
        >
        """
        let unclosedComment = """
        <!--
        ![注释图片](https://example.com/comment.png)
        ![尾部图片](https://example.com/after.png)
        """

        try expectEqual(
            RepositoryCoverExtractor().firstCandidate(
                markdown: closedStates,
                baseURL: nil
            )?.url.absoluteString,
            "https://example.com/hero.png",
            "跨行 HTML 状态只允许完整 img 进入候选"
        )
        try expectEqual(
            RepositoryCoverExtractor().firstCandidate(
                markdown: unclosedComment,
                baseURL: nil
            ),
            nil,
            "未闭合注释必须屏蔽到 EOF"
        )
    },
    TestCase("封面拒绝危险协议并解析相对 HTML 图片尺寸") {
        let markdown = """
        ![数据](data:image/png;base64,AAAA)
        <img src="javascript:alert(1)" width="900" height="600">
        <img src="../assets/hero.jpg" alt="产品封面" width="900" height="600">
        """
        let candidate = RepositoryCoverExtractor().firstCandidate(
            markdown: markdown,
            baseURL: URL(
                string: "https://github.com/GitMate/app/blob/main/docs/README.md"
            )!
        )

        try expectEqual(
            candidate,
            RepositoryCoverCandidate(
                url: URL(
                    string: "https://github.com/GitMate/app/blob/main/assets/hero.jpg"
                )!,
                alt: "产品封面",
                declaredWidth: 900,
                declaredHeight: 600
            ),
            "相对 HTML 图片应安全解析并保留声明尺寸"
        )
    },
    TestCase("封面按全局源码顺序处理 HTML 与 Markdown 图片") {
        let markdown = """
        <img src="https://example.com/first-html.png" width="900" height="600"> ![后出现](https://example.com/second-markdown.png)
        """

        try expectEqual(
            RepositoryCoverExtractor().firstCandidate(
                markdown: markdown,
                baseURL: nil
            )?.url.absoluteString,
            "https://example.com/first-html.png",
            "HTML 先出现时不得被同一行较后的 Markdown 图片抢占"
        )
    },
    TestCase("同一行首张图片被拒后继续选择后续有效候选") {
        let html = """
        <img src="https://example.com/icon.png" width="32"><img src="https://example.com/valid-html.png" width="900" height="600">
        """
        let markdown = """
        ![徽章](https://img.shields.io/build/hero.png) ![有效截图](https://example.com/valid-markdown.png)
        """

        try expectEqual(
            RepositoryCoverExtractor().firstCandidate(
                markdown: html,
                baseURL: nil
            )?.url.absoluteString,
            "https://example.com/valid-html.png",
            "小 HTML 图片不得阻止同一行后续有效图片"
        )
        try expectEqual(
            RepositoryCoverExtractor().firstCandidate(
                markdown: markdown,
                baseURL: nil
            )?.url.absoluteString,
            "https://example.com/valid-markdown.png",
            "受阻 Markdown 图片不得阻止同一行后续有效图片"
        )
    },
    TestCase("多个 Markdown 图片严格按源码顺序筛选") {
        let markdown = """
        ![状态](https://example.com/status.png) ![图标](https://example.com/icon.png) ![界面](https://example.com/screens/dashboard.png)
        """

        try expectEqual(
            RepositoryCoverExtractor().firstCandidate(
                markdown: markdown,
                baseURL: nil
            )?.url.absoluteString,
            "https://example.com/screens/dashboard.png",
            "应遍历全部 Markdown 图片直至首个有效候选"
        )
    },
    TestCase("封面拒绝显式无主机 URL 与尾点受阻主机") {
        let schemeRelative = """
        ![伪绝对地址](https:relative.png)
        ![有效](https://example.com/valid.png)
        """
        let trailingDotHost = """
        ![尾点徽章](https://img.shields.io./assets/hero.png)
        ![有效](https://example.com/valid.png)
        """

        try expectEqual(
            RepositoryCoverExtractor().firstCandidate(
                markdown: schemeRelative,
                baseURL: URL(string: "https://base.example/README.md")
            )?.url.absoluteString,
            "https://example.com/valid.png",
            "显式 http/https scheme 必须同时具有非空 host"
        )
        try expectEqual(
            RepositoryCoverExtractor().firstCandidate(
                markdown: trailingDotHost,
                baseURL: nil
            )?.url.absoluteString,
            "https://example.com/valid.png",
            "主机比较前必须去除全部尾随点"
        )
    },
    TestCase("封面缓存真实保存读取原始数据和元数据") {
        let rootDirectory = temporaryCoverDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let cache = RepositoryCoverCache(rootDirectory: rootDirectory)
        let sourceURL = URL(string: "https://cdn.example.com/covers/hero.png")!
        let metadata = RepositoryCoverCacheMetadata(
            contentType: "image/png",
            storedAt: Date(timeIntervalSince1970: 1_785_319_200),
            pixelWidth: 1_200,
            pixelHeight: 630
        )
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])

        try cache.save(
            data: imageData,
            metadata: metadata,
            repositoryID: 101,
            sourceURL: sourceURL
        )

        let loadedEntry = try cache.load(repositoryID: 101, sourceURL: sourceURL)
        try expectEqual(loadedEntry?.data, imageData, "缓存应返回真实图像数据")
        try expectEqual(
            loadedEntry?.metadata.contentType,
            metadata.contentType,
            "缓存应保留内容类型"
        )
        try expectEqual(
            loadedEntry?.metadata.sourceURL,
            sourceURL,
            "缓存应补全安全封面地址"
        )
        try expect(
            loadedEntry?.metadata.contentHash?.isEmpty == false,
            "缓存应记录内容哈希"
        )
    },
    TestCase("封面缓存路径稳定且 sourceURL 无法目录逃逸") {
        let rootDirectory = temporaryCoverDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let sourceURL = URL(
            string: "https://user:secret@example.com/../../escape.png?token=top-secret"
        )!
        let metadata = RepositoryCoverCacheMetadata(
            contentType: "image/png",
            storedAt: Date(timeIntervalSince1970: 1_785_319_200),
            pixelWidth: nil,
            pixelHeight: nil
        )

        try RepositoryCoverCache(rootDirectory: rootDirectory).save(
            data: Data([1, 2, 3]),
            metadata: metadata,
            repositoryID: -42,
            sourceURL: sourceURL
        )
        try RepositoryCoverCache(rootDirectory: rootDirectory).save(
            data: Data([4, 5, 6]),
            metadata: metadata,
            repositoryID: -42,
            sourceURL: sourceURL
        )

        let repositoryDirectory = rootDirectory
            .appending(path: "Covers", directoryHint: .isDirectory)
            .appending(path: "-42", directoryHint: .isDirectory)
        let entryRoot = repositoryDirectory.appending(
            path: "9ac59277863bddd8926033d35c89c416657b7b5fd15c55aa8c65d925ee63140e",
            directoryHint: .isDirectory
        )
        let repositoryEntries = try FileManager.default.contentsOfDirectory(
            at: repositoryDirectory,
            includingPropertiesForKeys: nil
        )
        try expectEqual(
            Set(repositoryEntries.map(\.lastPathComponent)),
            Set([
                "9ac59277863bddd8926033d35c89c416657b7b5fd15c55aa8c65d925ee63140e",
                "latest.json"
            ]),
            "sourceURL 必须形成确定性 entryRoot 和单一最近索引"
        )
        let files = try FileManager.default.contentsOfDirectory(
            at: entryRoot,
            includingPropertiesForKeys: nil
        )
        try expectEqual(
            files.filter { $0.pathExtension == "data" }.count,
            2,
            "每次保存应写入独立 generation 数据文件"
        )
        try expectEqual(
            files.filter { $0.pathExtension == "json" }.count,
            2,
            "每次保存应写入独立 generation 元数据文件"
        )
        try expectEqual(
            files.filter { $0.lastPathComponent == "current" }.count,
            1,
            "只能通过单一 current 指针发布 generation"
        )
        try expect(
            files.allSatisfy {
                $0.standardizedFileURL.path.hasPrefix(
                    entryRoot.standardizedFileURL.path + "/"
                )
            },
            "缓存文件不得逃出仓库目录"
        )
        for metadataURL in files where metadataURL.pathExtension == "json" {
            let storedMetadata = try String(
                contentsOf: metadataURL,
                encoding: .utf8
            )
            try expect(
                !storedMetadata.contains("secret")
                    && !storedMetadata.contains("top-secret"),
                "缓存元数据不得保存 URL 凭据或 Token"
            )
        }
    },
    TestCase("两个缓存实例并发保存不会混配数据与元数据") {
        let rootDirectory = temporaryCoverDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let sourceURL = URL(string: "https://example.com/concurrent.png")!
        let firstMetadata = RepositoryCoverCacheMetadata(
            contentType: "image/first",
            storedAt: Date(timeIntervalSince1970: 100),
            pixelWidth: 1_000,
            pixelHeight: 600
        )
        let secondMetadata = RepositoryCoverCacheMetadata(
            contentType: "image/second",
            storedAt: Date(timeIntervalSince1970: 200),
            pixelWidth: 2_000,
            pixelHeight: 1_200
        )
        let firstData = Data(repeating: 0x11, count: 256 * 1_024)
        let secondData = Data(repeating: 0x22, count: 256 * 1_024)
        let firstCache = RepositoryCoverCache(rootDirectory: rootDirectory)
        let secondCache = RepositoryCoverCache(rootDirectory: rootDirectory)

        async let firstSave: Void = firstCache.save(
            data: firstData,
            metadata: firstMetadata,
            repositoryID: 77,
            sourceURL: sourceURL
        )
        async let secondSave: Void = secondCache.save(
            data: secondData,
            metadata: secondMetadata,
            repositoryID: 77,
            sourceURL: sourceURL
        )
        _ = try await (firstSave, secondSave)

        let loaded = try RepositoryCoverCache(
            rootDirectory: rootDirectory
        ).load(repositoryID: 77, sourceURL: sourceURL)
        let isFirstPair = loaded?.data == firstData
            && loaded?.metadata.contentType == firstMetadata.contentType
            && loaded?.metadata.pixelWidth == firstMetadata.pixelWidth
        let isSecondPair = loaded?.data == secondData
            && loaded?.metadata.contentType == secondMetadata.contentType
            && loaded?.metadata.pixelWidth == secondMetadata.pixelWidth
        try expect(
            isFirstPair || isSecondPair,
            "并发保存后只能读取任一完整 generation pair"
        )
        let entryRoot = try coverEntryRoot(
            rootDirectory: rootDirectory,
            repositoryID: 77
        )
        try expect(
            FileManager.default.fileExists(
                atPath: entryRoot.appending(path: "current").path
            ),
            "并发保存必须通过 current 指针发布"
        )
    },
    TestCase("缓存只读取 current 指向且 generation 匹配的完整文件对") {
        let rootDirectory = temporaryCoverDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let cache = RepositoryCoverCache(rootDirectory: rootDirectory)
        let sourceURL = URL(string: "https://example.com/pointer.png")!
        let metadata = RepositoryCoverCacheMetadata(
            contentType: "image/png",
            storedAt: Date(timeIntervalSince1970: 300),
            pixelWidth: 900,
            pixelHeight: 600
        )
        let publishedData = Data([1, 2, 3])
        try cache.save(
            data: publishedData,
            metadata: metadata,
            repositoryID: 88,
            sourceURL: sourceURL
        )
        let entryRoot = try coverEntryRoot(
            rootDirectory: rootDirectory,
            repositoryID: 88
        )
        let currentURL = entryRoot.appending(path: "current")
        let publishedGeneration = try String(
            contentsOf: currentURL,
            encoding: .utf8
        )
        let publishedMetadataURL = entryRoot.appending(
            path: "\(publishedGeneration).json"
        )

        let unpublishedGeneration = UUID().uuidString
        try Data([9, 9, 9]).write(
            to: entryRoot.appending(
                path: "\(unpublishedGeneration).data"
            ),
            options: .atomic
        )
        let stillPublished = try cache.load(
            repositoryID: 88,
            sourceURL: sourceURL
        )
        try expectEqual(
            stillPublished?.data,
            publishedData,
            "未发布 generation 不得影响 current 指向的缓存"
        )

        let missingGeneration = UUID().uuidString
        try Data(missingGeneration.utf8).write(
            to: currentURL,
            options: .atomic
        )
        let missingEntry = try cache.load(
            repositoryID: 88,
            sourceURL: sourceURL
        )
        try expectEqual(
            missingEntry,
            nil,
            "current 指向缺文件 generation 时必须返回 nil"
        )

        let mismatchedGeneration = UUID().uuidString
        try Data([7, 7]).write(
            to: entryRoot.appending(
                path: "\(mismatchedGeneration).data"
            ),
            options: .atomic
        )
        try FileManager.default.copyItem(
            at: publishedMetadataURL,
            to: entryRoot.appending(
                path: "\(mismatchedGeneration).json"
            )
        )
        try Data(mismatchedGeneration.utf8).write(
            to: currentURL,
            options: .atomic
        )
        let mismatchedEntry = try cache.load(
            repositoryID: 88,
            sourceURL: sourceURL
        )
        try expectEqual(
            mismatchedEntry,
            nil,
            "元数据 generation 与 current 不匹配时必须返回 nil"
        )
    },
    TestCase("清理封面缓存只删除目标仓库目录") {
        let rootDirectory = temporaryCoverDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let cache = RepositoryCoverCache(rootDirectory: rootDirectory)
        let metadata = RepositoryCoverCacheMetadata(
            contentType: nil,
            storedAt: Date(timeIntervalSince1970: 1_785_319_200),
            pixelWidth: nil,
            pixelHeight: nil
        )
        let sourceURL = URL(string: "https://example.com/cover.png")!
        try cache.save(
            data: Data([1]),
            metadata: metadata,
            repositoryID: 1,
            sourceURL: sourceURL
        )
        try cache.save(
            data: Data([2]),
            metadata: metadata,
            repositoryID: 2,
            sourceURL: sourceURL
        )

        try cache.clear(repositoryID: 1)

        let clearedEntry = try cache.load(repositoryID: 1, sourceURL: sourceURL)
        try expectEqual(
            clearedEntry,
            nil,
            "目标仓库缓存应被清理"
        )
        let retainedData = try cache.load(
            repositoryID: 2,
            sourceURL: sourceURL
        )?.data
        try expectEqual(
            retainedData,
            Data([2]),
            "其他仓库缓存不得被清理"
        )
    },
    TestCase("回退封面跨编码保持稳定且不依赖界面类型") {
        let repository = Repository(
            id: 101,
            name: "mac-client",
            fullName: "GitMate/mac-client",
            isPrivate: false,
            defaultBranch: "main",
            sizeInKilobytes: 2_048,
            cloneURL: URL(string: "https://github.com/GitMate/mac-client.git")!,
            ownerAvatarURL: nil
        )
        let first = FallbackRepositoryCover.make(
            repository: repository,
            language: "Swift"
        )
        let second = FallbackRepositoryCover.make(
            repository: repository,
            language: "Swift"
        )
        let decoded = try JSONDecoder().decode(
            FallbackRepositoryCover.self,
            from: JSONEncoder().encode(first)
        )

        try expectEqual(first, second, "同一仓库回退封面必须稳定")
        try expectEqual(first, decoded, "回退封面必须可序列化")
        try expectEqual(first.initials, "MC", "应由仓库名生成稳定首字母")
        try expectEqual(
            first.languageColorToken,
            "language.swift",
            "应使用可由 UI 映射的语言颜色 token"
        )
    }
]

private func temporaryCoverDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appending(
            path: "GitMateCoverTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
}

private func coverEntryRoot(
    rootDirectory: URL,
    repositoryID: Int64
) throws -> URL {
    let repositoryDirectory = rootDirectory
        .appending(path: "Covers", directoryHint: .isDirectory)
        .appending(
            path: String(repositoryID),
            directoryHint: .isDirectory
        )
    let entries = try FileManager.default.contentsOfDirectory(
        at: repositoryDirectory,
        includingPropertiesForKeys: [.isDirectoryKey]
    )
    let directories = entries.filter {
        let values = try? $0.resourceValues(
            forKeys: [.isDirectoryKey]
        )
        return values?.isDirectory == true
    }
    guard directories.count == 1, let entryRoot = directories.first else {
        throw TestFailure(description: "仓库缓存目录应只有一个稳定 entryRoot")
    }
    return entryRoot
}

private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let self else {
            throw TestFailure(description: message)
        }
        return self
    }
}
