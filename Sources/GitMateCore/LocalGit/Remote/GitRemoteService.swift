import CryptoKit
import Foundation

public protocol GitRemoteServicing: Sendable {
    func list(repositoryURL: URL) async throws -> [GitRemote]

    func add(
        repositoryURL: URL,
        name: String,
        fetchURL: String,
        pushURL: String?
    ) async throws

    func update(
        repositoryURL: URL,
        originalName: String,
        change: GitRemoteChange
    ) async throws

    func removalImpact(
        repositoryURL: URL,
        remote: String
    ) async throws -> RemoteRemovalImpact

    func remove(
        repositoryURL: URL,
        remote: String,
        confirmation: RiskConfirmation
    ) async throws

    func testConnection(
        repositoryURL: URL,
        remote: String,
        context: GitCredentialContext
    ) async throws -> RemoteConnectionResult
}

public struct GitRemoteService: GitRemoteServicing, Sendable {
    private let executor: any GitCommandExecuting
    private let coordinator: RepositoryOperationCoordinator
    private let transportPolicy: GitRemoteTransportPolicy
    private let credentialEnvironment: GitCredentialEnvironment
    private let commandBuilder: GitCommandBuilder

    public init(
        executor: any GitCommandExecuting = ProcessGitCommandExecutor(),
        coordinator: RepositoryOperationCoordinator =
            RepositoryOperationCoordinator(),
        transportPolicy: GitRemoteTransportPolicy = .production,
        credentialEnvironment: GitCredentialEnvironment? = nil,
        commandBuilder: GitCommandBuilder = GitCommandBuilder()
    ) {
        self.executor = executor
        self.coordinator = coordinator
        self.transportPolicy = transportPolicy
        self.credentialEnvironment = credentialEnvironment
            ?? GitCredentialEnvironment(
                credentialStore: InMemoryCredentialStore(),
                transportPolicy: transportPolicy
            )
        self.commandBuilder = commandBuilder
    }

    public func list(
        repositoryURL: URL
    ) async throws -> [GitRemote] {
        let names = try await remoteNames(repositoryURL: repositoryURL)
        let tracking = try await trackingBranches(
            repositoryURL: repositoryURL
        )
        var remotes: [GitRemote] = []
        remotes.reserveCapacity(names.count)

        for name in names {
            let fetchURL = try await rawURL(
                repositoryURL: repositoryURL,
                remote: name,
                push: false
            )
            let pushURL = try await rawURL(
                repositoryURL: repositoryURL,
                remote: name,
                push: true
            )
            remotes.append(
                GitRemote(
                    name: name,
                    fetchURL: Self.sanitizedURL(fetchURL),
                    pushURL: Self.sanitizedURL(pushURL),
                    fetchProtocol: try transportPolicy.validate(
                        remoteURLString: fetchURL
                    ),
                    pushProtocol: try transportPolicy.validate(
                        remoteURLString: pushURL
                    ),
                    trackingBranches: tracking[name, default: []].sorted()
                )
            )
        }
        return remotes
    }

    public func add(
        repositoryURL: URL,
        name: String,
        fetchURL: String,
        pushURL: String?
    ) async throws {
        try validate(name: name)
        _ = try transportPolicy.validate(remoteURLString: fetchURL)
        if let pushURL {
            _ = try transportPolicy.validate(remoteURLString: pushURL)
        }

        let addCommand = try commandBuilder.addRemote(
            repositoryURL: repositoryURL,
            name: name,
            url: fetchURL
        )
        try await runWrite(
            repositoryURL: repositoryURL,
            commands: [addCommand]
        )
        if let pushURL, pushURL != fetchURL {
            let pushCommand = try commandBuilder.setRemoteURL(
                repositoryURL: repositoryURL,
                name: name,
                url: pushURL,
                push: true
            )
            do {
                try await runWrite(
                    repositoryURL: repositoryURL,
                    commands: [pushCommand]
                )
            } catch {
                let rollback = try commandBuilder.removeRemote(
                    repositoryURL: repositoryURL,
                    name: name
                )
                try? await runWrite(
                    repositoryURL: repositoryURL,
                    commands: [rollback]
                )
                throw error
            }
        }
    }

    public func update(
        repositoryURL: URL,
        originalName: String,
        change: GitRemoteChange
    ) async throws {
        try validate(name: originalName)
        try validate(name: change.name)
        _ = try transportPolicy.validate(
            remoteURLString: change.fetchURL
        )
        if let pushURL = change.pushURL {
            _ = try transportPolicy.validate(remoteURLString: pushURL)
        }

        var commands: [GitCommand] = []
        if originalName != change.name {
            commands.append(
                try commandBuilder.renameRemote(
                    repositoryURL: repositoryURL,
                    originalName: originalName,
                    newName: change.name
                )
            )
        }
        commands.append(
            try commandBuilder.setRemoteURL(
                repositoryURL: repositoryURL,
                name: change.name,
                url: change.fetchURL,
                push: false
            )
        )
        if let pushURL = change.pushURL {
            commands.append(
                try commandBuilder.setRemoteURL(
                    repositoryURL: repositoryURL,
                    name: change.name,
                    url: pushURL,
                    push: true
                )
            )
        }
        try await runWrite(
            repositoryURL: repositoryURL,
            commands: commands
        )
        if change.pushURL == nil {
            let command = try commandBuilder.unsetRemotePushURL(
                repositoryURL: repositoryURL,
                name: change.name
            )
            do {
                try await runWrite(
                    repositoryURL: repositoryURL,
                    commands: [command]
                )
            } catch let GitCommandError.exitStatus(status, _)
                where status == 5 {
            }
        }
    }

