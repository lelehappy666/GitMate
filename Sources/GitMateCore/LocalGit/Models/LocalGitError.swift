import Foundation

public enum LocalGitError: Error, Equatable, Sendable {
    case notGitRepository
    case repositoryBusy
    case repositoryLocked
    case workingTreeNotClean
    case invalidReference
    case invalidPath
    case unsupportedRemoteProtocol
    case missingCredential
    case emptyCommitMessage
    case emptyIndex
    case hookFailed(String)
    case signingFailed(String)
    case stalePatch
    case binaryConflictRequiresWholeFileChoice
    case confirmationExpired
    case operationInProgress
    case authenticationExpired
    case sshAgentUnavailable
    case sshHostVerificationFailed
    case networkUnavailable
    case networkTimedOut
    case remoteRejected(String)
    case nonFastForward
    case unsupportedGitCapability(String)
}

public struct LocalGitUserFacingError: Equatable, Sendable {
    public let message: String
    public let recoverySuggestion: String?

    public init(message: String, recoverySuggestion: String? = nil) {
        self.message = message
        self.recoverySuggestion = recoverySuggestion
    }
}
