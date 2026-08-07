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

        let isInvalid = snapshot.expectedCommitCount != commitHashes.count
            || expectedRelationshipCount != actualRelationshipCount
            || !duplicateCommitHashes.isEmpty
            || !duplicateEdgeIDs.isEmpty
            || !missingParentHashes.isEmpty
            || !missingReferenceTargets.isEmpty
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
