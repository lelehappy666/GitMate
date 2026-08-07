import Foundation
import GitMateCore

@MainActor
enum LocalGitPreviewFactory {
    static func make(page: Int) -> LocalGitRootView {
        let services = PreviewLocalGitServices()
        let remoteService = PreviewRemoteService()
        let dependencies = LocalGitViewDependencies(
            reader: services,
            watcher: PreviewRepositoryWatcher(),
            diff: services,
            commit: services,
            stash: services,
            history: services,
            conflict: services,
            remote: remoteService,
            transfer: services
        )
        return LocalGitRootView(
            repositoryURL: URL(
                fileURLWithPath: "/GitMate-Preview/mac-client"
            ),
            credentialContext: GitCredentialContext(
                accountID: "preview"
            ),
            initialRoute: LocalGitRoute(pageNumber: page) ?? .workingTree,
            isPreview: true,
            dependencies: dependencies
        )
    }
}

private struct PreviewRepositoryWatcher: RepositoryFileSystemWatching {
    func events(repositoryURL: URL) -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

private struct PreviewLocalGitServices:
    WorkingTreeReading,
    GitDiffServicing,
    GitCommitServicing,
    GitStashServicing,
    GitHistoryOperationServicing,
    GitConflictServicing,
    GitTransferServicing
{
    func trackedSnapshot(
        repositoryURL: URL,
        generation: UInt64
    ) async throws -> WorkingTreeSnapshot {
        WorkingTreeSnapshot(
            branch: LocalBranchStatus(
                name: "main",
                upstream: "origin/main",
                ahead: 2,
                behind: 1
            ),
            files: [
                WorkingTreeFile(
                    path: "Sources/SyncCoordinator.swift",
                    category: .staged,
                    indexStatus: "M"
                ),
                WorkingTreeFile(
                    path: "Sources/GitClient.swift",
                    category: .unstaged,
                    workTreeStatus: "M"
                ),
                WorkingTreeFile(
                    path: "Tests/ConflictTests.swift",
                    category: .conflicted,
                    indexStatus: "U",
                    workTreeStatus: "U"
                )
            ],
            untrackedScan: .loading(received: 0),
            generation: generation
        )
    }

    func untrackedBatches(
        repositoryURL: URL,
        generation: UInt64,
        batchSize: Int
    ) -> AsyncThrowingStream<WorkingTreeBatch, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                WorkingTreeBatch(
                    generation: generation,
                    files: [
                        WorkingTreeFile(
                            path: "docs/本地Git说明.md",
                            category: .untracked
                        )
                    ],
                    isLast: true
                )
            )
            continuation.finish()
        }
    }

    func diff(
        repositoryURL: URL,
        path: String,
        source: GitDiffSource,
        options: GitDiffOptions
    ) async throws -> GitDiffDocument {
        Self.previewDiff(path: path)
    }

    func stage(repositoryURL: URL, paths: [String]) async throws {}
    func unstage(repositoryURL: URL, paths: [String]) async throws {}
    func stageHunk(repositoryURL: URL, hunk: GitDiffHunk) async throws {}
    func unstageHunk(repositoryURL: URL, hunk: GitDiffHunk) async throws {}

    func discardHunk(
        repositoryURL: URL,
        hunk: GitDiffHunk,
        confirmation: RiskConfirmation
    ) async throws {}

    func discardFiles(
        repositoryURL: URL,
        paths: [String],
        confirmation: RiskConfirmation
    ) async throws {}

    func identity(repositoryURL: URL) async throws -> CommitIdentity {
        CommitIdentity(
            name: "lele",
            email: "lele@example.com"
        )
    }

    func signingState(
        repositoryURL: URL
    ) async throws -> CommitSigningState {
        .configured(format: "ssh")
    }

    func commit(
        repositoryURL: URL,
        message: CommitMessage,
        signing: CommitSigningPolicy
    ) async throws -> CommitResult {
        CommitResult(
            oid: String(repeating: "a", count: 40),
            shortOID: "a81c32f",
            subject: message.title
        )
    }

    func list(repositoryURL: URL) async throws -> [GitStashEntry] {
        guard let first = GitStashID(rawValue: "stash@{0}"),
              let second = GitStashID(rawValue: "stash@{1}")
        else {
            return []
        }
        return [
            GitStashEntry(
                id: first,
                message: "On main: 网络恢复前的工作现场",
                baseBranch: "main",
                createdAt: Date().addingTimeInterval(-900),
                fileCount: 4
            ),
            GitStashEntry(
                id: second,
                message: "On feature/sync: 同步性能实验",
                baseBranch: "feature/sync",
                createdAt: Date().addingTimeInterval(-86_400),
                fileCount: 12
            )
        ]
    }

    func create(
        repositoryURL: URL,
        message: String,
        includeUntracked: Bool
    ) async throws {}

    func diff(
        repositoryURL: URL,
        id: GitStashID
    ) async throws -> GitDiffDocument {
        Self.previewDiff(path: "Sources/SyncCoordinator.swift")
    }

    func apply(
        repositoryURL: URL,
        id: GitStashID
    ) async throws -> StashApplyResult {
        .applied
    }

    func pop(
        repositoryURL: URL,
        id: GitStashID,
        confirmation: RiskConfirmation
    ) async throws -> StashApplyResult {
        .applied
    }

    func drop(
        repositoryURL: URL,
        id: GitStashID,
        confirmation: RiskConfirmation
    ) async throws {}

    func popConfirmation(
        repositoryURL: URL,
        id: GitStashID
    ) -> RiskConfirmation {
        Self.confirmation(repositoryURL: repositoryURL, value: "pop")
    }

    func dropConfirmation(
        repositoryURL: URL,
        id: GitStashID
    ) -> RiskConfirmation {
        Self.confirmation(repositoryURL: repositoryURL, value: "drop")
    }

    func preflight(
        repositoryURL: URL,
        request: GitHistoryOperationRequest
    ) async throws -> GitOperationPreflight {
        GitOperationPreflight(
            canStart: true,
            blocker: nil,
            availableRecovery: [],
            affectedFiles: [
                "Sources/SyncCoordinator.swift",
                "Sources/GitClient.swift",
                "Tests/SyncTests.swift"
            ],
            commitCount: 6,
            conflictPrediction: .likely(
                paths: ["Sources/SyncCoordinator.swift"]
            ),
            confirmation: Self.confirmation(
                repositoryURL: repositoryURL,
                value: "history"
            )
        )
    }

    func start(
        repositoryURL: URL,
        request: GitHistoryOperationRequest,
        confirmation: RiskConfirmation
    ) async throws -> GitHistoryOperationResult {
        .completed
    }

    func `continue`(
        repositoryURL: URL
    ) async throws -> GitHistoryOperationResult {
        .completed
    }

    func abort(repositoryURL: URL) async throws {}

    func state(
        repositoryURL: URL
    ) async throws -> GitRepositoryOperationState {
        .none
    }

    func files(repositoryURL: URL) async throws -> [GitConflictFile] {
        [
            GitConflictFile(
                path: "Tests/ConflictTests.swift",
                isBinary: false
            )
        ]
    }

    func document(
        repositoryURL: URL,
        path: String
    ) async throws -> GitConflictDocument {
        GitConflictDocument(
            path: path,
            baseData: Data("base\n".utf8),
            currentData: Data("current\n".utf8),
            incomingData: Data("incoming\n".utf8),
            baseText: "func retry() { old() }\n",
            currentText: "func retry() { reconnect() }\n",
            incomingText: "func retry() { resume() }\n",
            isBinary: false
        )
    }

    func saveTextResult(
        repositoryURL: URL,
        path: String,
        text: String
    ) async throws {}

    func chooseWholeFile(
        repositoryURL: URL,
        path: String,
        side: ConflictSide,
        confirmation: RiskConfirmation
    ) async throws {}

    func wholeFileConfirmation(
        repositoryURL: URL,
        path: String,
        side: ConflictSide
    ) -> RiskConfirmation {
        Self.confirmation(repositoryURL: repositoryURL, value: "binary")
    }

    func planFetch(
        repositoryURL: URL,
        remote: String
    ) async throws -> GitTransferPlan {
        GitTransferPlan(
            operation: .fetch,
            remote: remote,
            branch: nil,
            pullStrategy: nil,
            pushMode: nil,
            expectedRemoteOID: nil,
            ahead: 2,
            behind: 1,
            estimatedBytes: 8_388_608,
            confirmation: nil
        )
    }

    func fetch(
        repositoryURL: URL,
        remote: String,
        context: GitCredentialContext
    ) -> AsyncThrowingStream<GitTransferEvent, Error> {
        Self.transferEvents()
    }

    func planPull(
        repositoryURL: URL,
        remote: String,
        branch: String
    ) async throws -> GitTransferPlan {
        Self.transferPlan(
            repositoryURL: repositoryURL,
            operation: .pull,
            remote: remote,
            branch: branch,
            pullStrategy: .rebase,
            pushMode: nil
        )
    }

    func pull(
        repositoryURL: URL,
        plan: GitTransferPlan,
        context: GitCredentialContext,
        confirmation: RiskConfirmation
    ) -> AsyncThrowingStream<GitTransferEvent, Error> {
        Self.transferEvents(integrating: true)
    }

    func planPush(
        repositoryURL: URL,
        remote: String,
        branch: String,
        mode: PushMode
    ) async throws -> GitTransferPlan {
        Self.transferPlan(
            repositoryURL: repositoryURL,
            operation: .push,
            remote: remote,
            branch: branch,
            pullStrategy: nil,
            pushMode: mode
        )
    }

    func push(
        repositoryURL: URL,
        plan: GitTransferPlan,
        context: GitCredentialContext,
        confirmation: RiskConfirmation
    ) -> AsyncThrowingStream<GitTransferEvent, Error> {
        Self.transferEvents()
    }

    private static func previewDiff(path: String) -> GitDiffDocument {
        GitDiffParser.parse(
            path: path,
            data: Data(
                """
                diff --git a/\(path) b/\(path)
                --- a/\(path)
                +++ b/\(path)
                @@ -18,2 +18,3 @@
                -        retryImmediately()
                +        await network.waitUntilReachable()
                +        retryFromCheckpoint()
                 }
                """.utf8
            )
        )
    }

    private static func confirmation(
        repositoryURL: URL,
        value: String
    ) -> RiskConfirmation {
        RiskConfirmation(
            repositoryID: GitRepositoryIdentifier.make(
                repositoryURL: repositoryURL
            ),
            impactFingerprint: value
        )
    }

    private static func transferPlan(
        repositoryURL: URL,
        operation: GitTransferOperation,
        remote: String,
        branch: String,
        pullStrategy: PullStrategy?,
        pushMode: PushMode?
    ) -> GitTransferPlan {
        GitTransferPlan(
            operation: operation,
            remote: remote,
            branch: branch,
            pullStrategy: pullStrategy,
            pushMode: pushMode,
            expectedRemoteOID: pushMode == .forceWithLease
                ? "a81c32ff"
                : nil,
            ahead: 2,
            behind: 1,
            estimatedBytes: 8_388_608,
            confirmation: confirmation(
                repositoryURL: repositoryURL,
                value: "transfer"
            )
        )
    }

    private static func transferEvents(
        integrating: Bool = false
    ) -> AsyncThrowingStream<GitTransferEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(GitTransferEvent(phase: .connecting))
            continuation.yield(
                GitTransferEvent(
                    phase: .transferring,
                    currentObjects: 640,
                    totalObjects: 1_000,
                    bytesPerSecond: 4_194_304,
                    message: "Receiving objects: 64% (640/1000)"
                )
            )
            if integrating {
                continuation.yield(GitTransferEvent(phase: .integrating))
            }
            continuation.yield(GitTransferEvent(phase: .completed))
            continuation.finish()
        }
    }
}

