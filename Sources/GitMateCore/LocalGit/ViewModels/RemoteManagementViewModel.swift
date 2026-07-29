import Foundation
import Observation

@MainActor
@Observable
public final class RemoteManagementViewModel {
    public private(set) var remotes: [GitRemote] = []
    public private(set) var selectedName: String?
    public private(set) var connectionResult: RemoteConnectionResult?
    public private(set) var isLoading = false
    public private(set) var error: LocalGitUserFacingError?
    public var name = ""
    public var fetchURL = ""
    public var pushURL = ""

    private let repositoryURL: URL
    private let service: any GitRemoteServicing

    public init(
        repositoryURL: URL,
        service: any GitRemoteServicing
    ) {
        self.repositoryURL = repositoryURL
        self.service = service
    }

    public func refresh() async {
        isLoading = true
        do {
            remotes = try await service.list(repositoryURL: repositoryURL)
        } catch {
            present(error)
        }
        isLoading = false
    }

    public func select(_ remote: GitRemote) {
        selectedName = remote.name
        name = remote.name
        fetchURL = remote.fetchURL
        pushURL = remote.pushURL == remote.fetchURL ? "" : remote.pushURL
        connectionResult = nil
    }

    public func save() async {
        isLoading = true
        do {
            if let selectedName {
                try await service.update(
                    repositoryURL: repositoryURL,
                    originalName: selectedName,
                    change: GitRemoteChange(
                        name: name,
                        fetchURL: fetchURL,
                        pushURL: pushURL.isEmpty ? nil : pushURL
                    )
                )
            } else {
                try await service.add(
                    repositoryURL: repositoryURL,
                    name: name,
                    fetchURL: fetchURL,
                    pushURL: pushURL.isEmpty ? nil : pushURL
                )
            }
            clearEditor()
            await refresh()
        } catch {
            present(error)
        }
        isLoading = false
    }

    public func testConnection(
        context: GitCredentialContext
    ) async {
        guard let selectedName else {
            return
        }
        isLoading = true
        do {
            connectionResult = try await service.testConnection(
                repositoryURL: repositoryURL,
                remote: selectedName,
                context: context
            )
        } catch {
            present(error)
        }
        isLoading = false
    }

    public func remove(
        impact: RemoteRemovalImpact
    ) async {
        isLoading = true
        do {
            try await service.remove(
                repositoryURL: repositoryURL,
                remote: impact.remote,
                confirmation: impact.confirmation
            )
            clearEditor()
            await refresh()
        } catch {
            present(error)
        }
        isLoading = false
    }

    public func clearEditor() {
        selectedName = nil
        name = ""
        fetchURL = ""
        pushURL = ""
        connectionResult = nil
    }

    private func present(_ error: Error) {
        self.error = LocalGitUserFacingError(
            message: GitOutputRedactor.redact(error.localizedDescription),
            recoverySuggestion: "检查远程地址和认证状态后重试。"
        )
    }
}
