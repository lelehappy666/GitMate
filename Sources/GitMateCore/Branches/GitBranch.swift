import Foundation

public enum BranchLocation: String, Codable, Sendable {
    case local
    case remote
    case localAndRemote
}

public struct BranchComparison: Equatable, Codable, Sendable {
    public let aheadBy: Int
    public let behindBy: Int

    public init(aheadBy: Int, behindBy: Int) {
        self.aheadBy = max(0, aheadBy)
        self.behindBy = max(0, behindBy)
    }
}

public enum BranchTrackingStatus: Equatable, Codable, Sendable {
    case localOnly
    case remoteOnly
    case synchronized
    case ahead(Int)
    case behind(Int)
    case diverged(aheadBy: Int, behindBy: Int)
}

public struct GitBranch: Identifiable, Equatable, Codable, Sendable {
    public var id: String { name }

    public let name: String
    public var localSHA: String?
    public var remoteSHA: String?
    public var remoteName: String?
    public var upstreamName: String?
    public var authorName: String?
    public var isDefault: Bool
    public var isProtected: Bool
    public var lastCommitDate: Date?
    public var comparison: BranchComparison?

    public init(
        name: String,
        localSHA: String?,
        remoteSHA: String?,
        remoteName: String? = nil,
        upstreamName: String?,
        authorName: String? = nil,
        isDefault: Bool = false,
        isProtected: Bool = false,
        lastCommitDate: Date? = nil,
        comparison: BranchComparison? = nil
    ) {
        self.name = name
        self.localSHA = localSHA
        self.remoteSHA = remoteSHA
        self.remoteName = remoteName
        self.upstreamName = upstreamName
        self.authorName = authorName
        self.isDefault = isDefault
        self.isProtected = isProtected
        self.lastCommitDate = lastCommitDate
        self.comparison = comparison
    }

    public var location: BranchLocation {
        switch (localSHA, remoteSHA) {
        case (.some, .none):
            .local
        case (.none, .some):
            .remote
        case (.some, .some):
            .localAndRemote
        case (.none, .none):
            upstreamName == nil ? .local : .remote
        }
    }

    public var trackingStatus: BranchTrackingStatus {
        switch (localSHA, remoteSHA) {
        case (.some, .none):
            return .localOnly
        case (.none, .some):
            return .remoteOnly
        case let (.some(local), .some(remote)) where local == remote:
            return .synchronized
        case (.some, .some):
            let aheadBy = comparison?.aheadBy ?? 0
            let behindBy = comparison?.behindBy ?? 0
            if aheadBy > 0, behindBy == 0 {
                return .ahead(aheadBy)
            }
            if behindBy > 0, aheadBy == 0 {
                return .behind(behindBy)
            }
            return .diverged(aheadBy: aheadBy, behindBy: behindBy)
        case (.none, .none):
            return upstreamName == nil ? .localOnly : .remoteOnly
        }
    }
}
