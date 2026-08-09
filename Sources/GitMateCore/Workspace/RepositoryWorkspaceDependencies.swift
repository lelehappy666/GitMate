public struct RepositoryWorkspaceDependencies: Sendable {
    public let localGit: any LocalRepositoryGitService
    public let branchesAPI: any GitHubBranchesAPI
    public let issuesAPI: any GitHubIssuesAPI
    public let credentialStore: any CredentialStore
    public let persistenceStore: any WorkspacePersistenceStore
    public let labelMergeService: any LabelMerging

    public init(
        localGit: any LocalRepositoryGitService,
        branchesAPI: any GitHubBranchesAPI,
        issuesAPI: any GitHubIssuesAPI,
        credentialStore: any CredentialStore,
        persistenceStore: any WorkspacePersistenceStore,
        labelMergeService: any LabelMerging
    ) {
        self.localGit = localGit
        self.branchesAPI = branchesAPI
        self.issuesAPI = issuesAPI
        self.credentialStore = credentialStore
        self.persistenceStore = persistenceStore
        self.labelMergeService = labelMergeService
    }
}
