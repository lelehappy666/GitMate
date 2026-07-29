import Foundation
import Observation

public enum RepositoryWorkspaceError: Error, Sendable {
    case missingAccessToken
    case repositoryNotAvailableLocally
}

extension RepositoryWorkspaceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAccessToken:
            "账户授权不存在，请重新登录 GitHub。"
        case .repositoryNotAvailableLocally:
            "该仓库尚未同步到本机。"
        }
    }
}

@MainActor
@Observable
public final class RepositoryWorkspaceViewModel {
    public private(set) var state: RepositoryWorkspaceState
    public private(set) var pendingDangerousOperation: DangerousOperationRequest?
    public let context: RepositoryWorkspaceContext

    @ObservationIgnored
    private let dependencies: RepositoryWorkspaceDependencies

    @ObservationIgnored
    private var loadTask: Task<Void, Never>?

    @ObservationIgnored
    private var loadID = UUID()

    public init(
        context: RepositoryWorkspaceContext,
        dependencies: RepositoryWorkspaceDependencies,
        initialRoute: RepositoryWorkspaceRoute = .branches
    ) {
        self.context = context
        self.dependencies = dependencies
        state = RepositoryWorkspaceState(route: initialRoute)
    }

    deinit {
        loadTask?.cancel()
    }

    public func navigate(to route: RepositoryWorkspaceRoute) {
        loadTask?.cancel()
        loadTask = nil
        loadID = UUID()
        state.route = route
        state.status = .idle
        state.errorMessage = nil
    }

