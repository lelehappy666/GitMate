import Foundation

public protocol LabelMergeAPI: Sendable {
    func issueNumbers(
        labelName: String,
        token: String
    ) async throws -> [Int]
    func addLabels(
        to issueNumber: Int,
        names: [String],
        token: String
    ) async throws
    func removeLabel(
        from issueNumber: Int,
        name: String,
        token: String
    ) async throws
    func deleteLabel(name: String, token: String) async throws
}

public struct LabelMergeProgress: Equatable, Codable, Sendable {
    public let source: String
    public let target: String
    public let completedIssueNumbers: [Int]
    public let failedIssueNumbers: [Int]

    public init(
        source: String,
        target: String,
        completedIssueNumbers: [Int],
        failedIssueNumbers: [Int]
    ) {
        self.source = source
        self.target = target
        self.completedIssueNumbers = completedIssueNumbers
        self.failedIssueNumbers = failedIssueNumbers
    }
}

public protocol LabelMerging: Sendable {
    func merge(
        source: String,
        into target: String,
        token: String,
        completedIssueNumbers: [Int]
    ) async throws -> LabelMergeProgress
}

public enum LabelMergeError: Error, Equatable, Sendable {
    case sourceAndTargetAreEqual
}

extension LabelMergeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sourceAndTargetAreEqual:
            "来源标签和目标标签不能相同。"
        }
    }
}

public final class LabelMergeService: LabelMerging, @unchecked Sendable {
    private let api: any LabelMergeAPI

    public init(api: any LabelMergeAPI) {
        self.api = api
    }

    public func merge(
        source: String,
        into target: String,
        token: String,
        completedIssueNumbers: [Int] = []
    ) async throws -> LabelMergeProgress {
        guard source != target else {
            throw LabelMergeError.sourceAndTargetAreEqual
        }
        let issueNumbers = try await api.issueNumbers(
            labelName: source,
            token: token
        )
        var completed = Set(completedIssueNumbers)
        var failed = Set<Int>()

        for issueNumber in issueNumbers where !completed.contains(issueNumber) {
            try Task.checkCancellation()
            do {
                try await api.addLabels(
                    to: issueNumber,
                    names: [target],
                    token: token
                )
                try await api.removeLabel(
                    from: issueNumber,
                    name: source,
                    token: token
                )
                completed.insert(issueNumber)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failed.insert(issueNumber)
            }
        }

        if failed.isEmpty {
            try await api.deleteLabel(name: source, token: token)
        }

        return LabelMergeProgress(
            source: source,
            target: target,
            completedIssueNumbers: completed.sorted(),
            failedIssueNumbers: failed.sorted()
        )
    }
}
