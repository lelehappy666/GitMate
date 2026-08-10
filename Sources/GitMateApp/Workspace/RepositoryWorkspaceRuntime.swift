import GitMateCore

@MainActor
struct RepositoryWorkspaceRuntime {
    let workspaceViewModel: RepositoryWorkspaceViewModel
    let overviewViewModel: RepositoryOverviewViewModel
    let readmeViewModel: READMEViewModel
    let imageAuthorization: READMEImageAuthorization
}
