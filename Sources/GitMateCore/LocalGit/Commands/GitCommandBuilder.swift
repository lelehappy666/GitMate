import Foundation

public struct GitCommandBuilder: Sendable {
    public init() {}

    public func version(
        environment: [String: String] = [:]
    ) -> GitCommand {
        GitCommand(
            arguments: ["--version"],
            environment: environment
        )
    }

    public func untrackedFiles(
        repositoryURL: URL,
        environment: [String: String] = [:]
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "ls-files",
                "--others",
                "--exclude-standard",
                "-z"
            ],
            environment: environment
        )
    }
}
