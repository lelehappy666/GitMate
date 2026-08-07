import Foundation

public struct LocalGitLaunchConfiguration: Equatable, Sendable {
    public let repositoryURL: URL?
    public let previewRoute: LocalGitRoute?

    public init(
        arguments: [String],
        fileManager: FileManager = .default
    ) throws {
        var repositoryPath: String?
        var previewPage: Int?
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--local-repository":
                guard repositoryPath == nil,
                      arguments.indices.contains(index + 1)
                else {
                    throw LocalGitError.invalidPath
                }
                repositoryPath = arguments[index + 1]
                index += 2
            case "--preview-page":
                guard previewPage == nil,
                      arguments.indices.contains(index + 1),
                      let page = Int(arguments[index + 1])
                else {
                    throw LocalGitError.invalidPath
                }
                previewPage = page
                index += 2
            default:
                index += 1
            }
        }

        if let page = previewPage, (30...37).contains(page) {
            previewRoute = LocalGitRoute(pageNumber: page)
        } else {
            previewRoute = nil
        }

        guard let repositoryPath else {
            repositoryURL = nil
            return
        }
        guard NSString(string: repositoryPath).isAbsolutePath else {
            throw LocalGitError.invalidPath
        }
        let candidate = URL(fileURLWithPath: repositoryPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: candidate.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw LocalGitError.notGitRepository
        }
        repositoryURL = try GitInputValidator.validatedRepositoryURL(
            candidate
        )
    }
}
