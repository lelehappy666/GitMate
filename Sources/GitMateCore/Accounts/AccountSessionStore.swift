import Foundation

public protocol AccountSessionStore: Sendable {
    func save(account: GitHubAccount) throws
    func account() throws -> GitHubAccount?
    func clear() throws
}

public enum AccountSessionStoreError: Error, LocalizedError, Sendable {
    case encodingFailed(String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .encodingFailed(message):
            "无法保存 GitHub 登录会话：\(message)"
        case let .decodingFailed(message):
            "无法读取 GitHub 登录会话：\(message)"
        }
    }
}

public final class UserDefaultsAccountSessionStore: AccountSessionStore, @unchecked Sendable {
    private static let accountKey = "GitMate.ActiveGitHubAccount"

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func save(account: GitHubAccount) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(account)
        } catch {
            throw AccountSessionStoreError.encodingFailed(error.localizedDescription)
        }

        lock.lock()
        defaults.set(data, forKey: Self.accountKey)
        lock.unlock()
    }

    public func account() throws -> GitHubAccount? {
        lock.lock()
        let data = defaults.data(forKey: Self.accountKey)
        lock.unlock()
        guard let data else { return nil }

        do {
            return try JSONDecoder().decode(GitHubAccount.self, from: data)
        } catch {
            throw AccountSessionStoreError.decodingFailed(error.localizedDescription)
        }
    }

    public func clear() throws {
        lock.lock()
        defaults.removeObject(forKey: Self.accountKey)
        lock.unlock()
    }
}

public final class InMemoryAccountSessionStore: AccountSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedAccount: GitHubAccount?

    public init(account: GitHubAccount? = nil) {
        storedAccount = account
    }

    public func save(account: GitHubAccount) throws {
        lock.lock()
        storedAccount = account
        lock.unlock()
    }

    public func account() throws -> GitHubAccount? {
        lock.lock()
        defer { lock.unlock() }
        return storedAccount
    }

    public func clear() throws {
        lock.lock()
        storedAccount = nil
        lock.unlock()
    }
}
