import Foundation

public struct GitCredentialContext: Equatable, Sendable {
    public let accountID: String

    public init(accountID: String) {
        self.accountID = accountID
    }
}

public struct GitCredentialEnvironment: Sendable {
    private let credentialStore: any CredentialStore
    private let transportPolicy: GitRemoteTransportPolicy

    public init(
        credentialStore: any CredentialStore,
        transportPolicy: GitRemoteTransportPolicy = .production
    ) {
        self.credentialStore = credentialStore
        self.transportPolicy = transportPolicy
    }

    public func environment(
        remoteURLString: String,
        context: GitCredentialContext
    ) throws -> [String: String] {
        let remoteProtocol = try transportPolicy.validate(
            remoteURLString: remoteURLString
        )
        var environment = ["GIT_TERMINAL_PROMPT": "0"]

        switch remoteProtocol {
        case .https:
            guard let token = try credentialStore.token(
                accountID: context.accountID
            ), !token.isEmpty else {
                throw LocalGitError.missingCredential
            }
            let credential = Data(
                "x-access-token:\(token)".utf8
            ).base64EncodedString()
            environment["GIT_CONFIG_COUNT"] = "1"
            environment["GIT_CONFIG_KEY_0"] = "http.extraHeader"
            environment["GIT_CONFIG_VALUE_0"] =
                "Authorization: Basic \(credential)"
        case .ssh, .localFileForTests:
            break
        case .unsupported:
            throw LocalGitError.unsupportedRemoteProtocol
        }

        return environment
    }
}
