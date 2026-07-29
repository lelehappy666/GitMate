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

    public func workingTreeStatus(
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
                "status",
                "--porcelain=v2",
                "-z",
                "--branch",
                "--untracked-files=no"
            ],
            environment: environment
        )
    }

    public func stagePaths(
        repositoryURL: URL,
        paths: [String],
        environment: [String: String] = [:]
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "add",
                "--pathspec-from-file=-",
                "--pathspec-file-nul"
            ],
            environment: environment,
            standardInput: try pathspecData(
                paths,
                repositoryURL: repository
            ),
            cancellation: .finishToSafeState
        )
    }

    public func unstagePaths(
        repositoryURL: URL,
        paths: [String],
        environment: [String: String] = [:]
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "restore",
                "--staged",
                "--pathspec-from-file=-",
                "--pathspec-file-nul"
            ],
            environment: environment,
            standardInput: try pathspecData(
                paths,
                repositoryURL: repository
            ),
            cancellation: .finishToSafeState
        )
    }

    public func diff(
        repositoryURL: URL,
        path: String,
        source: GitDiffSource,
        options: GitDiffOptions
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        let validatedPath = try GitInputValidator.validatedRelativePath(
            path,
            repositoryURL: repository
        )
        var arguments = [
            "-C",
            repository.path,
            "diff",
            "--no-ext-diff",
            "--no-color",
            "--unified=\(options.contextLines)"
        ]
        if source == .index {
            arguments.append("--cached")
        }
        if options.ignoreWhitespace {
            arguments.append("--ignore-all-space")
        }
        arguments.append(contentsOf: [
            "--",
            ":(literal)\(validatedPath)"
        ])
        return GitCommand(arguments: arguments)
    }

    public func applyPatch(
        repositoryURL: URL,
        patch: Data,
        cached: Bool,
        reverse: Bool
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        var arguments = [
            "-C",
            repository.path,
            "apply",
            "--recount"
        ]
        if cached {
            arguments.append("--cached")
        }
        if reverse {
            arguments.append("--reverse")
        }
        arguments.append("-")
        return GitCommand(
            arguments: arguments,
            standardInput: patch,
            cancellation: .finishToSafeState
        )
    }

    public func restoreWorkingTreePaths(
        repositoryURL: URL,
        paths: [String]
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "restore",
                "--worktree",
                "--pathspec-from-file=-",
                "--pathspec-file-nul"
            ],
            standardInput: try pathspecData(
                paths,
                repositoryURL: repository
            ),
            cancellation: .finishToSafeState
        )
    }

    public func commit(
        repositoryURL: URL,
        message: CommitMessage
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        let title = message.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !title.isEmpty else {
            throw LocalGitError.emptyCommitMessage
        }
        let body = message.body.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let value = body.isEmpty
            ? "\(title)\n"
            : "\(title)\n\n\(body)\n"
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "commit",
                "--file=-"
            ],
            standardInput: Data(value.utf8),
            cancellation: .finishToSafeState
        )
    }

    public func stagedPaths(
        repositoryURL: URL
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "diff",
                "--cached",
                "--name-only",
                "-z"
            ]
        )
    }

    public func configurationValue(
        repositoryURL: URL,
        key: GitConfigurationKey
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "config",
                "--get",
                key.rawValue
            ]
        )
    }

    public func latestCommit(
        repositoryURL: URL
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "log",
                "-1",
                "--format=%H%x00%h%x00%s"
            ]
        )
    }

    private func pathspecData(
        _ paths: [String],
        repositoryURL: URL
    ) throws -> Data {
        guard !paths.isEmpty else {
            throw LocalGitError.invalidPath
        }
        var data = Data()
        for path in paths {
            let validated = try GitInputValidator.validatedRelativePath(
                path,
                repositoryURL: repositoryURL
            )
            data.append(Data(validated.utf8))
            data.append(0)
        }
        return data
    }
}