    public func removalImpact(
        repositoryURL: URL,
        remote: String
    ) async throws -> RemoteRemovalImpact {
        try validate(name: remote)
        let names = try await remoteNames(repositoryURL: repositoryURL)
        guard names.contains(remote) else {
            throw LocalGitError.invalidReference
        }
        let branches = try await trackingBranches(
            repositoryURL: repositoryURL
        )[remote, default: []].sorted()
        return RemoteRemovalImpact(
            remote: remote,
            trackingBranches: branches,
            confirmation: RiskConfirmation(
                repositoryID: GitRepositoryIdentifier.make(
                    repositoryURL: repositoryURL
                ),
                impactFingerprint: Self.removalFingerprint(
                    remote: remote,
                    branches: branches
                )
            )
        )
    }

    public func remove(
        repositoryURL: URL,
        remote: String,
        confirmation: RiskConfirmation
    ) async throws {
        let latest = try await removalImpact(
            repositoryURL: repositoryURL,
            remote: remote
        )
        let age = Date().timeIntervalSince(confirmation.createdAt)
        guard confirmation.repositoryID
                == latest.confirmation.repositoryID,
              confirmation.impactFingerprint
                == latest.confirmation.impactFingerprint,
              age >= 0,
              age <= 300
        else {
            throw LocalGitError.confirmationExpired
        }
        let command = try commandBuilder.removeRemote(
            repositoryURL: repositoryURL,
            name: remote
        )
        try await runWrite(
            repositoryURL: repositoryURL,
            commands: [command]
        )
    }

    public func testConnection(
        repositoryURL: URL,
        remote: String,
        context: GitCredentialContext
    ) async throws -> RemoteConnectionResult {
        try validate(name: remote)
        let remoteURL = try await rawURL(
            repositoryURL: repositoryURL,
            remote: remote,
            push: false
        )
        let protocolValue = try transportPolicy.validate(
            remoteURLString: remoteURL
        )
        if protocolValue == .ssh,
           ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] == nil {
            return .sshAgentUnavailable
        }

        let environment: [String: String]
        do {
            environment = try credentialEnvironment.environment(
                remoteURLString: remoteURL,
                context: context
            )
        } catch LocalGitError.missingCredential {
            return .authenticationRequired
        }
        let command = try commandBuilder.lsRemoteHeads(
            repositoryURL: repositoryURL,
            remote: remote,
            environment: environment
        )
        do {
            let output = try await executor.collect(command)
            let count = output.stdoutData.split(separator: 0x0A).count
            return .connected(referenceCount: count)
        } catch let GitCommandError.exitStatus(_, message) {
            let value = message.lowercased()
            if value.contains("authentication")
                || value.contains("could not read username")
                || value.contains("permission denied") {
                return .authenticationRequired
            }
            if value.contains("ssh_auth_sock")
                || value.contains("agent") {
                return .sshAgentUnavailable
            }
            throw GitCommandError.exitStatus(
                1,
                GitOutputRedactor.redact(message)
            )
        }
    }

    private func remoteNames(
        repositoryURL: URL
    ) async throws -> [String] {
        let command = try commandBuilder.remoteNames(
            repositoryURL: repositoryURL
        )
        let output = try await executor.collect(command)
        return String(decoding: output.stdoutData, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter(GitInputValidator.isSafeRemoteName)
            .sorted()
    }

    private func rawURL(
        repositoryURL: URL,
        remote: String,
        push: Bool
    ) async throws -> String {
        let command = try commandBuilder.remoteURL(
            repositoryURL: repositoryURL,
            name: remote,
            push: push
        )
        let output = try await executor.collect(command)
        return String(decoding: output.stdoutData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func trackingBranches(
        repositoryURL: URL
    ) async throws -> [String: [String]] {
        let command = try commandBuilder.branchTrackingRemotes(
            repositoryURL: repositoryURL
        )
        let output = try await executor.collect(command)
        var result: [String: [String]] = [:]
        for line in output.stdoutData.split(separator: 0x0A) {
            let fields = line.split(
                separator: 0,
                omittingEmptySubsequences: false
            )
            guard fields.count >= 2 else {
                continue
            }
            let branch = String(decoding: fields[0], as: UTF8.self)
            let remote = String(decoding: fields[1], as: UTF8.self)
            guard GitInputValidator.isSafeRemoteName(remote),
                  GitInputValidator.isSafeReference(branch)
            else {
                continue
            }
            result[remote, default: []].append(branch)
        }
        return result
    }

    private func runWrite(
        repositoryURL: URL,
        commands: [GitCommand]
    ) async throws {
        let executor = executor
        try await coordinator.run(
            repositoryURL: repositoryURL,
            kind: .remoteConfiguration
        ) {
            for command in commands {
                _ = try await executor.collect(command)
            }
        }
    }

    private func validate(name: String) throws {
        guard GitInputValidator.isSafeRemoteName(name) else {
            throw LocalGitError.invalidReference
        }
    }

    private static func sanitizedURL(_ value: String) -> String {
        if var components = URLComponents(string: value),
           components.scheme != nil {
            components.user = nil
            components.password = nil
            return components.string ?? value
        }
        if let at = value.firstIndex(of: "@"),
           value[value.index(after: at)...].contains(":") {
            return String(value[value.index(after: at)...])
        }
        return value
    }

    private static func removalFingerprint(
        remote: String,
        branches: [String]
    ) -> String {
        SHA256.hash(
            data: Data(
                "\(remote)\0\(branches.sorted().joined(separator: "\0"))"
                    .utf8
            )
        ).map {
            String(format: "%02x", $0)
        }.joined()
    }
}
