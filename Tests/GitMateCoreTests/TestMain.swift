import Foundation

@main
struct GitMateCoreTestsMain {
    static func main() async {
        let tests = onboardingRouteTests
            + localGitCommandTests
            + localGitSecurityTests
            + repositoryOperationCoordinatorTests
            + workingTreeReaderTests
            + workingTreeStressTests
            + workingTreeViewModelTests
            + gitDiffServiceTests
            + gitCommitServiceTests
            + gitStashServiceTests
            + onboardingStateTests
            + githubDeviceFlowTests
            + githubAPITests
            + enterpriseConnectionTests
            + credentialStoreTests
            + repositorySyncServiceTests
            + gitProgressParserTests
            + syncProgressTests
            + syncDestinationTests
            + onboardingViewModelTests
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
