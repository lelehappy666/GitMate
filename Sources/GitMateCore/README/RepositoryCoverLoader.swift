import Foundation
import ImageIO

public struct RepositoryCoverDownloadResponse: Equatable, Sendable {
    public let data: Data
    public let statusCode: Int
    public let contentType: String?

    public init(data: Data, statusCode: Int, contentType: String?) {
        self.data = data
        self.statusCode = statusCode
        self.contentType = contentType
    }
}

public protocol RepositoryCoverDownloading: Sendable {
    func download(
        from url: URL,
        maximumByteCount: Int
    ) async throws -> RepositoryCoverDownloadResponse
}

public protocol RepositoryCoverLoading: Sendable {
    func load(
        repositoryID: Int64,
        sourceURL: URL
    ) async throws -> RepositoryCoverCacheEntry
}

public enum RepositoryCoverLoadError: Error, Equatable, Sendable {
    case invalidURL
    case invalidHTTPStatus(Int)
    case invalidContentType(String?)
    case responseTooLarge
    case invalidImage
    case imageTooSmall(width: Int, height: Int)
}

public struct RepositoryFallbackPalette: Equatable, Sendable {
    public let family: Int
    public let variant: Int

    public init(family: Int, variant: Int) {
        self.family = family
        self.variant = variant
    }
}

public enum RepositoryFallbackPaletteResolver {
    public static func resolve(
        _ cover: FallbackRepositoryCover
    ) -> RepositoryFallbackPalette {
        RepositoryFallbackPalette(
            family: family(for: cover.languageColorToken),
            variant: (Int(cover.seed.prefix(2), radix: 16) ?? 0) % 4
        )
    }

    private static func family(for token: String) -> Int {
        switch token {
        case "language.swift":
            0
        case "language.typescript", "language.javascript":
            1
        case "language.python":
            2
        case "language.rust":
            3
        case "language.go":
            4
        default:
            token.utf8.reduce(0) { partial, byte in
                (partial &* 31 &+ Int(byte)) % 6
            }
        }
    }
}

public final class URLSessionRepositoryCoverDownloader:
    RepositoryCoverDownloading,
    @unchecked Sendable
{
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func download(
        from url: URL,
        maximumByteCount: Int
    ) async throws -> RepositoryCoverDownloadResponse {
        let (bytes, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse else {
            throw RepositoryCoverLoadError.invalidHTTPStatus(0)
        }
        if response.expectedContentLength > Int64(maximumByteCount) {
            throw RepositoryCoverLoadError.responseTooLarge
        }

        var data = Data()
        data.reserveCapacity(
            min(
                max(Int(response.expectedContentLength), 0),
                maximumByteCount
            )
        )
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumByteCount else {
                throw RepositoryCoverLoadError.responseTooLarge
            }
            data.append(byte)
        }
        return RepositoryCoverDownloadResponse(
            data: data,
            statusCode: response.statusCode,
            contentType: response.value(forHTTPHeaderField: "Content-Type")
        )
    }
}

public actor RepositoryCoverLoader: RepositoryCoverLoading {
    private let cache: any RepositoryCoverCaching
    private let coordinator: RepositoryCoverDownloadCoordinator
    private let minimumPixelDimension: Int

    public init(
        cache: any RepositoryCoverCaching,
        downloader: any RepositoryCoverDownloading =
            URLSessionRepositoryCoverDownloader(),
        maximumConcurrentDownloads: Int = 4,
        maximumResponseByteCount: Int = 8 * 1_024 * 1_024,
        minimumPixelDimension: Int = 240
    ) {
        self.cache = cache
        self.minimumPixelDimension = max(minimumPixelDimension, 1)
        coordinator = RepositoryCoverDownloadCoordinator(
            downloader: downloader,
            maximumConcurrentDownloads: max(maximumConcurrentDownloads, 1),
            maximumResponseByteCount: max(maximumResponseByteCount, 1),
            minimumPixelDimension: max(minimumPixelDimension, 1)
        )
    }

    public func load(
        repositoryID: Int64,
        sourceURL: URL
    ) async throws -> RepositoryCoverCacheEntry {
        try Task.checkCancellation()
        guard READMEURLPolicy.resolvedRemoteURL(
            sourceURL.absoluteString,
            baseURL: nil
        ) != nil else {
            throw RepositoryCoverLoadError.invalidURL
        }

        if let cached = try? cache.load(
            repositoryID: repositoryID,
            sourceURL: sourceURL
        ), let dimensions = try? RepositoryCoverImageValidator.dimensions(
            data: cached.data,
            minimumPixelDimension: minimumPixelDimension
        ) {
            return RepositoryCoverCacheEntry(
                data: cached.data,
                metadata: RepositoryCoverCacheMetadata(
                    contentType: cached.metadata.contentType,
                    storedAt: cached.metadata.storedAt,
                    pixelWidth: dimensions.width,
                    pixelHeight: dimensions.height
                )
            )
        }

        let entry = try await coordinator.download(sourceURL)
        try Task.checkCancellation()
        try cache.save(
            data: entry.data,
            metadata: entry.metadata,
            repositoryID: repositoryID,
            sourceURL: sourceURL
        )
        return entry
    }
}

enum RepositoryCoverImageValidator {
    static func dimensions(
        data: Data,
        minimumPixelDimension: Int
    ) throws -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            nil
        ), CGImageSourceGetCount(source) > 0,
        let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
        ) as? [CFString: Any],
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
        width > 0,
        height > 0
        else {
            throw RepositoryCoverLoadError.invalidImage
        }
        guard width >= minimumPixelDimension,
              height >= minimumPixelDimension
        else {
            throw RepositoryCoverLoadError.imageTooSmall(
                width: width,
                height: height
            )
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512
        ]
        guard CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) != nil else {
            throw RepositoryCoverLoadError.invalidImage
        }
        return (width, height)
    }
}

