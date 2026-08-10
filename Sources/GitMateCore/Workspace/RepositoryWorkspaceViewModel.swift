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
    private var loadMoreTask: Task<Void, Never>?

    @ObservationIgnored
    private var loadMoreID: UUID?

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
        loadMoreTask?.cancel()
    }

    public func navigate(to route: RepositoryWorkspaceRoute) {
        loadTask?.cancel()
        loadMoreTask?.cancel()
        loadTask = nil
        loadMoreTask = nil
        loadMoreID = nil
        loadID = UUID()
        state.route = route
        state.status = .idle
        state.errorMessage = nil
    }

    public func cancelPageLoads() {
        loadTask?.cancel()
        loadMoreTask?.cancel()
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
                try await load(route: route, identifier: identifier)
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
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
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
            let nextPageURL = state.nextIssuesPageURL,
            loadMoreTask == nil
        else {
            return
        }
        let query = state.issueQuery
        let identifier = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let page = try await dependencies.issuesAPI.issues(
                    query: query,
                    pageURL: nextPageURL,
                    token: try accessToken()
                )
                try Task.checkCancellation()
                guard
                    state.route == .issues,
                    state.issueQuery == query,
                    state.nextIssuesPageURL == nextPageURL
                else {
                    return
                }
                let existingIDs = Set(state.issues.map(\.id))
                state.issues.append(
                    contentsOf: page.items.filter {
                        !existingIDs.contains($0.id)
                    }
                )
                state.nextIssuesPageURL = page.nextPageURL
            } catch is CancellationError {
                return
            } catch {
                handle(error)
            }
        }
        loadMoreID = identifier
        loadMoreTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if loadMoreID == identifier {
            loadMoreTask = nil
            loadMoreID = nil
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

    @discardableResult
    public func addComment(body: String) async -> Bool {
        guard let issue = state.selectedIssue else {
            return false
        }
        do {
            let comment = try await dependencies.issuesAPI.createComment(
                number: issue.number,
                body: body,
                token: try accessToken()
            )
            state.comments.append(comment)
            state.errorMessage = nil
            return true
        } catch {
            handle(error)
            return false
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

    @discardableResult
    public func updateComment(id: Int64, body: String) async -> Bool {
        do {
            let updated = try await dependencies.issuesAPI.updateComment(
                id: id,
                body: body,
                token: try accessToken()
            )
            if let index = state.comments.firstIndex(where: { $0.id == id }) {
                state.comments[index] = updated
            }
            state.errorMessage = nil
            return true
        } catch {
            handle(error)
            return false
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

    @discardableResult
    public func createMilestone(_ input: MilestoneInput) async -> Bool {
        do {
            let milestone = try await dependencies.issuesAPI.createMilestone(
                input,
                token: try accessToken()
            )
            state.milestones.append(milestone)
            state.status = .ready
            state.errorMessage = nil
            return true
        } catch {
            handleMilestoneMutationError(error)
            return false
        }
    }

    @discardableResult
    public func updateMilestone(
        number: Int,
        input: MilestoneInput
    ) async -> Bool {
        do {
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
            state.status = .ready
            state.errorMessage = nil
            return true
        } catch {
            handleMilestoneMutationError(error)
            return false
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

    public func requestUpdateRuleset(
        _ ruleset: RepositoryRuleset,
        input: RepositoryRulesetInput
    ) {
        pendingDangerousOperation = DangerousOperationRequest(
            action: .updateRuleset(current: ruleset, input: input)
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

            case let .updateRuleset(current, input):
                let updated = try await dependencies.branchesAPI.updateRuleset(
                    current,
                    input: input,
                    token: try accessToken()
                )
                if let index = state.rulesets.firstIndex(
                    where: { $0.id == updated.id }
                ) {
                    state.rulesets[index] = updated
                }

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
                let previousCompleted: [Int]
                if
                    state.labelMergeProgress?.source == source,
                    state.labelMergeProgress?.target == target
                {
                    previousCompleted =
                        state.labelMergeProgress?.completedIssueNumbers ?? []
                } else {
                    previousCompleted = []
                    state.labelMergeProgress = nil
                }
                state.labelMergeProgress = try await dependencies
                    .labelMergeService
                    .merge(
                        source: source,
                        into: target,
                        token: try accessToken(),
                        completedIssueNumbers: previousCompleted
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

    private func load(
        route: RepositoryWorkspaceRoute,
        identifier: UUID
    ) async throws {
        try Task.checkCancellation()
        let token = try accessToken()
        if state.savedIssueViews.isEmpty {
            try ensureCurrent(route: route, identifier: identifier)
            state.savedIssueViews = try dependencies.persistenceStore.savedViews(
                accountID: context.account.id,
                repositoryID: context.repository.id
            )
        }

        switch route {
        case .overview, .readme:
            return
        case .branches:
            let result = try await loadBranches(token: token)
            try ensureCurrent(route: route, identifier: identifier)
            state.branches = result.branches
            state.workingTreeStatus = result.workingTreeStatus
        case .tags:
            let tags: [GitTag]
            if let directory = context.localDirectory {
                async let localTags = dependencies.localGit.tags(at: directory)
                async let remoteTags = dependencies.branchesAPI.remoteTags(
                    token: token
                )
                let values = try await (localTags, remoteTags)
                tags = Self.merge(
                    local: values.0,
                    remote: values.1
                )
            } else {
                tags = try await dependencies.branchesAPI.remoteTags(
                    token: token
                )
            }
            try ensureCurrent(route: route, identifier: identifier)
            state.tags = tags
        case .branchRules:
            let rulesets = try await dependencies.branchesAPI.rulesets(
                token: token
            )
            try ensureCurrent(route: route, identifier: identifier)
            state.rulesets = rulesets
        case .issues:
            let query = state.issueQuery
            let page = try await dependencies.issuesAPI.issues(
                query: query,
                pageURL: nil,
                token: token
            )
            try ensureCurrent(route: route, identifier: identifier)
            guard state.issueQuery == query else {
                throw CancellationError()
            }
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
            try ensureCurrent(route: route, identifier: identifier)
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
            let draft = try dependencies.persistenceStore.issueDraft(
                accountID: context.account.id,
                repositoryID: context.repository.id
            )
            try ensureCurrent(route: route, identifier: identifier)
            state.milestones = values.0
            state.labels = values.1
            state.issueDraft = draft
        case .milestones:
            let milestones = try await dependencies.issuesAPI.milestones(
                state: nil,
                token: token
            )
            try ensureCurrent(route: route, identifier: identifier)
            state.milestones = milestones
        case .issueLabels:
            async let labels = dependencies.issuesAPI.labels(token: token)
            async let usage = dependencies.issuesAPI.labelUsage(token: token)
            let values = try await (labels, usage)
            let enrichedLabels = values.0.map { label in
                var enriched = label
                let counts = values.1[label.name] ?? IssueLabelUsage()
                enriched.openIssueCount = counts.openIssueCount
                enriched.closedIssueCount = counts.closedIssueCount
                return enriched
            }
            try ensureCurrent(route: route, identifier: identifier)
            state.labels = enrichedLabels
        }
    }

    private func loadBranches(
        token: String
    ) async throws -> (
        branches: [GitBranch],
        workingTreeStatus: WorkingTreeStatus?
    ) {
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
            var branches = Self.merge(
                local: values.0,
                remote: values.1
            )
            for index in branches.indices {
                try Task.checkCancellation()
                guard
                    let localSHA = branches[index].localSHA,
                    let remoteSHA = branches[index].remoteSHA,
                    localSHA != remoteSHA
                else {
                    continue
                }
                do {
                    branches[index].comparison = try await dependencies.localGit
                        .comparison(
                        local: localSHA,
                        remote: remoteSHA,
                        at: directory
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    branches[index].comparison = nil
                }
            }
            for index in branches.indices {
                branches[index].isDefault =
                    branches[index].name == context.repository.defaultBranch
            }
            return (branches, values.2)
        } else {
            var branches = try await dependencies.branchesAPI.remoteBranches(
                token: token
            )
            for index in branches.indices {
                branches[index].isDefault =
                    branches[index].name == context.repository.defaultBranch
            }
            return (branches, nil)
        }
    }

    private func ensureCurrent(
        route: RepositoryWorkspaceRoute,
        identifier: UUID
    ) throws {
        try Task.checkCancellation()
        guard loadID == identifier, state.route == route else {
            throw CancellationError()
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

    private func handleMilestoneMutationError(_ error: Error) {
        if case GitHubAPIError.forbidden = error {
            state.status = .failed
            state.errorMessage = "创建或编辑里程碑需要 GitHub Issues 或 Pull Requests 写权限，请更新令牌权限后重试。"
            return
        }
        handle(error)
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

    private static func merge(
        local: [GitTag],
        remote: [GitTag]
    ) -> [GitTag] {
        var tags: [String: GitTag] = [:]
        for var tag in local {
            tag.existsLocally = true
            tag.existsRemotely = false
            tags[tag.name] = tag
        }
        for remoteTag in remote {
            if var existing = tags[remoteTag.name] {
                existing.existsRemotely = true
                if existing.releaseURL == nil {
                    existing.releaseURL = remoteTag.releaseURL
                }
                tags[remoteTag.name] = existing
            } else {
                var tag = remoteTag
                tag.existsLocally = false
                tag.existsRemotely = true
                tags[tag.name] = tag
            }
        }
        return tags.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
