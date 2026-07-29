import Foundation
import GitMateCore

enum WorkspacePreviewState: String {
    case normal
    case offline
    case error
}

@MainActor
enum WorkspacePreviewFactory {
    static func make(
        page: Int,
        state: WorkspacePreviewState
    ) -> WorkspaceRootView {
        let credentialStore = InMemoryCredentialStore()
        try? credentialStore.save(
            token: "preview-token",
            accountID: account.id
        )
        let root = FileManager.default.temporaryDirectory.appending(
            path: "GitMatePreviewRepositories",
            directoryHint: .isDirectory
        )
        let catalog = LocalRepositoryCatalog(
            rootDirectory: root,
            fileSystem: PreviewRepositoryFileSystem()
        )
        let cache = PreviewWorkspaceCache()
        let coverCache = PreviewRepositoryCoverCache()
        let runtime = WorkspaceRuntimeDependencies(
            syncDestination: root,
            cacheDirectory: FileManager.default.temporaryDirectory,
            credentialStore: credentialStore,
            catalog: catalog,
            localGit: PreviewLocalGitReader(),
            workspaceAPI: PreviewGitHubWorkspaceAPI(state: state),
            cache: cache,
            coverCache: coverCache,
            coverLoader: PreviewRepositoryCoverLoader()
        )
        return WorkspaceRootView(
            session: WorkspaceSession(
                account: account,
                repositories: repositories,
                route: route(for: page)
            ),
            preferences: [
                RepositorySyncPreference(
                    repositoryID: repositories[0].id,
                    mode: .automatic
                ),
                RepositorySyncPreference(
                    repositoryID: repositories[1].id,
                    mode: .manual
                ),
                RepositorySyncPreference(
                    repositoryID: repositories[2].id,
                    mode: .never
                )
            ],
            runtime: runtime,
            onResync: {
                NotificationCenter.default.post(
                    name: .workspacePreviewRequestedResync,
                    object: nil
                )
            },
            onReauthorize: { _ in
                NotificationCenter.default.post(
                    name: .workspacePreviewRequestedReauthorization,
                    object: nil
                )
            }
        )
    }

    private static func route(for page: Int) -> WorkspaceRoute {
        switch page {
        case 11:
            .repositories
        case 12:
            .repositoryOverview(repositoryID: repositories[0].id)
        case 13:
            .readme(repositoryID: repositories[0].id)
        case 14:
            .filesAndCommits(repositoryID: repositories[0].id)
        case 15:
            .commitGraph(repositoryID: repositories[0].id)
        default:
            .dashboard
        }
    }

    private static let account = GitHubAccount(
        id: "github.com:9919",
        login: "lele",
        name: "Lele",
        avatarURL: URL(
            string: "https://avatars.githubusercontent.com/u/9919?v=4"
        ),
        serverURL: URL(string: "https://github.com")!,
        kind: .githubDotCom,
        scopes: ["repo", "read:user", "workflow"]
    )

    private static let repositories = [
        Repository(
            id: 101,
            name: "mac-client",
            fullName: "GitMate/mac-client",
            isPrivate: true,
            defaultBranch: "main",
            sizeInKilobytes: 2_457_600,
            cloneURL: URL(
                string: "https://github.com/GitMate/mac-client.git"
            )!,
            ownerAvatarURL: account.avatarURL
        ),
        Repository(
            id: 102,
            name: "design-system",
            fullName: "dafone/design-system",
            isPrivate: false,
            defaultBranch: "develop",
            sizeInKilobytes: 684_000,
            cloneURL: URL(
                string: "https://github.com/dafone/design-system.git"
            )!,
            ownerAvatarURL: URL(
                string: "https://avatars.githubusercontent.com/u/583231?v=4"
            )
        ),
        Repository(
            id: 103,
            name: "asset-console",
            fullName: "studio/asset-console",
            isPrivate: false,
            defaultBranch: "main",
            sizeInKilobytes: 1_126_400,
            cloneURL: URL(
                string: "https://github.com/studio/asset-console.git"
            )!,
            ownerAvatarURL: URL(
                string: "https://avatars.githubusercontent.com/u/69631?v=4"
            )
        )
    ]
}

private extension Notification.Name {
    static let workspacePreviewRequestedResync = Notification.Name(
        "GitMate.WorkspacePreview.RequestedResync"
    )
    static let workspacePreviewRequestedReauthorization = Notification.Name(
        "GitMate.WorkspacePreview.RequestedReauthorization"
    )
}

private struct PreviewRepositoryFileSystem: RepositoryFileSystem {
    func itemExists(at url: URL) -> Bool {
        !url.path.contains("asset-console")
    }

    func recursiveByteCount(at url: URL) throws -> Int64 {
        url.path.contains("design-system")
            ? 684_000 * 1_024
            : 2_457_600 * 1_024
    }
}

