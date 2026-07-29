@preconcurrency import Dispatch
import Darwin
import Foundation

public protocol RepositoryFileSystemWatching: Sendable {
    func events(repositoryURL: URL) -> AsyncStream<Void>
}

public struct RepositoryFileSystemWatcher: RepositoryFileSystemWatching,
    Sendable
{
    private let debounce: Duration

    public init(debounce: Duration = .milliseconds(300)) {
        self.debounce = debounce
    }

    public func events(repositoryURL: URL) -> AsyncStream<Void> {
        AsyncStream { continuation in
            do {
                let state = try RepositoryWatchState(
                    repositoryURL: repositoryURL,
                    debounce: debounce,
                    continuation: continuation
                )
                state.start()
                continuation.onTermination = { _ in
                    state.cancel()
                }
            } catch {
                continuation.finish()
            }
        }
    }
}

private final class RepositoryWatchState: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "cn.gitmate.localgit.repository-watcher"
    )
    private let delay: DispatchTimeInterval
    private let continuation: AsyncStream<Void>.Continuation
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private var eventGeneration: UInt64 = 0
    private var isCancelled = false

    init(
        repositoryURL: URL,
        debounce: Duration,
        continuation: AsyncStream<Void>.Continuation
    ) throws {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        self.delay = Self.dispatchInterval(for: debounce)
        self.continuation = continuation

        let watchedURLs = [
            repository,
            try Self.gitDirectory(repositoryURL: repository)
        ]
        for url in watchedURLs {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else {
                for existingDescriptor in fileDescriptors {
                    close(existingDescriptor)
                }
                throw LocalGitError.notGitRepository
            }
            fileDescriptors.append(descriptor)
        }
    }

    func start() {
        queue.async {
            guard !self.isCancelled else {
                return
            }
            self.sources = self.fileDescriptors.map { descriptor in
                let source = DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: descriptor,
                    eventMask: [
                        .write,
                        .delete,
                        .rename,
                        .extend,
                        .attrib,
                        .link,
                        .revoke
                    ],
                    queue: self.queue
                )
                source.setEventHandler { [weak self] in
                    self?.scheduleEvent()
                }
                source.resume()
                return source
            }
        }
    }

    func cancel() {
        queue.async {
            guard !self.isCancelled else {
                return
            }
            self.isCancelled = true
            self.eventGeneration &+= 1
            for source in self.sources {
                source.cancel()
            }
            self.sources.removeAll()
            for descriptor in self.fileDescriptors {
                close(descriptor)
            }
            self.fileDescriptors.removeAll()
        }
    }

    private func scheduleEvent() {
        guard !isCancelled else {
            return
        }
        eventGeneration &+= 1
        let scheduledGeneration = eventGeneration
        queue.asyncAfter(deadline: .now() + delay) {
            guard !self.isCancelled,
                  self.eventGeneration == scheduledGeneration
            else {
                return
            }
            self.continuation.yield()
        }
    }

    private static func gitDirectory(repositoryURL: URL) throws -> URL {
        let metadataURL = repositoryURL.appending(path: ".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: metadataURL.path,
            isDirectory: &isDirectory
        ) else {
            throw LocalGitError.notGitRepository
        }
        if isDirectory.boolValue {
            return metadataURL
        }

        let content = try String(
            contentsOf: metadataURL,
            encoding: .utf8
        )
        let prefix = "gitdir:"
        guard content.lowercased().hasPrefix(prefix) else {
            throw LocalGitError.notGitRepository
        }
        let path = content
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if NSString(string: path).isAbsolutePath {
            return URL(fileURLWithPath: path)
        }
        return repositoryURL
            .appending(path: path)
            .standardizedFileURL
    }

    private static func dispatchInterval(
        for duration: Duration
    ) -> DispatchTimeInterval {
        let components = duration.components
        let seconds = max(components.seconds, 0)
        let nanosecondsFromAttoseconds = max(
            components.attoseconds / 1_000_000_000,
            0
        )
        let totalNanoseconds = seconds * 1_000_000_000
            + nanosecondsFromAttoseconds
        return .nanoseconds(
            Int(min(totalNanoseconds, Int64(Int.max)))
        )
    }
}
