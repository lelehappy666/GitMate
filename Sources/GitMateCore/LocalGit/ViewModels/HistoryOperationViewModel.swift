import Foundation
import Observation

public enum HistoryOperationMode: CaseIterable, Sendable {
    case merge
    case rebase
    case cherryPick
}

@MainActor
@Observable
public final class HistoryOperationViewModel {
    public var mode: HistoryOperationMode = .merge
    public var source = ""
    public private(set) var preflight: GitOperationPreflight?
    public private(set) var operationState = GitRepositoryOperationState.none
    public private(set) var isLoading = false
    public private(set) var shouldShowConflicts = false
    public private(set) var error: LocalGitUserFacingError?

    private let repositoryURL: URL
    private let service: any GitHistoryOperationServicing

    public init(
        repositoryURL: URL,
        service: any GitHistoryOperationServicing
    ) {
        self.repositoryURL = repositoryURL
        self.service = service
    }

    public func refreshState() async {
        do {
            operationState = try await service.state(
                repositoryURL: repositoryURL
            )
        } catch {
            present(error)
        }
    }

    public func runPreflight() async {
        guard let request = request else {
            return
        }
        isLoading = true
        error = nil
        do {
            preflight = try await service.preflight(
                repositoryURL: repositoryURL,
                request: request
            )
        } catch {
            present(error)
        }
        isLoading = false
    }

    public func start() async {
        guard let request,
              let confirmation = preflight?.confirmation
        else {
            return
        }
        isLoading = true
        error = nil
        do {
            let result = try await service.start(
                repositoryURL: repositoryURL,
                request: request,
                confirmation: confirmation
            )
            shouldShowConflicts = result == .conflicted
            await refreshState()
        } catch {
            present(error)
        }
        isLoading = false
    }

    public func continueOperation() async {
        isLoading = true
        do {
            let result = try await service.continue(
                repositoryURL: repositoryURL
            )
            shouldShowConflicts = result == .conflicted
            await refreshState()
        } catch {
            present(error)
        }
        isLoading = false
    }

    public func abort() async {
        isLoading = true
        do {
            try await service.abort(repositoryURL: repositoryURL)
            preflight = nil
            await refreshState()
        } catch {
            present(error)
        }
        isLoading = false
    }

    public func consumeConflictRoute() {
        shouldShowConflicts = false
    }

    private var request: GitHistoryOperationRequest? {
        let value = source.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !value.isEmpty else {
            return nil
        }
        switch mode {
        case .merge:
            return .merge(source: value)
        case .rebase:
            return .rebase(onto: value)
        case .cherryPick:
            let commits = value
                .split(whereSeparator: { $0.isWhitespace || $0 == "," })
                .map(String.init)
            return commits.isEmpty ? nil : .cherryPick(commits: commits)
        }
    }

    private func present(_ error: Error) {
        self.error = LocalGitUserFacingError(
            message: GitOutputRedactor.redact(error.localizedDescription),
            recoverySuggestion: "刷新仓库状态后重试。"
        )
    }
}
