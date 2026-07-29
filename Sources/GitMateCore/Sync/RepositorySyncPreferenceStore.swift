import Foundation

public protocol RepositorySyncPreferenceStoring: Sendable {
    func load(accountID: String) throws -> [RepositorySyncPreference]

    func save(
        _ preferences: [RepositorySyncPreference],
        accountID: String
    ) throws

    func clear(accountID: String) throws
}

public final class UserDefaultsRepositorySyncPreferenceStore:
    RepositorySyncPreferenceStoring,
    @unchecked Sendable
{
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(
        accountID: String
    ) throws -> [RepositorySyncPreference] {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard let data = defaults.data(forKey: key(for: accountID)) else {
            return []
        }
        return try JSONDecoder().decode(
            [RepositorySyncPreference].self,
            from: data
        )
    }

    public func save(
        _ preferences: [RepositorySyncPreference],
        accountID: String
    ) throws {
        lock.lock()
        defer {
            lock.unlock()
        }
        let normalized = Dictionary(
            preferences.map { ($0.repositoryID, $0) },
            uniquingKeysWith: { _, newest in newest }
        )
        .values
        .sorted { $0.repositoryID < $1.repositoryID }
        defaults.set(
            try JSONEncoder().encode(normalized),
            forKey: key(for: accountID)
        )
    }

    public func clear(accountID: String) throws {
        lock.lock()
        defer {
            lock.unlock()
        }
        defaults.removeObject(forKey: key(for: accountID))
    }

    private func key(for accountID: String) -> String {
        let encodedAccountID = Data(accountID.utf8).base64EncodedString()
        return "GitMate.RepositorySyncPreferences.\(encodedAccountID)"
    }
}
