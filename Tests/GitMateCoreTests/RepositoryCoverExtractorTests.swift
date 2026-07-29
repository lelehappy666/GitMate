import Foundation
import GitMateCore

let repositoryCoverExtractorTests = [
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
        try expectEqual(
            loadedEntry,
            RepositoryCoverCacheEntry(data: imageData, metadata: metadata),
            "缓存应返回真实落盘的图像原始数据和元数据"
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

        let coverDirectory = rootDirectory
            .appending(path: "Covers", directoryHint: .isDirectory)
            .appending(path: "-42", directoryHint: .isDirectory)
        let files = try FileManager.default.contentsOfDirectory(
            at: coverDirectory,
            includingPropertiesForKeys: nil
        )
        try expectEqual(files.count, 2, "相同 URL 重写后只能保留数据和元数据两个稳定文件")
        try expectEqual(
            files.map(\.lastPathComponent).sorted(),
            [
                "9ac59277863bddd8926033d35c89c416657b7b5fd15c55aa8c65d925ee63140e",
                "9ac59277863bddd8926033d35c89c416657b7b5fd15c55aa8c65d925ee63140e.json"
            ],
            "缓存文件名必须使用确定性 SHA-256，不能使用 hashValue"
        )
        try expect(
            files.allSatisfy {
                $0.standardizedFileURL.path.hasPrefix(
                    coverDirectory.standardizedFileURL.path + "/"
                )
            },
            "缓存文件不得逃出仓库目录"
        )
        let metadataURL = try files.first { $0.pathExtension == "json" }
            .unwrap("应生成元数据文件")
        let storedMetadata = try String(contentsOf: metadataURL, encoding: .utf8)
        try expect(
            !storedMetadata.contains("secret")
                && !storedMetadata.contains("top-secret"),
            "缓存元数据不得保存 URL 凭据或 Token"
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

private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let self else {
            throw TestFailure(description: message)
        }
        return self
    }
}
