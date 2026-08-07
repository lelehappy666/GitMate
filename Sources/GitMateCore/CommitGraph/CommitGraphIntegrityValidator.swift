import Foundation

public enum CommitGraphIntegrityValidator {
    public static func validate(_ snapshot: CommitGraphSnapshot) -> CommitGraphIntegrityReport {
        let commitHashes = snapshot.commitsNewestFirst.map(\.fullHash)
        let commitHashSet = Set(commitHashes)
        let duplicateCommitHashes = duplicates(in: commitHashes)

        let edgeIDs = snapshot.commitsNewestFirst.flatMap { commit in
            commit.parentHashes.enumerated().map { parentIndex, parentHash in
                "\(commit.fullHash)->\(parentHash)#\(parentIndex)"
            }
        }
        let duplicateEdgeIDs = duplicates(in: edgeIDs)
        let parentHashes = snapshot.commitsNewestFirst.flatMap(\.parentHashes)
        let missingParentHashSet = Set(parentHashes).subtracting(commitHashSet)
        let shallowBoundaryHashSet = snapshot.fingerprint.isShallow
            ? snapshot.shallowBoundaryParentHashes
            : []
        let shallowBoundaryParentHashes = missingParentHashSet
            .intersection(shallowBoundaryHashSet)
            .sorted()
        let missingParentHashes = missingParentHashSet
            .subtracting(shallowBoundaryHashSet)
            .sorted()
        var referenceTargets = Set(snapshot.fingerprint.references.map(\.targetHash))
        if let headHash = snapshot.fingerprint.headHash {
            referenceTargets.insert(headHash)
        }
        let missingReferenceTargets = referenceTargets
            .subtracting(commitHashSet)
            .sorted()
        let expectedRelationshipCount = parentHashes.filter {
            !shallowBoundaryHashSet.contains($0)
        }.count
        let actualRelationshipCount = parentHashes.filter { commitHashSet.contains($0) }.count
        var commitIndexByHash: [String: Int] = [:]
        for (index, commit) in snapshot.commitsNewestFirst.enumerated()
        where commitIndexByHash[commit.fullHash] == nil {
            commitIndexByHash[commit.fullHash] = index
        }
        let topologyOrderViolations: [CommitGraphTopologyOrderViolation] =
            snapshot.commitsNewestFirst.enumerated().flatMap { indexedCommit in
                let (childIndex, commit) = indexedCommit
                return commit.parentHashes.compactMap {
                    parentHash -> CommitGraphTopologyOrderViolation? in
                    guard let parentIndex = commitIndexByHash[parentHash],
                          parentIndex <= childIndex
                    else {
                        return nil
                    }
                    return CommitGraphTopologyOrderViolation(
                        childHash: commit.fullHash,
                        childIndex: childIndex,
                        parentHash: parentHash,
                        parentIndex: parentIndex
                    )
                }
            }
            .sorted {
                if $0.childIndex != $1.childIndex {
                    return $0.childIndex < $1.childIndex
                }
                if $0.parentIndex != $1.parentIndex {
                    return $0.parentIndex < $1.parentIndex
                }
                if $0.childHash != $1.childHash {
                    return $0.childHash < $1.childHash
                }
                return $0.parentHash < $1.parentHash
            }

        let isInvalid = snapshot.expectedCommitCount != commitHashes.count
            || expectedRelationshipCount != actualRelationshipCount
            || !duplicateCommitHashes.isEmpty
            || !duplicateEdgeIDs.isEmpty
            || !missingParentHashes.isEmpty
            || !missingReferenceTargets.isEmpty
            || !topologyOrderViolations.isEmpty
        let status: CommitGraphIntegrityStatus
        if isInvalid {
            status = .invalid
        } else if !shallowBoundaryParentHashes.isEmpty {
            status = .warning
        } else {
            status = .valid
        }

        return CommitGraphIntegrityReport(
            status: status,
            expectedCommitCount: snapshot.expectedCommitCount,
            actualCommitCount: commitHashes.count,
            expectedRelationshipCount: expectedRelationshipCount,
            actualRelationshipCount: actualRelationshipCount,
            duplicateCommitHashes: duplicateCommitHashes,
            duplicateEdgeIDs: duplicateEdgeIDs,
            missingParentHashes: missingParentHashes,
            missingReferenceTargets: missingReferenceTargets,
            shallowBoundaryParentHashes: shallowBoundaryParentHashes,
            topologyOrderViolations: topologyOrderViolations,
            checkedAt: Date()
        )
    }

    private static func duplicates(in values: [String]) -> [String] {
        var seen = Set<String>()
        var duplicates = Set<String>()
        for value in values where !seen.insert(value).inserted {
            duplicates.insert(value)
        }
        return duplicates.sorted()
    }
}