private actor RepositoryCoverDownloadCoordinator {
    private struct Flight {
        let id: UUID
        let task: Task<RepositoryCoverCacheEntry, Error>
        var waiters: Set<UUID>
    }

    private let downloader: any RepositoryCoverDownloading
    private let gate: RepositoryCoverDownloadGate
    private let maximumResponseByteCount: Int
    private let minimumPixelDimension: Int
    private var flights: [URL: Flight] = [:]

    init(
        downloader: any RepositoryCoverDownloading,
        maximumConcurrentDownloads: Int,
        maximumResponseByteCount: Int,
        minimumPixelDimension: Int
    ) {
        self.downloader = downloader
        gate = RepositoryCoverDownloadGate(
            maximumConcurrentDownloads: maximumConcurrentDownloads
        )
        self.maximumResponseByteCount = maximumResponseByteCount
        self.minimumPixelDimension = minimumPixelDimension
    }

    func download(_ sourceURL: URL) async throws -> RepositoryCoverCacheEntry {
        let waiterID = UUID()
        let flightID: UUID
        let task: Task<RepositoryCoverCacheEntry, Error>
        if var flight = flights[sourceURL] {
            flight.waiters.insert(waiterID)
            flights[sourceURL] = flight
            flightID = flight.id
            task = flight.task
        } else {
            let id = UUID()
            let downloader = self.downloader
            let gate = self.gate
            let maximumResponseByteCount = self.maximumResponseByteCount
            let minimumPixelDimension = self.minimumPixelDimension
            let newTask = Task {
                try await gate.acquire()
                defer {
                    Task {
                        await gate.release()
                    }
                }
                try Task.checkCancellation()
                let response = try await downloader.download(
                    from: sourceURL,
                    maximumByteCount: maximumResponseByteCount
                )
                return try Self.validatedEntry(
                    response,
                    maximumResponseByteCount: maximumResponseByteCount,
                    minimumPixelDimension: minimumPixelDimension
                )
            }
            flights[sourceURL] = Flight(
                id: id,
                task: newTask,
                waiters: [waiterID]
            )
            flightID = id
            task = newTask
        }

        return try await withTaskCancellationHandler {
            do {
                let entry = try await task.value
                try Task.checkCancellation()
                releaseWaiter(
                    sourceURL: sourceURL,
                    flightID: flightID,
                    waiterID: waiterID,
                    cancelIfEmpty: false
                )
                return entry
            } catch {
                releaseWaiter(
                    sourceURL: sourceURL,
                    flightID: flightID,
                    waiterID: waiterID,
                    cancelIfEmpty: false
                )
                throw error
            }
        } onCancel: {
            Task {
                await self.releaseWaiter(
                    sourceURL: sourceURL,
                    flightID: flightID,
                    waiterID: waiterID,
                    cancelIfEmpty: true
                )
            }
        }
    }

    private func releaseWaiter(
        sourceURL: URL,
        flightID: UUID,
        waiterID: UUID,
        cancelIfEmpty: Bool
    ) {
        guard var flight = flights[sourceURL],
              flight.id == flightID,
              flight.waiters.remove(waiterID) != nil
        else {
            return
        }
        if flight.waiters.isEmpty {
            flights[sourceURL] = nil
            if cancelIfEmpty {
                flight.task.cancel()
            }
        } else {
            flights[sourceURL] = flight
        }
    }

    private static func validatedEntry(
        _ response: RepositoryCoverDownloadResponse,
        maximumResponseByteCount: Int,
        minimumPixelDimension: Int
    ) throws -> RepositoryCoverCacheEntry {
        guard (200..<300).contains(response.statusCode) else {
            throw RepositoryCoverLoadError.invalidHTTPStatus(
                response.statusCode
            )
        }
        let contentType = response.contentType?
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let allowedTypes = [
            "image/png",
            "image/jpeg",
            "image/gif",
            "image/webp",
            "image/heic",
            "image/heif"
        ]
        guard let contentType, allowedTypes.contains(contentType) else {
            throw RepositoryCoverLoadError.invalidContentType(
                response.contentType
            )
        }
        guard response.data.count <= maximumResponseByteCount else {
            throw RepositoryCoverLoadError.responseTooLarge
        }
        let dimensions = try RepositoryCoverImageValidator.dimensions(
            data: response.data,
            minimumPixelDimension: minimumPixelDimension
        )
        return RepositoryCoverCacheEntry(
            data: response.data,
            metadata: RepositoryCoverCacheMetadata(
                contentType: contentType,
                storedAt: Date(),
                pixelWidth: dimensions.width,
                pixelHeight: dimensions.height
            )
        )
    }
}

package actor RepositoryCoverDownloadGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let maximumConcurrentDownloads: Int
    private var activeCount = 0
    private var waiters: [Waiter] = []

    package init(maximumConcurrentDownloads: Int) {
        self.maximumConcurrentDownloads = maximumConcurrentDownloads
    }

    package func acquire() async throws {
        try Task.checkCancellation()
        if activeCount < maximumConcurrentDownloads {
            activeCount += 1
            return
        }

        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(
                    Waiter(id: waiterID, continuation: continuation)
                )
            }
            do {
                try Task.checkCancellation()
            } catch {
                release()
                throw error
            }
        } onCancel: {
            Task {
                await self.cancel(waiterID)
            }
        }
    }

    package func release() {
        if waiters.isEmpty {
            activeCount = max(activeCount - 1, 0)
            return
        }
        let waiter = waiters.removeFirst()
        waiter.continuation.resume()
    }

    private func cancel(_ waiterID: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else {
            return
        }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
}
