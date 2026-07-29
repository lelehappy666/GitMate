import Foundation

public struct GitRemote: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let fetchURL: String
    public let pushURL: String
    public let fetchProtocol: GitRemoteProtocol
    public let pushProtocol: GitRemoteProtocol
    public let trackingBranches: [String]

    public init(
        name: String,
        fetchURL: String,
        pushURL: String,
        fetchProtocol: GitRemoteProtocol,
        pushProtocol: GitRemoteProtocol,
        trackingBranches: [String]
    ) {
        self.name = name
        self.fetchURL = fetchURL
        self.pushURL = pushURL
        self.fetchProtocol = fetchProtocol
        self.pushProtocol = pushProtocol
        self.trackingBranches = trackingBranches
    }
}

public struct GitRemoteChange: Equatable, Sendable {
    public let name: String
    public let fetchURL: String
    public let pushURL: String?

    public init(
        name: String,
        fetchURL: String,
        pushURL: String?
    ) {
        self.name = name
        self.fetchURL = fetchURL
        self.pushURL = pushURL
    }
}

public struct RemoteRemovalImpact: Equatable, Sendable {
    public let remote: String
    public let trackingBranches: [String]
    public let confirmation: RiskConfirmation

    public init(
        remote: String,
        trackingBranches: [String],
        confirmation: RiskConfirmation
    ) {
        self.remote = remote
        self.trackingBranches = trackingBranches
        self.confirmation = confirmation
    }
}

public enum RemoteConnectionResult: Equatable, Sendable {
    case connected(referenceCount: Int)
    case authenticationRequired
    case sshAgentUnavailable
}
