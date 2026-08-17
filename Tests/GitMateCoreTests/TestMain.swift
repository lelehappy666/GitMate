import Foundation

@main
struct GitMateCoreTestsMain {
    static func main() async {
        let tests = onboardingRouteTests
            + experimentalFeaturePreferenceTests
            + repositoryWorkspaceModelTests
            + onboardingStateTests
            + githubDeviceFlowTests
            + githubAPITests
            + githubRESTClientTests
            + githubBranchesAPITests
            + githubIssuesAPITests
            + milestoneTimelineLayoutTests
            + labelMergeServiceTests
            + workspacePersistenceStoreTests
            + repositoryWorkspaceViewModelTests
            + githubWorkspaceAPITests
            + enterpriseConnectionTests
            + credentialStoreTests
            + repositorySyncServiceTests
            + localRepositoryGitServiceTests
            + gitProgressParserTests
            + repositorySyncPreferenceTests
            + repositorySyncPreferenceStoreTests
            + syncProgressTests
            + syncDestinationTests
            + onboardingViewModelTests
            + workspaceRouteTests
            + repositorySwitcherModelTests
            + localRepositoryCatalogTests
            + importedLocalRepositoryStoreTests
            + localRepositoryImporterTests
            + workspaceRepositoryClassifierTests
            + localGitReaderTests
            + workspaceContentServiceTests
            + dashboardViewModelTests
            + cloudRepositoryViewModelTests
            + repositoryWallViewModelTests
            + repositoryOverviewViewModelTests
            + readmeViewModelTests
            + filesCommitsViewModelTests
            + filePreviewDescriptorTests
            + fileTreePresentationTests
            + repositoryCoverLoaderTests
            + repositoryCoverResolverTests
            + repositoryCoverViewportSchedulerTests
            + readmeBlockParserTests
            + repositoryCoverExtractorTests
            + commitGraphBranchCatalogTests
            + commitGraphBranchBundleTests
            + commitGraphSearchIndexTests
            + commitGraphLayoutTests
            + commitGraphOrganizationTreeLayoutTests
            + commitGraphLaneTopologyTests
            + commitGraphTraditionalLayoutTests
            + commitGraphTraditionalBranchProjectionTests
            + commitGraphTraditionalSegmentProjectionTests
            + commitGraphTraditionalPublicationTests
            + commitGraphTraditionalViewportTests
            + commitGraphAuthorAvatarTests
            + commitGraphTraditionalContentViewportTests
            + commitGraphTraditionalSplitLayoutTests
            + commitGraphPathGeometryTests
            + commitGraphOrganizationRouterTests
            + commitGraphTextFitterTests
            + commitGraphGroupingTests
            + commitGraphSceneProjectorTests
            + commitGraphRenderIndexTests
            + commitGraphLevelOfDetailTests
            + commitGraphSceneStoreTests
            + commitGraphViewportProjectorTests
            + commitGraphViewModelTests
            + commitGraphIntegrityValidatorTests
            + commitGraphSnapshotStoreTests
            + commitGraphRefreshCoordinatorTests
            + commitGraphSceneReconcilerTests
            + commitGraphPerformanceTests
        var failedCount = 0

        for test in tests {
            do {
                try await test.body()
                print("✓ \(test.name)")
            } catch {
                failedCount += 1
                print("✗ \(test.name)：\(error)")
            }
        }

        print("完成 \(tests.count) 个测试，失败 \(failedCount) 个。")

        if failedCount > 0 {
            exit(EXIT_FAILURE)
        }
    }
}
