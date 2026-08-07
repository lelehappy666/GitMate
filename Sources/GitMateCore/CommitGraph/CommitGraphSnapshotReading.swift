import Foundation

/// 读取用于构建提交图的完整、只读 Git 快照。
public protocol CommitGraphSnapshotReading: Sendable {
    func fingerprint(
        repositoryURL: URL
    ) async throws -> CommitGraphReferenceFingerprint

    func snapshot(
        repositoryURL: URL,
        fingerprint: CommitGraphReferenceFingerprint
    ) async throws -> CommitGraphSnapshot
}
