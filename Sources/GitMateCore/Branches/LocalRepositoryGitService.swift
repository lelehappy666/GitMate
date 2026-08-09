import Foundation

public struct WorkingTreeStatus: Equatable, Codable, Sendable {
    public let changedFiles: [String]

    public init(changedFiles: [String]) {
        self.changedFiles = changedFiles
    }

    public var isClean: Bool {
        changedFiles.isEmpty
    }
}

public protocol LocalRepositoryGitService: Sendable {
    func branches(at directory: URL) async throws -> [GitBranch]
    func tags(at directory: URL) async throws -> [GitTag]
    func workingTreeStatus(at directory: URL) async throws -> WorkingTreeStatus
    func comparison(
        local: String,
        remote: String,
        at directory: URL
    ) async throws -> BranchComparison
    func createBranch(
        _ name: String,
        startPoint: String,
        at directory: URL
    ) async throws
    func checkoutBranch(_ name: String, at directory: URL) async throws
    func mergeBranch(_ source: String, at directory: URL) async throws
    func setUpstream(
        branch: String,
        upstream: String,
        at directory: URL
    ) async throws
    func pushBranch(
        _ name: String,
        remote: String,
        at directory: URL
    ) async throws
    func deleteBranch(
        _ name: String,
        remote: String?,
        force: Bool,
        at directory: URL
    ) async throws
    func createTag(
        _ name: String,
        target: String,
        message: String?,
        at directory: URL
    ) async throws
    func pushTag(
        _ name: String,
        remote: String,
        at directory: URL
    ) async throws
    func fetchTags(remote: String, at directory: URL) async throws
    func deleteTag(
        _ name: String,
        remote: String?,
        at directory: URL
    ) async throws
}