private final class PreviewWorkspaceCache: WorkspaceCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [String: WorkspaceCacheSnapshot] = [:]

    func load(accountID: String) throws -> WorkspaceCacheSnapshot? {
        lock.withLock { snapshots[accountID] }
    }

    func save(_ snapshot: WorkspaceCacheSnapshot) throws {
        lock.withLock { snapshots[snapshot.accountID] = snapshot }
    }

    func clear(accountID: String) throws {
        _ = lock.withLock { snapshots.removeValue(forKey: accountID) }
    }

    func update(
        accountID: String,
        _ transform: @Sendable (
            WorkspaceCacheSnapshot?
        ) throws -> WorkspaceCacheSnapshot
    ) throws {
        try lock.withLock {
            snapshots[accountID] = try transform(snapshots[accountID])
        }
    }
}

private final class PreviewRepositoryCoverCache:
    RepositoryCoverCaching,
    @unchecked Sendable
{
    func load(
        repositoryID: Int64,
        sourceURL: URL
    ) throws -> RepositoryCoverCacheEntry? {
        nil
    }

    func save(
        data: Data,
        metadata: RepositoryCoverCacheMetadata,
        repositoryID: Int64,
        sourceURL: URL
    ) throws {}

    func clear(repositoryID: Int64) throws {}
}

private struct PreviewRepositoryCoverLoader: RepositoryCoverLoading {
    func load(
        repositoryID: Int64,
        sourceURL: URL
    ) async throws -> RepositoryCoverCacheEntry {
        let data = Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
        return RepositoryCoverCacheEntry(
            data: data,
            metadata: RepositoryCoverCacheMetadata(
                contentType: "image/png",
                storedAt: Date(timeIntervalSince1970: 1_753_747_200),
                pixelWidth: 640,
                pixelHeight: 360
            )
        )
    }
}

private struct PreviewGitHubWorkspaceAPI: GitHubWorkspaceAPI {
    let state: WorkspacePreviewState

    func repositorySummary(
        repository: Repository,
        token: String
    ) async throws -> RepositoryOnlineSummary {
        try onlineCheck(repositoryID: repository.id)
        let index = max(Int(repository.id - 101), 0)
        return RepositoryOnlineSummary(
            repositoryID: repository.id,
            primaryLanguage: ["Swift", "TypeScript", "Vue"][index],
            openIssueCount: [8, 5, 3][index],
            openPullRequestCount: [7, 2, 1][index],
            failedWorkflowCount: [2, 0, 1][index],
            remoteUpdatedAt: Date(
                timeIntervalSince1970: 1_753_747_200 - Double(index * 3_600)
            )
        )
    }

    func readme(
        repository: Repository,
        token: String
    ) async throws -> GitHubREADME {
        try onlineCheck(repositoryID: repository.id)
        let markdown: String
        if repository.id == 101 {
            markdown = """
            ![GitMate 封面](https://raw.githubusercontent.com/github/explore/main/topics/swift/swift.png)

            # GitMate macOS 客户端

            原生、只读优先的 GitHub 桌面工作区。

            ## 当前能力

            - 汇总本地仓库状态
            - 安全渲染 README
            - 浏览文件、提交与合并关系

            ```swift
            let workspace = GitMateWorkspace()
            workspace.open()
            ```

            | 模块 | 状态 |
            | --- | --- |
            | 本地 Git | 可用 |
            | GitHub 摘要 | 已连接 |
            """
        } else {
            markdown = "# \(repository.name)\n\n仓库说明与开发约定。"
        }
        return GitHubREADME(
            repositoryID: repository.id,
            path: "README.md",
            markdown: markdown,
            downloadURL: URL(
                string:
                    "https://raw.githubusercontent.com/\(repository.fullName)/\(repository.defaultBranch)/README.md"
            )
        )
    }

    private func onlineCheck(repositoryID: Int64) throws {
        switch state {
        case .normal:
            return
        case .offline:
            throw URLError(.notConnectedToInternet)
        case .error where repositoryID == 102:
            throw WorkspaceAPIError.httpStatus(500, nil)
        case .error:
            return
        }
    }
}

private struct PreviewLocalGitReader: LocalGitReading {
    func status(repositoryURL: URL) async throws -> LocalRepositoryStatus {
        LocalRepositoryStatus(
            branch: repositoryURL.path.contains("design-system")
                ? "develop"
                : "main",
            upstream: "origin/main",
            ahead: 1,
            behind: 0,
            stagedCount: 1,
            unstagedCount: 2,
            untrackedCount: 1,
            conflictCount: 0
        )
    }

