import Foundation
import Observation

@MainActor
@Observable
public final class StashViewModel {
    public private(set) var entries: [GitStashEntry] = []
    public private(set) var selectedID: GitStashID?
    public private(set) var preview: GitDiffDocument?
    public private(set) var isLoading = false
    public private(set) var isMutating = false
    public private(set) var shouldShowConflicts = false
    public private(set) var error: LocalGitUserFacingError?
    public var message = ""
    public var includeUntracked = true

    private let repositoryURL: URL
    private let service: any GitStashServicing
    private var previewGeneration: UInt64 = 0

    public init(
        repositoryURL: URL,
        service: any GitStashServicing
    ) {
        self.repositoryURL = repositoryURL
        self.service = service
    }

    public func refresh() async {
        isLoading = true
        error = nil
        do {
            entries = try await service.list(repositoryURL: repositoryURL)
            if let selectedID,
               !entries.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
                preview = nil
            }
        } catch {
            present(error)
        }
        isLoading = false
    }

    public func select(_ id: GitStashID) async {
        previewGeneration &+= 1
        let generation = previewGeneration
        selectedID = id
        preview = nil
        error = nil
        do {
            let document = try await service.diff(
                repositoryURL: repositoryURL,
                id: id
            )
            guard generation == previewGeneration else {
                return
            }
            preview = document
        } catch {
            guard generation == previewGeneration else {
                return
            }
            present(error)
        }
    }

    public func create() async {
        isMutating = true
        error = nil
        do {
            try await service.create(
                repositoryURL: repositoryURL,
                message: message,
                includeUntracked: includeUntracked
            )
            message = ""
            await refresh()
        } catch {
            present(error)
        }
        isMutating = false
    }

    public func applySelected() async {
        guard let selectedID else {
            return
        }
        isMutating = true
        error = nil
        do {
            let result = try await service.apply(
                repositoryURL: repositoryURL,
                id: selectedID
            )
            shouldShowConflicts = result == .conflicted
            await refresh()
        } catch {
            present(error)
        }
        isMutating = false
    }

    public func popSelected(
        confirmation: RiskConfirmation
    ) async {
        guard let selectedID else {
            return
        }
        isMutating = true
        error = nil
        do {
            let result = try await service.pop(
                repositoryURL: repositoryURL,
                id: selectedID,
                confirmation: confirmation
            )
            shouldShowConflicts = result == .conflicted
            await refresh()
        } catch {
            present(error)
        }
        isMutating = false
    }

    public func dropSelected(
        confirmation: RiskConfirmation
    ) async {
        guard let selectedID else {
            return
        }
        isMutating = true
        error = nil
        do {
            try await service.drop(
                repositoryURL: repositoryURL,
                id: selectedID,
                confirmation: confirmation
            )
            await refresh()
        } catch {
            present(error)
        }
        isMutating = false
    }

    public func consumeConflictRoute() {
        shouldShowConflicts = false
    }

    private func present(_ error: Error) {
        self.error = LocalGitUserFacingError(
            message: GitOutputRedactor.redact(error.localizedDescription),
            recoverySuggestion: "请检查工作区状态后重试。"
        )
    }
}
