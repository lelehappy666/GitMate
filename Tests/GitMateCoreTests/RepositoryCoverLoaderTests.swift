import AppKit
import Foundation
import GitMateCore

let repositoryCoverLoaderTests = [
    TestCase("远程封面验证成功后写入磁盘缓存") {
        let data = validRepositoryCoverData(width: 320, height: 280)
        let cache = CoverLoaderCacheStub()
        let downloader = CoverDownloaderStub(
            response: RepositoryCoverDownloadResponse(
                data: data,
                statusCode: 200,
                contentType: "image/png"
            )
        )
        let loader = RepositoryCoverLoader(
            cache: cache,
            downloader: downloader
        )

        let entry = try await loader.load(
            repositoryID: 11,
            sourceURL: URL(string: "https://images.example/cover.png")!
        )

        try expectEqual(entry.data, data, "加载器应返回已验证的原始图片")
        try expectEqual(entry.metadata.pixelWidth, 320, "应记录真实图片宽度")
        try expectEqual(entry.metadata.pixelHeight, 280, "应记录真实图片高度")
        try expectEqual(cache.saveCount, 1, "远程成功后必须写入磁盘缓存")
    },
    TestCase("远程封面拒绝异常响应类型超大内容和无效图片") {
        let valid = validRepositoryCoverData(width: 320, height: 280)
        let cases: [(RepositoryCoverDownloadResponse, RepositoryCoverLoadError)] = [
            (
                RepositoryCoverDownloadResponse(
                    data: valid,
                    statusCode: 404,
                    contentType: "image/png"
                ),
                .invalidHTTPStatus(404)
            ),
            (
                RepositoryCoverDownloadResponse(
                    data: valid,
                    statusCode: 200,
                    contentType: "text/html"
                ),
                .invalidContentType("text/html")
            ),
            (
                RepositoryCoverDownloadResponse(
                    data: Data(repeating: 1, count: 65),
                    statusCode: 200,
                    contentType: "image/png"
                ),
                .responseTooLarge
            ),
            (
                RepositoryCoverDownloadResponse(
                    data: Data("not-image".utf8),
                    statusCode: 200,
                    contentType: "image/png"
                ),
                .invalidImage
            ),
            (
                RepositoryCoverDownloadResponse(
                    data: validRepositoryCoverData(width: 120, height: 120),
                    statusCode: 200,
                    contentType: "image/png"
                ),
                .imageTooSmall(width: 120, height: 120)
            )
        ]

        for (index, testCase) in cases.enumerated() {
            let cache = CoverLoaderCacheStub()
            let loader = RepositoryCoverLoader(
                cache: cache,
                downloader: CoverDownloaderStub(response: testCase.0),
                maximumResponseByteCount: index == 2
                    ? 64
                    : 8 * 1_024 * 1_024
            )
            do {
                _ = try await loader.load(
                    repositoryID: Int64(index),
                    sourceURL: URL(
                        string: "https://images.example/\(index).png"
                    )!
                )
                throw TestFailure(description: "非法远程封面不应加载成功")
            } catch let error as RepositoryCoverLoadError {
                try expectEqual(error, testCase.1, "应返回对应的封面校验错误")
            }
            try expectEqual(cache.saveCount, 0, "非法远程封面不得写入缓存")
        }
    },
    TestCase("远程封面限制四路并发并对相同地址去重") {
        let data = validRepositoryCoverData(width: 320, height: 280)
        let downloader = ConcurrentCoverDownloader(data: data)
        let loader = RepositoryCoverLoader(
            cache: CoverLoaderCacheStub(),
            downloader: downloader,
            maximumConcurrentDownloads: 4
        )
        let sharedURL = URL(string: "https://images.example/shared.png")!

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<8 {
                group.addTask {
                    let url = index < 2
                        ? sharedURL
                        : URL(
                            string: "https://images.example/\(index).png"
                        )!
                    _ = try await loader.load(
                        repositoryID: Int64(index),
                        sourceURL: url
                    )
                }
            }
            try await group.waitForAll()
        }

        let maximumActiveCount = await downloader.maximumActiveCount
        let sharedCallCount = await downloader.callCount(for: sharedURL)
        try expect(
            maximumActiveCount <= 4,
            "远程封面并发数不得超过四"
        )
        try expectEqual(
            sharedCallCount,
            1,
            "同一封面地址并发加载必须复用一个网络请求"
        )
    },
    TestCase("取消唯一远程封面请求会停止下载且不写缓存") {
        let cache = CoverLoaderCacheStub()
        let downloader = CancellableCoverDownloader()
        let loader = RepositoryCoverLoader(
            cache: cache,
            downloader: downloader
        )
        let task = Task {
            try await loader.load(
                repositoryID: 1,
                sourceURL: URL(string: "https://images.example/slow.png")!
            )
        }

        while await !downloader.hasStarted {
            await Task.yield()
        }
        task.cancel()

        do {
            _ = try await task.value
            throw TestFailure(description: "取消后不应返回封面")
        } catch is CancellationError {
            // 预期路径。
        }
        let wasCancelled = await downloader.wasCancelled
        try expect(wasCancelled, "取消应传递到底层下载器")
        try expectEqual(cache.saveCount, 0, "取消后不得写入缓存")
    },
    TestCase("损坏磁盘封面会重新下载而不是继续标记 README") {
        let sourceURL = URL(string: "https://images.example/recover.png")!
        let cache = CoverLoaderCacheStub(
            entries: [
                sourceURL: RepositoryCoverCacheEntry(
                    data: Data("broken".utf8),
                    metadata: RepositoryCoverCacheMetadata(
                        contentType: "image/png",
                        storedAt: Date(timeIntervalSince1970: 1),
                        pixelWidth: 600,
                        pixelHeight: 400
                    )
                )
            ]
        )
        let data = validRepositoryCoverData(width: 360, height: 260)
        let downloader = CoverDownloaderStub(
            response: RepositoryCoverDownloadResponse(
                data: data,
                statusCode: 200,
                contentType: "image/png"
            )
        )
        let loader = RepositoryCoverLoader(
            cache: cache,
            downloader: downloader
        )

        let entry = try await loader.load(
            repositoryID: 7,
            sourceURL: sourceURL
        )

        try expectEqual(entry.data, data, "损坏缓存应由有效远程图片替换")
        let callCount = await downloader.callCount
        try expectEqual(callCount, 1, "损坏缓存必须重新下载")
        try expectEqual(cache.saveCount, 1, "修复后的图片应重新写入缓存")
    },
    TestCase("语言和 seed 共同稳定决定回退封面配色") {
        let swift = FallbackRepositoryCover(
            seed: "00abc",
            initials: "GM",
            languageColorToken: "language.swift"
        )
        let python = FallbackRepositoryCover(
            seed: "00abc",
            initials: "GM",
            languageColorToken: "language.python"
        )
        let swiftVariant = FallbackRepositoryCover(
            seed: "ffabc",
            initials: "GM",
            languageColorToken: "language.swift"
        )

        let first = RepositoryFallbackPaletteResolver.resolve(swift)
        try expectEqual(
            first,
            RepositoryFallbackPaletteResolver.resolve(swift),
            "相同语言与 seed 的配色必须稳定"
        )
        try expect(
            first.family != RepositoryFallbackPaletteResolver.resolve(python).family,
            "不同语言 token 必须影响色系"
        )
        try expect(
            first.variant
                != RepositoryFallbackPaletteResolver.resolve(swiftVariant).variant,
            "seed 必须继续影响渐变变体"
        )
    }
]