    func tree(
        repositoryURL: URL,
        revision: String,
        path: String
    ) async throws -> [GitFileEntry] {
        if path == "Sources" {
            return [
                GitFileEntry(
                    path: "Sources/App.swift",
                    name: "App.swift",
                    kind: .file,
                    objectID: "tree-app",
                    byteCount: 2_840
                ),
                GitFileEntry(
                    path: "Sources/WorkspaceView.swift",
                    name: "WorkspaceView.swift",
                    kind: .file,
                    objectID: "tree-workspace",
                    byteCount: 8_420
                )
            ]
        }
        return [
            GitFileEntry(
                path: "Sources",
                name: "Sources",
                kind: .directory,
                objectID: "tree-sources",
                byteCount: nil
            ),
            GitFileEntry(
                path: "README.md",
                name: "README.md",
                kind: .file,
                objectID: "tree-readme",
                byteCount: 4_210
            ),
            GitFileEntry(
                path: "Package.swift",
                name: "Package.swift",
                kind: .file,
                objectID: "tree-package",
                byteCount: 1_280
            )
        ]
    }

    func file(
        repositoryURL: URL,
        revision: String,
        path: String
    ) async throws -> GitFileContent {
        let text = path.hasSuffix(".swift")
            ? "import SwiftUI\n\n@main\nstruct GitMateApp: App {\n    var body: some Scene { WindowGroup { WorkspaceView() } }\n}\n"
            : "# GitMate\n\n原生 macOS GitHub 工作区。"
        return GitFileContent(
            path: path,
            data: Data(text.utf8),
            text: text,
            byteCount: text.utf8.count,
            isBinary: false
        )
    }

    func commits(
        repositoryURL: URL,
        cursor: String?,
        limit: Int
    ) async throws -> GitCommitPage {
        GitCommitPage(
            commits: Array(Self.commits.prefix(limit)),
            nextCursor: nil
        )
    }

    func commit(
        repositoryURL: URL,
        hash: String
    ) async throws -> GitCommitDetail {
        let commit = Self.commits.first { $0.fullHash == hash }
            ?? Self.commits[0]
        return GitCommitDetail(
            commit: commit,
            message: "\(commit.subject)\n\n保持本地索引恢复过程幂等，并补充回归测试。",
            signatureStatus: .verified,
            signer: "Lele"
        )
    }

    func diff(
        repositoryURL: URL,
        hash: String
    ) async throws -> GitDiff {
        GitDiff(
            commitHash: hash,
            files: [
                GitChangedFile(
                    path: "Sources/SyncRecovery.swift",
                    additions: 38,
                    deletions: 8,
                    isBinary: false
                ),
                GitChangedFile(
                    path: "Tests/SyncRecoveryTests.swift",
                    additions: 44,
                    deletions: 3,
                    isBinary: false
                )
            ],
            patch: """
            diff --git a/Sources/SyncRecovery.swift b/Sources/SyncRecovery.swift
            +guard request.id == activeRequestID else { return }
            +try Task.checkCancellation()
            -index.append(contentsOf: files)
            +index.merge(files, uniquingKeysWith: { _, latest in latest })
            """,
            additions: 82,
            deletions: 11
        )
    }

    func graph(
        repositoryURL: URL,
        cursor: String?,
        limit: Int
    ) async throws -> CommitGraphPage {
        CommitGraphPage(
            commits: Array(Self.commits.prefix(limit)),
            nextCursor: nil
        )
    }

    private static let commits: [GitCommit] = {
        let base = "0d4ab120d4ab120d4ab120d4ab120d4ab120d4ab"
        let main = "a81c32fa81c32fa81c32fa81c32fa81c32fa81c"
        let feature = "742fd81742fd81742fd81742fd81742fd81742fd8"
        let merge = "8e1d04a8e1d04a8e1d04a8e1d04a8e1d04a8e"
        return [
            GitCommit(
                shortHash: "8e1d04a",
                fullHash: merge,
                subject: "merge: 合并索引恢复优化",
                authorName: "Lele",
                authorEmail: "lele@example.invalid",
                authoredAt: Date(timeIntervalSince1970: 1_753_747_080),
                parentHashes: [main, feature],
                decorations: ["HEAD -> main", "origin/main"]
            ),
            GitCommit(
                shortHash: "a81c32f",
                fullHash: main,
                subject: "fix: 修复网络恢复后的索引重复",
                authorName: "Lele",
                authorEmail: "lele@example.invalid",
                authoredAt: Date(timeIntervalSince1970: 1_753_746_600),
                parentHashes: [base],
                decorations: ["main"]
            ),
            GitCommit(
                shortHash: "742fd81",
                fullHash: feature,
                subject: "perf: 优化大型仓库的增量扫描",
                authorName: "Mingxu",
                authorEmail: "mingxu@example.invalid",
                authoredAt: Date(timeIntervalSince1970: 1_753_744_800),
                parentHashes: [base],
                decorations: ["feature/sync"]
            ),
            GitCommit(
                shortHash: "0d4ab12",
                fullHash: base,
                subject: "docs: 更新企业服务器连接说明",
                authorName: "Yuhan",
                authorEmail: "yuhan@example.invalid",
                authoredAt: Date(timeIntervalSince1970: 1_753_740_000),
                parentHashes: [],
                decorations: ["release/2.4"]
            )
        ]
    }()
}
