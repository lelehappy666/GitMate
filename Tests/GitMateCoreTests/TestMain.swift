import Foundation

@main
struct GitMateCoreTestsMain {
    static func main() async {
        let tests = onboardingRouteTests
            + onboardingStateTests
            + githubDeviceFlowTests
            + githubAPITests
            + githubWorkspaceAPITests
            + enterpriseConnectionTests
            + credentialStoreTests
            + repositorySyncServiceTests
            + repositorySyncPreferenceTests
            + repositorySyncPreferenceStoreTests
            + syncProgressTests
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
            + commitGraphLayoutTests
            + commitGraphLaneTopologyTests
            + commitGraphTraditionalLayoutTests
            + commitGraphTraditionalViewportTests
            + commitGraphPathGeometryTests
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
