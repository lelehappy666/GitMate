import Foundation

public final class WorkspaceContentService: @unchecked Sendable {
    private static let cacheTimeToLive: TimeInterval = 900
    private static let recentCommitLimit = 8

    private let catalog: LocalRepositoryCatalog
    private let localGit: any LocalGitReading
    private let github: any GitHubWorkspaceAPI
    private let cache: any WorkspaceCaching
    private let now: @Sendable () -> Date

    public init(
        catalog: LocalRepositoryCatalog,
        localGit: any LocalGitReading,
        github: any GitHubWorkspaceAPI,
        cache: any WorkspaceCaching,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.catalog = catalog
        self.localGit = localGit
        self.github = github
        self.cache = cache
        self.now = now
    }

    public func repositoryContent(
        repository: Repository,
        account: GitHubAccount,
        token: String
    ) async throws -> RepositoryContent {
        let accountID = String(account.id)
        let currentDate = now()
        var panelErrors: [WorkspacePanelError] = []
        let localRecord: LocalRepositoryRecord
        var catalogReadFailed = false
        do {
            localRecord = try catalog.record(for: repository)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            catalogReadFailed = true
            localRecord = LocalRepositoryRecord(
                repository: repository,
                localURL: catalog.localURL(for: repository),
                availability: .damaged,
                localSizeInBytes: 0,
                lastInspectedAt: currentDate
            )
            panelErrors.append(
                panelError(
                    panel: .localRepository,
                    repositoryID: repository.id,
                    message: "无法读取本地仓库。"
                )
            )
        }
        var connectivity = WorkspaceConnectivity.online
        var localStatus: LocalRepositoryStatus?
        var recentCommits: [GitCommit] = []

        let loadedSnapshot: WorkspaceCacheSnapshot?
        do {
            loadedSnapshot = try cache.load(accountID: accountID)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            loadedSnapshot = nil
            panelErrors.append(
                panelError(
                    panel: .onlineSummary,
                    repositoryID: repository.id,
                    message: "无法读取工作区缓存。"
                )
            )
        }
        let validSnapshot = validSnapshot(
            loadedSnapshot,
            accountID: accountID,
            now: currentDate
        )

        switch localRecord.availability {
        case .available:
            do {
                localStatus = try await localGit.status(
                    repositoryURL: localRecord.localURL
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                panelErrors.append(
                    panelError(
                        panel: .localStatus,
                        repositoryID: repository.id,
                        message: "无法读取本地仓库状态。"
                    )
                )
            }

            do {
                let page = try await localGit.commits(
                    repositoryURL: localRecord.localURL,
                    cursor: nil,
                    limit: Self.recentCommitLimit
                )
                recentCommits = Array(
                    page.commits.prefix(Self.recentCommitLimit)
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                panelErrors.append(
                    panelError(
                        panel: .recentCommits,
                        repositoryID: repository.id,
                        message: "无法读取本地最近提交。"
                    )
                )
            }
        case .missing:
            panelErrors.append(
                panelError(
                    panel: .localRepository,
                    repositoryID: repository.id,
                    message: "本地仓库不存在，请重新同步。"
                )
            )
        case .damaged:
            if !catalogReadFailed {
                panelErrors.append(
                    panelError(
                        panel: .localRepository,
                        repositoryID: repository.id,
                        message: "本地 Git 数据损坏，请重新同步。"
                    )
                )
            }
        }

        var onlineSummary = validSnapshot?.onlineSummaries[repository.id]
        do {
            let freshSummary = try await github.repositorySummary(
                repository: repository,
                token: token
            )
            onlineSummary = freshSummary
            do {
                try saveOnlineSummary(
                    freshSummary,
                    localRecord: localRecord,
                    accountID: accountID
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                panelErrors.append(
                    panelError(
                        panel: .onlineSummary,
                        repositoryID: repository.id,
                        message: "无法保存工作区缓存。"
                    )
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            connectivity = mergedConnectivity(
                connectivity,
                connectivityState(for: error)
            )
            panelErrors.append(
                panelError(
                    panel: .onlineSummary,
                    repositoryID: repository.id,
                    message: stableMessage(for: error, panel: .onlineSummary)
                )
            )
        }

        var readme: GitHubREADME?
        do {
            readme = try await github.readme(
                repository: repository,
                token: token
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            connectivity = mergedConnectivity(
                connectivity,
                connectivityState(for: error)
            )
            panelErrors.append(
                panelError(
                    panel: .readme,
                    repositoryID: repository.id,
                    message: stableMessage(for: error, panel: .readme)
                )
            )
        }

        return RepositoryContent(
            repository: repository,
            localRecord: localRecord,
            localStatus: localStatus,
            onlineSummary: onlineSummary,
            recentCommits: recentCommits,
            readme: readme,
            connectivity: connectivity,
            panelErrors: panelErrors
        )
    }

    public func dashboard(
        account: GitHubAccount,
        repositories: [Repository],
        token: String
    ) async throws -> WorkspaceDashboardContent {
        var contents: [RepositoryContent] = []
        var connectivity = WorkspaceConnectivity.online
        var panelErrors: [WorkspacePanelError] = []

        for repository in repositories {
            do {
                let content = try await repositoryContent(
                    repository: repository,
                    account: account,
                    token: token
                )
                contents.append(content)
                connectivity = mergedConnectivity(
                    connectivity,
                    content.connectivity
                )
                panelErrors.append(contentsOf: content.panelErrors)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                panelErrors.append(
                    panelError(
                        panel: .localRepository,
                        repositoryID: repository.id,
                        message: "无法读取本地仓库。"
                    )
                )
            }
        }

        return WorkspaceDashboardContent(
            account: account,
            repositories: contents,
            connectivity: connectivity,
            panelErrors: panelErrors
        )
    }

    private func validSnapshot(
        _ snapshot: WorkspaceCacheSnapshot?,
        accountID: String,
        now: Date
    ) -> WorkspaceCacheSnapshot? {
        guard let snapshot, snapshot.accountID == accountID else {
            return nil
        }
        let age = now.timeIntervalSince(snapshot.savedAt)
        guard (0...Self.cacheTimeToLive).contains(age) else {
            return nil
        }
        return snapshot
    }

    private func saveOnlineSummary(
        _ summary: RepositoryOnlineSummary,
        localRecord: LocalRepositoryRecord,
        accountID: String
    ) throws {
        try cache.update(accountID: accountID) { latestSnapshot in
            let savedAt = now()
            let previousSnapshot = validSnapshot(
                latestSnapshot,
                accountID: accountID,
                now: savedAt
            )
            var summaries = previousSnapshot?.onlineSummaries ?? [:]
            summaries[summary.repositoryID] = summary

            var records = previousSnapshot?.repositoryRecords ?? []
            records.removeAll {
                $0.repository.id == localRecord.repository.id
            }
            records.append(localRecord)

            return WorkspaceCacheSnapshot(
                accountID: accountID,
                repositoryRecords: records,
                onlineSummaries: summaries,
                savedAt: savedAt
            )
        }
    }

    private func connectivityState(for error: Error) -> WorkspaceConnectivity {
        if let apiError = error as? WorkspaceAPIError {
            switch apiError {
            case .authorizationRequired:
                return .authorizationRequired
            case let .rateLimited(resetAt):
                return .rateLimited(resetAt: resetAt)
            default:
                return .online
            }
        }
        if error is URLError
            || (error as NSError).domain == NSURLErrorDomain
        {
            return .offline
        }
        return .online
    }

    private func mergedConnectivity(
        _ lhs: WorkspaceConnectivity,
        _ rhs: WorkspaceConnectivity
    ) -> WorkspaceConnectivity {
        switch (lhs, rhs) {
        case (.authorizationRequired, _), (_, .authorizationRequired):
            return .authorizationRequired
        case let (.rateLimited(lhsResetAt), .rateLimited(rhsResetAt)):
            return .rateLimited(resetAt: max(lhsResetAt, rhsResetAt))
        case let (.rateLimited(resetAt), _):
            return .rateLimited(resetAt: resetAt)
        case let (_, .rateLimited(resetAt)):
            return .rateLimited(resetAt: resetAt)
        case (.offline, _), (_, .offline):
            return .offline
        case (.online, .online):
            return .online
        }
    }

    private func stableMessage(
        for error: Error,
        panel: WorkspacePanel
    ) -> String {
        if let apiError = error as? WorkspaceAPIError {
            switch apiError {
            case .authorizationRequired:
                return "GitHub 授权已失效，请重新授权。"
            case .rateLimited:
                return "GitHub API 已达到速率限制，请在恢复后重试。"
            default:
                break
            }
        }
        if error is URLError
            || (error as NSError).domain == NSURLErrorDomain
        {
            return "无法连接 GitHub，已显示可用的本地或缓存数据。"
        }
        switch panel {
        case .onlineSummary:
            return "无法加载 GitHub 在线摘要。"
        case .readme:
            return "无法在线读取 README，已保留其他仓库内容。"
        case .localRepository:
            return "无法读取本地仓库。"
        case .localStatus:
            return "无法读取本地仓库状态。"
        case .recentCommits:
            return "无法读取本地最近提交。"
        }
    }

    private func panelError(
        panel: WorkspacePanel,
        repositoryID: Int64?,
        message: String
    ) -> WorkspacePanelError {
        WorkspacePanelError(
            panel: panel,
            repositoryID: repositoryID,
            message: message
        )
    }
}
