import Foundation

public protocol SyncDestinationStore: Sendable {
    func destination() -> URL?
    func save(destination: URL) throws
    func clear()
}

public enum SyncDestinationStoreError: Error, LocalizedError, Sendable {
    case invalidDirectory

    public var errorDescription: String? {
        switch self {
        case .invalidDirectory:
            "同步目录必须是本机文件夹。"
        }
    }
}

public final class UserDefaultsSyncDestinationStore: SyncDestinationStore, @unchecked Sendable {
    private static let destinationKey = "GitMate.SyncDestinationPath"

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func destination() -> URL? {
        lock.lock()
        let path = defaults.string(forKey: Self.destinationKey)
        lock.unlock()
        guard let path, !path.isEmpty else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    public func save(destination: URL) throws {
        guard destination.isFileURL else {
            throw SyncDestinationStoreError.invalidDirectory
        }
        lock.lock()
        defaults.set(destination.path, forKey: Self.destinationKey)
        lock.unlock()
    }

    public func clear() {
        lock.lock()
        defaults.removeObject(forKey: Self.destinationKey)
        lock.unlock()
    }
}

public final class InMemorySyncDestinationStore: SyncDestinationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedDestination: URL?

    public init(destination: URL? = nil) {
        storedDestination = destination
    }

    public func destination() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return storedDestination
    }

    public func save(destination: URL) throws {
        guard destination.isFileURL else {
            throw SyncDestinationStoreError.invalidDirectory
        }
        lock.lock()
        storedDestination = destination
        lock.unlock()
    }

    public func clear() {
        lock.lock()
        storedDestination = nil
        lock.unlock()
    }
}