    public func loadCurrentRoute() async {
        loadTask?.cancel()
        let route = state.route
        let identifier = UUID()
        loadID = identifier
        state.status = .loading
        state.errorMessage = nil

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                try await load(route: route)
                try Task.checkCancellation()
                guard loadID == identifier, state.route == route else {
                    return
                }
                state.status = .ready
            } catch is CancellationError {
                guard loadID == identifier else {
                    return
                }
                state.status = .idle
            } catch {
                guard loadID == identifier else {
                    return
                }
                handle(error)
            }
        }
        loadTask = task
        await task.value
        if loadID == identifier {
            loadTask = nil
        }
    }

    public func updateIssueQuery(_ query: IssueQuery) async {
        state.issueQuery = query
        state.nextIssuesPageURL = nil
        await loadCurrentRoute()
    }

    public func loadMoreIssues() async {
        guard
            state.route == .issues,
            let nextPageURL = state.nextIssuesPageURL
        else {
            return
        }
        do {
            let page = try await dependencies.issuesAPI.issues(
                query: state.issueQuery,
                pageURL: nextPageURL,
                token: try accessToken()
            )
            state.issues.append(contentsOf: page.items)
            state.nextIssuesPageURL = page.nextPageURL
        } catch {
            handle(error)
        }
    }

    public func saveDraft(_ draft: IssueDraft) {
        do {
            try dependencies.persistenceStore.saveDraft(
                draft,
                accountID: context.account.id,
                repositoryID: context.repository.id
            )
            state.issueDraft = draft
        } catch {
            handle(error)
        }
    }

    public func saveIssueViews(_ views: [SavedIssueView]) {
        do {
            try dependencies.persistenceStore.saveViews(
                views,
                accountID: context.account.id,
                repositoryID: context.repository.id
            )
            state.savedIssueViews = views
        } catch {
            handle(error)
        }
    }

    public func publishIssue(_ input: CreateIssueInput) async {
        do {
            let issue = try await dependencies.issuesAPI.createIssue(
                input,
                token: try accessToken()
            )
            try dependencies.persistenceStore.deleteDraft(
                accountID: context.account.id,
                repositoryID: context.repository.id
            )
            state.issueDraft = nil
            state.selectedIssue = issue
            state.route = .issueDetail(number: issue.number)
            state.status = .ready
            state.errorMessage = nil
        } catch {
            let draft = IssueDraft(
                title: input.title,
                body: input.body ?? "",
                assigneeLogins: input.assigneeLogins,
                labelNames: input.labelNames,
                milestoneNumber: input.milestoneNumber
            )
            try? dependencies.persistenceStore.saveDraft(
                draft,
                accountID: context.account.id,
                repositoryID: context.repository.id
            )
            state.issueDraft = draft
            handle(error)
        }
    }

    public func createBranch(name: String, startPoint: String) async {
        await performAction {
            try await dependencies.localGit.createBranch(
                name,
                startPoint: startPoint,
                at: try localDirectory()
            )
        }
    }

    public func checkoutBranch(name: String) async {
        await performAction {
            try await dependencies.localGit.checkoutBranch(
                name,
                at: try localDirectory()
            )
        }
    }

    public func mergeBranch(source: String) async {
        await performAction {
            try await dependencies.localGit.mergeBranch(
                source,
                at: try localDirectory()
            )
        }
    }

    public func pushBranch(name: String, remote: String) async {
        await performAction {
            try await dependencies.localGit.pushBranch(
                name,
                remote: remote,
                at: try localDirectory()
            )
        }
    }

    public func createTag(
        name: String,
        target: String,
        message: String?
    ) async {
        await performAction {
            try await dependencies.localGit.createTag(
                name,
                target: target,
                message: message,
                at: try localDirectory()
            )
        }
    }

    public func pushTag(name: String, remote: String) async {
        await performAction {
            try await dependencies.localGit.pushTag(
                name,
                remote: remote,
                at: try localDirectory()
            )
        }
    }

    public func fetchTags(remote: String) async {
        await performAction {
            try await dependencies.localGit.fetchTags(
                remote: remote,
                at: try localDirectory()
            )
        }
    }

    public func createRuleset(_ input: RepositoryRulesetInput) async {
        await performAction {
            let ruleset = try await dependencies.branchesAPI.createRuleset(
                input,
                token: try accessToken()
            )
            state.rulesets.append(ruleset)
        }
    }

    public func updateRuleset(
        _ ruleset: RepositoryRuleset,
        input: RepositoryRulesetInput
    ) async {
        await performAction {
            let updated = try await dependencies.branchesAPI.updateRuleset(
                ruleset,
                input: input,
                token: try accessToken()
            )
            if let index = state.rulesets.firstIndex(where: { $0.id == updated.id }) {
                state.rulesets[index] = updated
            }
        }
    }

    public func addComment(body: String) async {
        guard let issue = state.selectedIssue else {
            return
        }
        await performAction {
            let comment = try await dependencies.issuesAPI.createComment(
                number: issue.number,
                body: body,
                token: try accessToken()
            )
            state.comments.append(comment)
        }
    }

    public func updateIssue(_ input: UpdateIssueInput) async {
        guard let issue = state.selectedIssue else {
            return
        }
        await performAction {
            state.selectedIssue = try await dependencies.issuesAPI.updateIssue(
                number: issue.number,
                input: input,
                token: try accessToken()
            )
        }
    }

    public func lockSelectedIssue(reason: IssueLockReason?) async {
        guard let issue = state.selectedIssue else {
            return
        }
        await performAction {
            try await dependencies.issuesAPI.lockIssue(
                number: issue.number,
                reason: reason,
                token: try accessToken()
            )
            state.selectedIssue?.isLocked = true
        }
    }

    public func unlockSelectedIssue() async {
        guard let issue = state.selectedIssue else {
            return
        }
        await performAction {
            try await dependencies.issuesAPI.unlockIssue(
                number: issue.number,
                token: try accessToken()
            )
            state.selectedIssue?.isLocked = false
        }
    }

    public func createMilestone(_ input: MilestoneInput) async {
        await performAction {
            let milestone = try await dependencies.issuesAPI.createMilestone(
                input,
                token: try accessToken()
            )
            state.milestones.append(milestone)
        }
    }

    public func updateMilestone(
        number: Int,
        input: MilestoneInput
    ) async {
        await performAction {
            let milestone = try await dependencies.issuesAPI.updateMilestone(
                number: number,
                input: input,
                token: try accessToken()
            )
            if let index = state.milestones.firstIndex(
                where: { $0.number == number }
            ) {
                state.milestones[index] = milestone
            }
        }
    }

    public func createLabel(_ input: IssueLabelInput) async {
        await performAction {
            let label = try await dependencies.issuesAPI.createLabel(
                input,
                token: try accessToken()
            )
            state.labels.append(label)
        }
    }

    public func updateLabel(name: String, input: IssueLabelInput) async {
        await performAction {
            let label = try await dependencies.issuesAPI.updateLabel(
                name: name,
                input: input,
                token: try accessToken()
            )
            if let index = state.labels.firstIndex(where: { $0.name == name }) {
                state.labels[index] = label
            }
        }
    }

    public func requestDeleteLocalBranch(name: String, force: Bool) {
        pendingDangerousOperation = DangerousOperationRequest(
            action: .deleteLocalBranch(name: name, force: force)
        )
    }

    public func requestDeleteRemoteBranch(remote: String, name: String) {
        pendingDangerousOperation = DangerousOperationRequest(
            action: .deleteRemoteBranch(remote: remote, name: name)
        )
    }

    public func requestDeleteTag(name: String, remote: String?) {
        pendingDangerousOperation = DangerousOperationRequest(
            action: .deleteTag(name: name, remote: remote)
        )
    }

    public func requestDeleteRuleset(_ ruleset: RepositoryRuleset) {
        pendingDangerousOperation = DangerousOperationRequest(
            action: .deleteRuleset(id: ruleset.id, name: ruleset.name)
        )
    }

    public func requestDeleteMilestone(
        number: Int,
        affectedIssues: Int
    ) {
        pendingDangerousOperation = DangerousOperationRequest(
            action: .deleteMilestone(
                number: number,
                affectedIssues: affectedIssues
            )
        )
    }

    public func requestDeleteLabel(name: String, affectedIssues: Int) {
        pendingDangerousOperation = DangerousOperationRequest(
            action: .deleteLabel(
                name: name,
                affectedIssues: affectedIssues
            )
        )
    }

    public func requestMergeLabels(
        source: String,
        target: String,
        affectedIssues: Int
    ) {
        pendingDangerousOperation = DangerousOperationRequest(
            action: .mergeLabels(
                source: source,
                target: target,
                affectedIssues: affectedIssues
            )
        )
    }

    public func cancelDangerousOperation() {
        pendingDangerousOperation = nil
    }

    public func confirmDangerousOperation() async {
        guard let request = pendingDangerousOperation else {
            return
        }
        do {
            switch request.action {
            case let .deleteLocalBranch(name, force):
                try await dependencies.localGit.deleteBranch(
                    name,
                    remote: nil,
                    force: force,
                    at: try localDirectory()
                )
                state.branches.removeAll { $0.name == name && $0.remoteSHA == nil }

            case let .deleteRemoteBranch(remote, name):
                try await dependencies.localGit.deleteBranch(
                    name,
                    remote: remote,
                    force: false,
                    at: try localDirectory()
                )
                if let index = state.branches.firstIndex(where: { $0.name == name }) {
                    state.branches[index].remoteSHA = nil
                    state.branches[index].remoteName = nil
                }

            case let .deleteTag(name, remote):
                try await dependencies.localGit.deleteTag(
                    name,
                    remote: remote,
                    at: try localDirectory()
                )
                state.tags.removeAll { $0.name == name }

            case let .deleteRuleset(id, name):
                let ruleset = state.rulesets.first(where: { $0.id == id })
                    ?? RepositoryRuleset(
                        id: id,
                        name: name,
                        enforcement: .disabled,
                        source: .repository
                    )
                try await dependencies.branchesAPI.deleteRuleset(
                    ruleset,
                    token: try accessToken()
                )
                state.rulesets.removeAll { $0.id == id }

            case let .deleteMilestone(number, _):
                try await dependencies.issuesAPI.deleteMilestone(
                    number: number,
                    token: try accessToken()
                )
                state.milestones.removeAll { $0.number == number }

            case let .deleteLabel(name, _):
                try await dependencies.issuesAPI.deleteLabel(
                    name: name,
                    token: try accessToken()
                )
                state.labels.removeAll { $0.name == name }

            case let .mergeLabels(source, target, _):
                state.labelMergeProgress = try await dependencies
                    .labelMergeService
                    .merge(
                        source: source,
                        into: target,
                        token: try accessToken(),
                        completedIssueNumbers:
                            state.labelMergeProgress?.completedIssueNumbers ?? []
                    )
                if state.labelMergeProgress?.failedIssueNumbers.isEmpty == true {
                    state.labels.removeAll { $0.name == source }
                }
            }
            pendingDangerousOperation = nil
            state.errorMessage = nil
        } catch {
            handle(error)
        }
    }

    private func load(route: RepositoryWorkspaceRoute) async throws {
        try Task.checkCancellation()
        let token = try accessToken()
        if state.savedIssueViews.isEmpty {
            state.savedIssueViews = try dependencies.persistenceStore.savedViews(
                accountID: context.account.id,
                repositoryID: context.repository.id
            )
        }

        switch route {
        case .branches:
            try await loadBranches(token: token)
        case .tags:
            if let directory = context.localDirectory {
                state.tags = try await dependencies.localGit.tags(at: directory)
            } else {
                state.tags = []
            }
        case .branchRules:
            state.rulesets = try await dependencies.branchesAPI.rulesets(
                token: token
            )
        case .issues:
            let page = try await dependencies.issuesAPI.issues(
                query: state.issueQuery,
                pageURL: nil,
                token: token
            )
            state.issues = page.items
            state.nextIssuesPageURL = page.nextPageURL
        case let .issueDetail(number):
            async let issue = dependencies.issuesAPI.issue(
                number: number,
                token: token
            )
            async let timeline = dependencies.issuesAPI.timeline(
                number: number,
                token: token
            )
            async let comments = dependencies.issuesAPI.comments(
                number: number,
                token: token
            )
            let values = try await (issue, timeline, comments)
            state.selectedIssue = values.0
            state.timeline = values.1
            state.comments = values.2
        case .newIssue:
            async let milestones = dependencies.issuesAPI.milestones(
                state: .open,
                token: token
            )
            async let labels = dependencies.issuesAPI.labels(token: token)
            let values = try await (milestones, labels)
            state.milestones = values.0
            state.labels = values.1
            state.issueDraft = try dependencies.persistenceStore.issueDraft(
                accountID: context.account.id,
                repositoryID: context.repository.id
            )
        case .milestones:
            state.milestones = try await dependencies.issuesAPI.milestones(
                state: nil,
                token: token
            )
        case .issueLabels:
            state.labels = try await dependencies.issuesAPI.labels(token: token)
        }
    }

    private func loadBranches(token: String) async throws {
        if let directory = context.localDirectory {
            async let localBranches = dependencies.localGit.branches(at: directory)
            async let remoteBranches = dependencies.branchesAPI.remoteBranches(
                token: token
            )
            async let workingTreeStatus = dependencies.localGit
                .workingTreeStatus(at: directory)
            let values = try await (
                localBranches,
                remoteBranches,
                workingTreeStatus
            )
            state.branches = Self.merge(
                local: values.0,
                remote: values.1
            )
            state.workingTreeStatus = values.2
        } else {
            state.branches = try await dependencies.branchesAPI.remoteBranches(
                token: token
            )
            state.workingTreeStatus = nil
        }
    }

    private func accessToken() throws -> String {
        guard
            let token = try dependencies.credentialStore.token(
                accountID: context.tokenAccountID
            ),
            !token.isEmpty
        else {
            throw RepositoryWorkspaceError.missingAccessToken
        }
        return token
    }

    private func localDirectory() throws -> URL {
        guard let directory = context.localDirectory else {
            throw RepositoryWorkspaceError.repositoryNotAvailableLocally
        }
        return directory
    }

    private func performAction(
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            state.errorMessage = nil
        } catch {
            handle(error)
        }
    }

    private func handle(_ error: Error) {
        switch error {
        case GitHubAPIError.httpStatus(401, _),
             RepositoryWorkspaceError.missingAccessToken:
            state.status = .authorizationExpired
            state.errorMessage = "账户授权已失效，请重新登录 GitHub。"
        case is CancellationError, BranchOperationError.cancelled:
            state.status = .idle
        case is URLError:
            state.status = .offline
            state.errorMessage = "网络连接不可用，已保留当前页面数据。"
        default:
            state.status = .failed
            state.errorMessage = error.localizedDescription
        }
    }

    private static func merge(
        local: [GitBranch],
        remote: [GitBranch]
    ) -> [GitBranch] {
        var branches = Dictionary(
            uniqueKeysWithValues: local.map { ($0.name, $0) }
        )
        for remoteBranch in remote {
            if var existing = branches[remoteBranch.name] {
                existing.remoteSHA = remoteBranch.remoteSHA
                existing.remoteName = existing.remoteName
                    ?? remoteBranch.remoteName
                existing.isProtected = remoteBranch.isProtected
                if existing.authorName == nil {
                    existing.authorName = remoteBranch.authorName
                }
                branches[remoteBranch.name] = existing
            } else {
                branches[remoteBranch.name] = remoteBranch
            }
        }
        return branches.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
