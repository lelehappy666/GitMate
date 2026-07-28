import Foundation

public protocol CredentialStore: Sendable {
    func save(token: String, accountID: String) throws
    func token(accountID: String) throws -> String?
    func deleteToken(accountID: String) throws
}

public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String: String] = [:]

    public init() {}

    public func save(token: String, accountID: String) throws {
        lock.lock()
        tokens[accountID] = token
        lock.unlock()
    }

    public func token(accountID: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return tokens[accountID]
    }

    public func deleteToken(accountID: String) throws {
        lock.lock()
        tokens.removeValue(forKey: accountID)
        lock.unlock()
    }
}
