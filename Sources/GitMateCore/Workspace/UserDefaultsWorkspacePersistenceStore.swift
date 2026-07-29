import Foundation

public enum WorkspacePersistenceError: Error, Sendable {
    case encodingFailed(String)
    case decodingFailed(String)
}

extension WorkspacePersistenceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .encodingFailed(message):
            "无法保存仓库工作区数据：\(message)"
        case let .decodingFailed(message):
            "无法读取仓库工作区数据：\(message)"
        }
    }
}

public final class UserDefaultsWorkspacePersistenceStore:
    WorkspacePersistenceStore,
    @unchecked Sendable
{
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func savedViews(
        accountID: String,
        repositoryID: Int64
    ) throws -> [SavedIssueView] {
        try decode(
            [SavedIssueView].self,
            key: key(
                accountID: accountID,
                repositoryID: repositoryID,
                suffix: "SavedIssueViews"
            )
        ) ?? []
    }

    public func saveViews(
        _ views: [SavedIssueView],
        accountID: String,
        repositoryID: Int64
    ) throws {
        try encode(
            views,
            key: key(
                accountID: accountID,
                repositoryID: repositoryID,
                suffix: "SavedIssueViews"
            )
        )
    }

    public func issueDraft(
        accountID: String,
        repositoryID: Int64
    ) throws -> IssueDraft? {
        try decode(
            IssueDraft.self,
            key: key(
                accountID: accountID,
                repositoryID: repositoryID,
                suffix: "IssueDraft"
            )
        )
    }

    public func saveDraft(
        _ draft: IssueDraft,
        accountID: String,
        repositoryID: Int64
    ) throws {
        try encode(
            draft,
            key: key(
                accountID: accountID,
                repositoryID: repositoryID,
                suffix: "IssueDraft"
            )
        )
    }

    public func deleteDraft(accountID: String, repositoryID: Int64) throws {
        lock.lock()
        defaults.removeObject(
            forKey: key(
                accountID: accountID,
                repositoryID: repositoryID,
                suffix: "IssueDraft"
            )
        )
        lock.unlock()
    }

    private func key(
        accountID: String,
        repositoryID: Int64,
        suffix: String
    ) -> String {
        "GitMate.Workspace.\(accountID).\(repositoryID).\(suffix)"
    }

    private func encode<Value: Encodable>(_ value: Value, key: String) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw WorkspacePersistenceError.encodingFailed(
                error.localizedDescription
            )
        }
        lock.lock()
        defaults.set(data, forKey: key)
        lock.unlock()
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        key: String
    ) throws -> Value? {
        lock.lock()
        let data = defaults.data(forKey: key)
        lock.unlock()
        guard let data else {
            return nil
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw WorkspacePersistenceError.decodingFailed(
                error.localizedDescription
            )
        }
    }
}
