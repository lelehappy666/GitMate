import Foundation
import Observation

public protocol RepositoryContentLoading: Sendable {
    func repositoryContent(
        repository: Repository,
        account: GitHubAccount,
        token: String
    ) async throws -> RepositoryContent
}

extension WorkspaceContentService: RepositoryContentLoading {}

public enum RepositoryOverviewLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(message: String)
}

public struct RepositoryOverviewState: Equatable, Sendable {
    public var loadPhase: RepositoryOverviewLoadPhase
    public var repository: Repository
    public var localAvailability: LocalRepositoryAvailability
    public var localStatus: LocalRepositoryStatus?
    public var onlineSummary: RepositoryOnlineSummary?
    public var recentCommits: [GitCommit]
    public var readmePreview: READMEDocument?
    public var connectivity: WorkspaceConnectivity
    public var panelErrors: [WorkspacePanelError]
    public var lastInspectedAt: Date?
    public var localSizeInBytes: Int64

    public init(repository: Repository) {
        loadPhase = .idle
        self.repository = RepositoryPresentationSanitizer.repository(repository)
        localAvailability = .missing
        localStatus = nil
        onlineSummary = nil
        recentCommits = []
        readmePreview = nil
        connectivity = .online
        panelErrors = []
        lastInspectedAt = nil
        localSizeInBytes = 0
    }

    public var needsResync: Bool {
        localAvailability != .available
    }

    public var uncommittedChangeCount: Int {
        guard let localStatus else { return 0 }
        return localStatus.stagedCount
            + localStatus.unstagedCount
            + localStatus.untrackedCount
            + localStatus.conflictCount
    }

    public var quickRoutes: [WorkspaceRoute] {
        [
            .readme(repositoryID: repository.id),
            .filesAndCommits(repositoryID: repository.id),
            .commitGraph(repositoryID: repository.id)
        ]
    }
}

@MainActor
@Observable
public final class RepositoryOverviewViewModel {
    public private(set) var state: RepositoryOverviewState

    @ObservationIgnored
    private let repository: Repository

    @ObservationIgnored
    private let account: GitHubAccount

    @ObservationIgnored
    private let token: String

    @ObservationIgnored
    private let loader: any RepositoryContentLoading

    @ObservationIgnored
    private let parser: any READMEParsing

    @ObservationIgnored
    private var isLoading = false

    @ObservationIgnored
    private var hasLoadedSuccessfully = false

    public init(
        repository: Repository,
        account: GitHubAccount,
        token: String,
        loader: any RepositoryContentLoading,
        parser: any READMEParsing = READMEBlockParser()
    ) {
        self.repository = repository
        self.account = account
        self.token = token
        self.loader = loader
        self.parser = parser
        state = RepositoryOverviewState(repository: repository)
    }

    public func load() async {
        guard !isLoading, !hasLoadedSuccessfully else {
            return
        }

        let stateBeforeLoad = state
        isLoading = true
        state.loadPhase = .loading
        defer { isLoading = false }

        do {
            try Task.checkCancellation()
            let content = try await loader.repositoryContent(
                repository: repository,
                account: account,
                token: token
            )
            try Task.checkCancellation()
            state = try makeState(from: content)
            hasLoadedSuccessfully = true
        } catch is CancellationError {
            state = stateBeforeLoad
        } catch {
            var failedState = stateBeforeLoad
            failedState.loadPhase = .failed(
                message: "暂时无法加载仓库总览，请稍后重试。"
            )
            state = failedState
        }
    }

    private func makeState(
        from content: RepositoryContent
    ) throws -> RepositoryOverviewState {
        var nextState = RepositoryOverviewState(
            repository: content.repository
        )
        nextState.loadPhase = .loaded
        nextState.localAvailability = content.localRecord.availability
        nextState.localStatus = content.localStatus
        nextState.onlineSummary = content.onlineSummary
        nextState.recentCommits = content.recentCommits
        nextState.connectivity = content.connectivity
        nextState.panelErrors = content.panelErrors.map {
            WorkspacePanelError(
                panel: $0.panel,
                repositoryID: $0.repositoryID,
                message: sanitizedText($0.message)
            )
        }
        nextState.lastInspectedAt = content.localRecord.lastInspectedAt
        nextState.localSizeInBytes = content.localRecord.localSizeInBytes

        if let readme = content.readme {
            let document = try parser.parse(
                readme.markdown,
                baseURL: RepositoryPresentationSanitizer.remoteURL(
                    readme.downloadURL
                )
            )
            let sanitized = READMEPresentationSanitizer.sanitize(document)
            if !sanitized.blocks.isEmpty {
                nextState.readmePreview = sanitized
            }
        }
        return nextState
    }

    private func sanitizedText(_ value: String) -> String {
        guard !token.isEmpty else { return value }
        return value.replacingOccurrences(of: token, with: "••••")
    }
}

enum RepositoryPresentationSanitizer {
    static func repository(_ repository: Repository) -> Repository {
        Repository(
            id: repository.id,
            name: repository.name,
            fullName: repository.fullName,
            isPrivate: repository.isPrivate,
            defaultBranch: repository.defaultBranch,
            sizeInKilobytes: repository.sizeInKilobytes,
            cloneURL: remoteURL(repository.cloneURL)
                ?? URL(string: "https://invalid.invalid/")!,
            ownerAvatarURL: remoteURL(repository.ownerAvatarURL)
        )
    }

    static func remoteURL(_ url: URL?) -> URL? {
        guard let url,
              var components = URLComponents(
                  url: url,
                  resolvingAgainstBaseURL: false
              ),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false
        else {
            return nil
        }
        components.scheme = scheme
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
