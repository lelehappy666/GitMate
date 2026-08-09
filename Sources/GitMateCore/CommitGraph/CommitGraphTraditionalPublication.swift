import Foundation

public enum CommitGraphTraditionalPublicationState:
    String,
    Equatable,
    Sendable
{
    case remoteKnown
    case localUnpushed
    case unclassified
}

/// 传统提交图使用的不可变发布状态索引。
///
/// 该索引在完整快照派生阶段构建一次，绘制行和连线时只做 O(1) 查询。
public struct CommitGraphTraditionalPublicationIndex:
    Equatable,
    Sendable
{
    private let remoteReachableHashes: Set<String>
    private let localReachableHashes: Set<String>

    public init(
        remoteReachableHashes: Set<String>,
        localReachableHashes: Set<String>
    ) {
        self.remoteReachableHashes = remoteReachableHashes
        self.localReachableHashes = localReachableHashes
    }

    public static let empty = CommitGraphTraditionalPublicationIndex(
        remoteReachableHashes: [],
        localReachableHashes: []
    )

    public static func build(
        snapshot: CommitGraphSnapshot
    ) -> CommitGraphTraditionalPublicationIndex {
        let parentsByHash = Dictionary(
            snapshot.commitsNewestFirst.map {
                ($0.fullHash, $0.parentHashes)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let localTips = snapshot.fingerprint.references.compactMap {
            $0.kind == .localBranch ? $0.targetHash : nil
        }
        let remoteTips = snapshot.fingerprint.references.compactMap {
            $0.kind == .remoteBranch ? $0.targetHash : nil
        }
        return CommitGraphTraditionalPublicationIndex(
            remoteReachableHashes: reachableHashes(
                from: remoteTips,
                parentsByHash: parentsByHash
            ),
            localReachableHashes: reachableHashes(
                from: localTips,
                parentsByHash: parentsByHash
            )
        )
    }

    public func state(
        for hash: String
    ) -> CommitGraphTraditionalPublicationState {
        if remoteReachableHashes.contains(hash) { return .remoteKnown }
        if localReachableHashes.contains(hash) { return .localUnpushed }
        return .unclassified
    }

    public func isDashed(childHash: String) -> Bool {
        state(for: childHash) == .localUnpushed
    }

    private static func reachableHashes(
        from tips: [String],
        parentsByHash: [String: [String]]
    ) -> Set<String> {
        var reachable = Set<String>()
        var stack = Array(Set(tips))
        while let hash = stack.popLast() {
            guard parentsByHash[hash] != nil,
                  reachable.insert(hash).inserted
            else { continue }
            stack.append(contentsOf: parentsByHash[hash] ?? [])
        }
        return reachable
    }
}