private struct PreviewRemoteService: GitRemoteServicing {
    func list(repositoryURL: URL) async throws -> [GitRemote] {
        [
            GitRemote(
                name: "origin",
                fetchURL: "https://github.com/GitMate/mac-client.git",
                pushURL: "git@github.com:GitMate/mac-client.git",
                fetchProtocol: .https,
                pushProtocol: .ssh,
                trackingBranches: ["main", "release/2.4"]
            ),
            GitRemote(
                name: "upstream",
                fetchURL: "https://github.com/GitMate/core.git",
                pushURL: "https://github.com/GitMate/core.git",
                fetchProtocol: .https,
                pushProtocol: .https,
                trackingBranches: []
            )
        ]
    }

    func add(
        repositoryURL: URL,
        name: String,
        fetchURL: String,
        pushURL: String?
    ) async throws {}

    func update(
        repositoryURL: URL,
        originalName: String,
        change: GitRemoteChange
    ) async throws {}

    func removalImpact(
        repositoryURL: URL,
        remote: String
    ) async throws -> RemoteRemovalImpact {
        RemoteRemovalImpact(
            remote: remote,
            trackingBranches: ["main"],
            confirmation: RiskConfirmation(
                repositoryID: GitRepositoryIdentifier.make(
                    repositoryURL: repositoryURL
                ),
                impactFingerprint: "remote"
            )
        )
    }

    func remove(
        repositoryURL: URL,
        remote: String,
        confirmation: RiskConfirmation
    ) async throws {}

    func testConnection(
        repositoryURL: URL,
        remote: String,
        context: GitCredentialContext
    ) async throws -> RemoteConnectionResult {
        .connected(referenceCount: 8)
    }
}
