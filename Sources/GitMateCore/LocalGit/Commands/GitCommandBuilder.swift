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

    public func stashList(
        repositoryURL: URL
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "stash",
                "list",
                "--format=%gd%x00%gs%x00%ct%x00"
            ]
        )
    }

    public func stashCreate(
        repositoryURL: URL,
        message: String,
        includeUntracked: Bool
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        let value = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var arguments = [
            "-C",
            repository.path,
            "stash",
            "push"
        ]
        if includeUntracked {
            arguments.append("--include-untracked")
        }
        if !value.isEmpty {
            arguments.append(contentsOf: ["--message", value])
        }
        arguments.append("--")
        return GitCommand(
            arguments: arguments,
            cancellation: .finishToSafeState
        )
    }

    public func stashPaths(
        repositoryURL: URL,
        id: GitStashID
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "-c",
                "core.quotepath=false",
                "stash",
                "show",
                "--name-only",
                "-z",
                "--include-untracked",
                id.rawValue
            ]
        )
    }

    public func stashDiff(
        repositoryURL: URL,
        id: GitStashID
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "-c",
                "core.quotepath=false",
                "stash",
                "show",
                "--patch",
                "--binary",
                "--include-untracked",
                id.rawValue
            ]
        )
    }

    public func stashApply(
        repositoryURL: URL,
        id: GitStashID,
        pop: Bool
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "stash",
                pop ? "pop" : "apply",
                id.rawValue
            ],
            cancellation: .finishToSafeState
        )
    }

    public func stashDrop(
        repositoryURL: URL,
        id: GitStashID
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "stash",
                "drop",
                id.rawValue
            ],
            cancellation: .finishToSafeState
        )
    }

    public func unmergedPaths(
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
                "--name-only",
                "--diff-filter=U",
                "-z"
            ]
        )
    }

    public func fullWorkingTreeStatus(
        repositoryURL: URL
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
                "--untracked-files=normal"
            ]
        )
    }

    public func headOID(
        repositoryURL: URL
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "rev-parse",
                "--verify",
                "HEAD"
            ]
        )
    }

    public func verifyCommit(
        repositoryURL: URL,
        reference: String
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        guard GitInputValidator.isSafeReference(reference)
                || GitInputValidator.isSafeHash(reference)
        else {
            throw LocalGitError.invalidReference
        }
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "rev-parse",
                "--verify",
                "\(reference)^{commit}"
            ]
        )
    }

    public func historyAffectedPaths(
        repositoryURL: URL,
        first: String,
        second: String
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        try validateHistoryEndpoint(first)
        try validateHistoryEndpoint(second)
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "diff",
                "--name-only",
                "-z",
                "\(first)...\(second)"
            ]
        )
    }

    public func commitAffectedPaths(
        repositoryURL: URL,
        commit: String
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        guard GitInputValidator.isSafeHash(commit) else {
            throw LocalGitError.invalidReference
        }
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "show",
                "--format=",
                "--name-only",
                "-z",
                commit
            ]
        )
    }

    public func historyCommitCount(
        repositoryURL: URL,
        range: String
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        let endpoints = range.components(separatedBy: "..")
        guard endpoints.count == 2 else {
            throw LocalGitError.invalidReference
        }
        try validateHistoryEndpoint(endpoints[0])
        try validateHistoryEndpoint(endpoints[1])
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "rev-list",
                "--count",
                range
            ]
        )
    }

    public func mergeBase(
        repositoryURL: URL,
        first: String,
        second: String
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        try validateHistoryEndpoint(first)
        try validateHistoryEndpoint(second)
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "merge-base",
                first,
                second
            ]
        )
    }

    public func mergeTree(
        repositoryURL: URL,
        base: String,
        ours: String,
        theirs: String
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        for value in [base, ours, theirs] {
            try validateHistoryEndpoint(value)
        }
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "merge-tree",
                base,
                ours,
                theirs
            ]
        )
    }

    public func startHistoryOperation(
        repositoryURL: URL,
        request: GitHistoryOperationRequest
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        let arguments: [String]
        switch request {
        case let .merge(source):
            try validateHistoryEndpoint(source)
            arguments = [
                "-C", repository.path, "merge", "--no-edit", "--", source
            ]
        case let .rebase(onto):
            try validateHistoryEndpoint(onto)
            arguments = [
                "-C", repository.path, "rebase", "--", onto
            ]
        case let .cherryPick(commits):
            guard !commits.isEmpty else {
                throw LocalGitError.invalidReference
            }
            for commit in commits {
                guard GitInputValidator.isSafeHash(commit) else {
                    throw LocalGitError.invalidReference
                }
            }
            arguments = [
                "-C", repository.path, "cherry-pick", "--"
            ] + commits
        }
        return GitCommand(
            arguments: arguments,
            environment: ["GIT_EDITOR": "true"],
            cancellation: .finishToSafeState
        )
    }

    public func continueHistoryOperation(
        repositoryURL: URL,
        kind: GitRepositoryOperationKind
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        let operation: String
        switch kind {
        case .merge:
            operation = "merge"
        case .rebase:
            operation = "rebase"
        case .cherryPick:
            operation = "cherry-pick"
        }
        return GitCommand(
            arguments: [
                "-C", repository.path, operation, "--continue"
            ],
            environment: ["GIT_EDITOR": "true"],
            cancellation: .finishToSafeState
        )
    }

    public func abortHistoryOperation(
        repositoryURL: URL,
        kind: GitRepositoryOperationKind
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        let operation: String
        switch kind {
        case .merge:
            operation = "merge"
        case .rebase:
            operation = "rebase"
        case .cherryPick:
            operation = "cherry-pick"
        }
        return GitCommand(
            arguments: [
                "-C", repository.path, operation, "--abort"
            ],
            cancellation: .finishToSafeState
        )
    }

    public func conflictEntries(
        repositoryURL: URL
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "ls-files",
                "--unmerged",
                "-z"
            ]
        )
    }

    public func conflictBlob(
        repositoryURL: URL,
        path: String,
        stage: Int
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        let validatedPath = try GitInputValidator.validatedRelativePath(
            path,
            repositoryURL: repository
        )
        guard (1...3).contains(stage) else {
            throw LocalGitError.invalidReference
        }
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "show",
                ":\(stage):\(validatedPath)"
            ]
        )
    }

    public func remoteNames(
        repositoryURL: URL
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        return GitCommand(
            arguments: ["-C", repository.path, "remote"]
        )
    }

    public func remoteURL(
        repositoryURL: URL,
        name: String,
        push: Bool
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        guard GitInputValidator.isSafeRemoteName(name) else {
            throw LocalGitError.invalidReference
        }
        var arguments = [
            "-C", repository.path, "remote", "get-url"
        ]
        if push {
            arguments.append("--push")
        }
        arguments.append(name)
        return GitCommand(arguments: arguments)
    }

    public func branchTrackingRemotes(
        repositoryURL: URL
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "for-each-ref",
                "--format=%(refname:short)%00%(upstream:remotename)%00",
                "refs/heads/"
            ]
        )
    }

    public func addRemote(
        repositoryURL: URL,
        name: String,
        url: String
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        guard GitInputValidator.isSafeRemoteName(name) else {
            throw LocalGitError.invalidReference
        }
        return GitCommand(
            arguments: [
                "-C", repository.path, "remote", "add", name, url
            ],
            cancellation: .finishToSafeState
        )
    }

    public func renameRemote(
        repositoryURL: URL,
        originalName: String,
        newName: String
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        guard GitInputValidator.isSafeRemoteName(originalName),
              GitInputValidator.isSafeRemoteName(newName)
        else {
            throw LocalGitError.invalidReference
        }
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "remote",
                "rename",
                originalName,
                newName
            ],
            cancellation: .finishToSafeState
        )
    }

    public func setRemoteURL(
        repositoryURL: URL,
        name: String,
        url: String,
        push: Bool
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        guard GitInputValidator.isSafeRemoteName(name) else {
            throw LocalGitError.invalidReference
        }
        var arguments = [
            "-C", repository.path, "remote", "set-url"
        ]
        if push {
            arguments.append("--push")
        }
        arguments.append(contentsOf: [name, url])
        return GitCommand(
            arguments: arguments,
            cancellation: .finishToSafeState
        )
    }

    public func unsetRemotePushURL(
        repositoryURL: URL,
        name: String
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        guard GitInputValidator.isSafeRemoteName(name) else {
            throw LocalGitError.invalidReference
        }
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "config",
                "--unset-all",
                "remote.\(name).pushurl"
            ],
            cancellation: .finishToSafeState
        )
    }

    public func removeRemote(
        repositoryURL: URL,
        name: String
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        guard GitInputValidator.isSafeRemoteName(name) else {
            throw LocalGitError.invalidReference
        }
        return GitCommand(
            arguments: [
                "-C", repository.path, "remote", "remove", name
            ],
            cancellation: .finishToSafeState
        )
    }

    public func lsRemoteHeads(
        repositoryURL: URL,
        remote: String,
        environment: [String: String]
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        guard GitInputValidator.isSafeRemoteName(remote) else {
            throw LocalGitError.invalidReference
        }
        return GitCommand(
            arguments: [
                "-C", repository.path, "ls-remote", "--heads", remote
            ],
            environment: environment
        )
    }

    public func fetch(
        repositoryURL: URL,
        remote: String,
        environment: [String: String]
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        guard GitInputValidator.isSafeRemoteName(remote) else {
            throw LocalGitError.invalidReference
        }
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "fetch",
                "--progress",
                "--prune",
                remote
            ],
            environment: environment,
            cancellation: .terminateProcess
        )
    }

    public func aheadBehind(
        repositoryURL: URL,
        remote: String,
        branch: String
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        guard GitInputValidator.isSafeRemoteName(remote),
              GitInputValidator.isSafeReference(branch)
        else {
            throw LocalGitError.invalidReference
        }
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "rev-list",
                "--left-right",
                "--count",
                "refs/remotes/\(remote)/\(branch)...HEAD"
            ]
        )
    }

    public func remoteTrackingOID(
        repositoryURL: URL,
        remote: String,
        branch: String
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        guard GitInputValidator.isSafeRemoteName(remote),
              GitInputValidator.isSafeReference(branch)
        else {
            throw LocalGitError.invalidReference
        }
        return GitCommand(
            arguments: [
                "-C",
                repository.path,
                "rev-parse",
                "--verify",
                "refs/remotes/\(remote)/\(branch)"
            ]
        )
    }

    public func integratePull(
        repositoryURL: URL,
        plan: GitTransferPlan
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        guard plan.operation == .pull,
              let branch = plan.branch,
              let strategy = plan.pullStrategy,
              GitInputValidator.isSafeRemoteName(plan.remote),
              GitInputValidator.isSafeReference(branch)
        else {
            throw LocalGitError.invalidReference
        }
        let upstream = "refs/remotes/\(plan.remote)/\(branch)"
        let arguments: [String]
        switch strategy {
        case .fastForwardOnly:
            arguments = [
                "-C",
                repository.path,
                "merge",
                "--ff-only",
                upstream
            ]
        case .merge:
            arguments = [
                "-C",
                repository.path,
                "merge",
                "--no-edit",
                upstream
            ]
        case .rebase:
            arguments = [
                "-C",
                repository.path,
                "rebase",
                upstream
            ]
        }
        return GitCommand(
            arguments: arguments,
            environment: ["GIT_EDITOR": "true"],
            cancellation: .finishToSafeState
        )
    }

    public func push(
        repositoryURL: URL,
        plan: GitTransferPlan,
        environment: [String: String]
    ) throws -> GitCommand {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        guard plan.operation == .push,
              let branch = plan.branch,
              let mode = plan.pushMode,
              GitInputValidator.isSafeRemoteName(plan.remote),
              GitInputValidator.isSafeReference(branch)
        else {
            throw LocalGitError.invalidReference
        }
        var arguments = [
            "-C",
            repository.path,
            "push",
            "--progress"
        ]
        if mode == .forceWithLease {
            guard let expectedOID = plan.expectedRemoteOID,
                  GitInputValidator.isSafeHash(expectedOID)
            else {
                throw LocalGitError.invalidReference
            }
            arguments.append(
                "--force-with-lease=refs/heads/\(branch):\(expectedOID)"
            )
        }
        arguments.append(contentsOf: [
            plan.remote,
            "refs/heads/\(branch):refs/heads/\(branch)"
        ])
        return GitCommand(
            arguments: arguments,
            environment: environment,
            cancellation: .terminateProcess
        )
    }

    private func validateHistoryEndpoint(_ value: String) throws {
        guard value == "HEAD"
                || GitInputValidator.isSafeReference(value)
                || GitInputValidator.isSafeHash(value)
        else {
            throw LocalGitError.invalidReference
        }
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
