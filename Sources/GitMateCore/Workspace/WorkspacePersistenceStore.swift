import Foundation

public protocol WorkspacePersistenceStore: Sendable {
    func savedViews(
        accountID: String,
        repositoryID: Int64
    ) throws -> [SavedIssueView]
    func saveViews(
        _ views: [SavedIssueView],
        accountID: String,
        repositoryID: Int64
    ) throws
    func issueDraft(
        accountID: String,
        repositoryID: Int64
    ) throws -> IssueDraft?
    func saveDraft(
        _ draft: IssueDraft,
        accountID: String,
        repositoryID: Int64
    ) throws
    func deleteDraft(accountID: String, repositoryID: Int64) throws
}

public final class InMemoryWorkspacePersistenceStore:
    WorkspacePersistenceStore,
    @unchecked Sendable
{
    private struct Key: Hashable {
        let accountID: String
        let repositoryID: Int64
    }

    private let lock = NSLock()
    private var views: [Key: [SavedIssueView]] = [:]
    private var drafts: [Key: IssueDraft] = [:]

    public init() {}

    public func savedViews(
        accountID: String,
        repositoryID: Int64
    ) throws -> [SavedIssueView] {
        lock.lock()
        defer { lock.unlock() }
        return views[Key(accountID: accountID, repositoryID: repositoryID)] ?? []
    }

    public func saveViews(
        _ views: [SavedIssueView],
        accountID: String,
        repositoryID: Int64
    ) throws {
        lock.lock()
        self.views[Key(accountID: accountID, repositoryID: repositoryID)] = views
        lock.unlock()
    }

    public func issueDraft(
        accountID: String,
        repositoryID: Int64
    ) throws -> IssueDraft? {
        lock.lock()
        defer { lock.unlock() }
        return drafts[Key(accountID: accountID, repositoryID: repositoryID)]
    }

    public func saveDraft(
        _ draft: IssueDraft,
        accountID: String,
        repositoryID: Int64
    ) throws {
        lock.lock()
        drafts[Key(accountID: accountID, repositoryID: repositoryID)] = draft
        lock.unlock()
    }

    public func deleteDraft(accountID: String, repositoryID: Int64) throws {
        lock.lock()
        drafts.removeValue(
            forKey: Key(accountID: accountID, repositoryID: repositoryID)
        )
        lock.unlock()
    }
}