private final class CoverLoaderCacheStub: RepositoryCoverCaching,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var entries: [URL: RepositoryCoverCacheEntry]
    private var storedSaveCount = 0

    init(entries: [URL: RepositoryCoverCacheEntry] = [:]) {
        self.entries = entries
    }

    var saveCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedSaveCount
    }

    func load(
        repositoryID _: Int64,
        sourceURL: URL
    ) throws -> RepositoryCoverCacheEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[sourceURL]
    }

    func save(
        data: Data,
        metadata: RepositoryCoverCacheMetadata,
        repositoryID _: Int64,
        sourceURL: URL
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        storedSaveCount += 1
        entries[sourceURL] = RepositoryCoverCacheEntry(
            data: data,
            metadata: metadata
        )
    }

    func clear(repositoryID _: Int64) throws {}
}

private actor CoverDownloaderStub: RepositoryCoverDownloading {
    let response: RepositoryCoverDownloadResponse
    private(set) var callCount = 0

    init(response: RepositoryCoverDownloadResponse) {
        self.response = response
    }

    func download(
        from _: URL,
        maximumByteCount _: Int
    ) async throws -> RepositoryCoverDownloadResponse {
        callCount += 1
        return response
    }
}

private actor ConcurrentCoverDownloader: RepositoryCoverDownloading {
    let data: Data
    private(set) var activeCount = 0
    private(set) var maximumActiveCount = 0
    private var counts: [URL: Int] = [:]

    init(data: Data) {
        self.data = data
    }

    func download(
        from url: URL,
        maximumByteCount _: Int
    ) async throws -> RepositoryCoverDownloadResponse {
        counts[url, default: 0] += 1
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        defer { activeCount -= 1 }
        try await Task.sleep(for: .milliseconds(40))
        return RepositoryCoverDownloadResponse(
            data: data,
            statusCode: 200,
            contentType: "image/png"
        )
    }

    func callCount(for url: URL) -> Int {
        counts[url, default: 0]
    }
}

private actor CancellableCoverDownloader: RepositoryCoverDownloading {
    private(set) var hasStarted = false
    private(set) var wasCancelled = false

    func download(
        from _: URL,
        maximumByteCount _: Int
    ) async throws -> RepositoryCoverDownloadResponse {
        hasStarted = true
        do {
            try await Task.sleep(for: .seconds(30))
            throw TestFailure(description: "测试下载器不应自然完成")
        } catch is CancellationError {
            wasCancelled = true
            throw CancellationError()
        }
    }
}

private func validRepositoryCoverData(width: Int, height: Int) -> Data {
    let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    return representation.representation(
        using: .png,
        properties: [:]
    )!
}
