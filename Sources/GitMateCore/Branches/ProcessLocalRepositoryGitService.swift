import Foundation

public final class ProcessLocalRepositoryGitService:
    LocalRepositoryGitService,
    @unchecked Sendable
{
    private struct CommandResult {
        var standardOutput = ""
        var standardError = ""
    }

    private let executor: any CommandExecuting

    public init(executor: any CommandExecuting = ProcessCommandExecutor()) {
        self.executor = executor
    }

    public func branches(at directory: URL) async throws -> [GitBranch] {
        let result = try await run([
            "-C",
            directory.path,
            "for-each-ref",
            "--format=%(refname)%1f%(objectname)%1f%(upstream)%1f%(upstream:short)%1f%(authorname)%1e",
            "refs/heads",
            "refs/remotes"
        ])
        return GitReferenceParser.branches(from: result.standardOutput)
    }

    public func tags(at directory: URL) async throws -> [GitTag] {
        let result = try await run([
            "-C",
            directory.path,
            "for-each-ref",
            "--format=%(refname:short)%1f%(objectname)%1f%(objecttype)%1f%(taggername)%1f%(creatordate:iso8601)%1e",
            "refs/tags"
        ])
        return GitReferenceParser.tags(from: result.standardOutput)
    }

    public func workingTreeStatus(at directory: URL) async throws -> WorkingTreeStatus {
        let result = try await run([
            "-C",
            directory.path,
            "status",
            "--porcelain=v1",
            "-z"
        ])
        let records = result.standardOutput
            .split(whereSeparator: { $0 == "\0" || $0 == "\n" || $0 == "\r" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return WorkingTreeStatus(changedFiles: records)
    }

    public func comparison(
        local: String,
        remote: String,
        at directory: URL
    ) async throws -> BranchComparison {
        let result = try await run([
            "-C",
            directory.path,
            "rev-list",
            "--left-right",
            "--count",
            "\(remote)...\(local)"
        ])
        let counts = result.standardOutput
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Int($0) }
        guard counts.count >= 2 else {
            throw BranchOperationError.commandFailed(
                code: -1,
                message: "Git 未返回可识别的提交比较结果。"
            )
        }
        return BranchComparison(aheadBy: counts[1], behindBy: counts[0])
    }

    public func createBranch(
        _ name: String,
        startPoint: String,
        at directory: URL
    ) async throws {
        try await ensureClean(directory)
        try await validateBranch(name, at: directory)
        _ = try await run([
            "-C",
            directory.path,
            "switch",
            "-c",
            name,
            startPoint
        ])
    }

    public func checkoutBranch(_ name: String, at directory: URL) async throws {
        try await ensureClean(directory)
        _ = try await run([
            "-C",
            directory.path,
            "switch",
            name
        ])
    }

    public func mergeBranch(_ source: String, at directory: URL) async throws {
        try await ensureClean(directory)
        _ = try await run([
            "-C",
            directory.path,
            "merge",
            "--no-edit",
            source
        ])
    }

    public func setUpstream(
        branch: String,
        upstream: String,
        at directory: URL
    ) async throws {
        try await validateBranch(branch, at: directory)
        _ = try await run([
            "-C",
            directory.path,
            "branch",
            "--set-upstream-to",
            upstream,
            branch
        ])
    }

    public func pushBranch(
        _ name: String,
        remote: String,
        at directory: URL
    ) async throws {
        try await validateBranch(name, at: directory)
        try validateRemote(remote)
        _ = try await run([
            "-C",
            directory.path,
            "push",
            "--set-upstream",
            remote,
            name
        ])
    }

    public func deleteBranch(
        _ name: String,
        remote: String?,
        force: Bool,
        at directory: URL
    ) async throws {
        try await validateBranch(name, at: directory)
        if let remote {
            try validateRemote(remote)
            _ = try await run([
                "-C",
                directory.path,
                "push",
                remote,
                ":refs/heads/\(name)"
            ])
        } else {
            _ = try await run([
                "-C",
                directory.path,
                "branch",
                force ? "-D" : "-d",
                name
            ])
        }
    }

    public func createTag(
        _ name: String,
        target: String,
        message: String?,
        at directory: URL
    ) async throws {
        try await validateTag(name, at: directory)
        var arguments = ["-C", directory.path, "tag"]
        if let message, !message.isEmpty {
            arguments += ["-a", name, target, "-m", message]
        } else {
            arguments += [name, target]
        }
        _ = try await run(arguments)
    }

    public func pushTag(
        _ name: String,
        remote: String,
        at directory: URL
    ) async throws {
        try await validateTag(name, at: directory)
        try validateRemote(remote)
        _ = try await run([
            "-C",
            directory.path,
            "push",
            remote,
            "refs/tags/\(name)"
        ])
    }

    public func fetchTags(remote: String, at directory: URL) async throws {
        try validateRemote(remote)
        _ = try await run([
            "-C",
            directory.path,
            "fetch",
            remote,
            "--tags",
            "--prune"
        ])
    }

    public func deleteTag(
        _ name: String,
        remote: String?,
        at directory: URL
    ) async throws {
        try await validateTag(name, at: directory)
        if let remote {
            try validateRemote(remote)
            _ = try await run([
                "-C",
                directory.path,
                "push",
                remote,
                ":refs/tags/\(name)"
            ])
        } else {
            _ = try await run([
                "-C",
                directory.path,
                "tag",
                "-d",
                name
            ])
        }
    }

    private func ensureClean(_ directory: URL) async throws {
        let status = try await workingTreeStatus(at: directory)
        guard status.isClean else {
            throw BranchOperationError.workingTreeNotClean(
                files: status.changedFiles
            )
        }
    }

    private func validateBranch(_ name: String, at directory: URL) async throws {
        do {
            _ = try await run([
                "-C",
                directory.path,
                "check-ref-format",
                "--branch",
                name
            ])
        } catch BranchOperationError.cancelled {
            throw BranchOperationError.cancelled
        } catch {
            throw BranchOperationError.invalidReference(name)
        }
    }

    private func validateTag(_ name: String, at directory: URL) async throws {
        do {
            _ = try await run([
                "-C",
                directory.path,
                "check-ref-format",
                "refs/tags/\(name)"
            ])
        } catch BranchOperationError.cancelled {
            throw BranchOperationError.cancelled
        } catch {
            throw BranchOperationError.invalidReference(name)
        }
    }

    private func validateRemote(_ remote: String) throws {
        let hasWhitespace = remote.contains(where: \.isWhitespace)
        guard
            !remote.isEmpty,
            !remote.hasPrefix("-"),
            !hasWhitespace,
            !remote.contains(where: { $0.isNewline || $0.isASCII && $0.asciiValue! < 32 })
        else {
            throw BranchOperationError.invalidReference(remote)
        }
    }

    private func run(_ arguments: [String]) async throws -> CommandResult {
        do {
            try Task.checkCancellation()
            var result = CommandResult()
            for try await output in executor.execute(
                arguments: arguments,
                environment: [
                    "LC_ALL": "C",
                    "LANG": "C",
                    "GIT_TERMINAL_PROMPT": "0",
                    "GCM_INTERACTIVE": "never"
                ]
            ) {
                try Task.checkCancellation()
                switch output {
                case let .standardOutput(value):
                    result.standardOutput += value
                case let .standardError(value):
                    if !result.standardError.isEmpty {
                        result.standardError += "\n"
                    }
                    result.standardError += value
                }
            }
            return result
        } catch is CancellationError {
            throw BranchOperationError.cancelled
        } catch let error as BranchOperationError {
            throw error
        } catch let CommandExecutionError.exitStatus(code, message) {
            throw BranchOperationError.commandFailed(
                code: code,
                message: Self.redacted(message)
            )
        } catch let CommandExecutionError.launchFailed(message) {
            throw BranchOperationError.commandFailed(
                code: -1,
                message: Self.redacted(message)
            )
        } catch {
            throw BranchOperationError.commandFailed(
                code: -1,
                message: Self.redacted(error.localizedDescription)
            )
        }
    }

    private static func redacted(_ value: String) -> String {
        let replacements = [
            (#"(https?://)[^/@\s]+@"#, "$1***@"),
            (#"(?i)(github_pat_|gh[pousr]_)[A-Za-z0-9_]+"#, "***"),
            (#"(?i)(authorization:\s*bearer\s+)[^\s]+"#, "$1***")
        ]
        return replacements.reduce(value) { partial, replacement in
            guard let expression = try? NSRegularExpression(
                pattern: replacement.0
            ) else {
                return partial
            }
            let range = NSRange(
                partial.startIndex..<partial.endIndex,
                in: partial
            )
            return expression.stringByReplacingMatches(
                in: partial,
                range: range,
                withTemplate: replacement.1
            )
        }
    }
}
