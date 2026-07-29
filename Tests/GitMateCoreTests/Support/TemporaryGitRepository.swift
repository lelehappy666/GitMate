import Foundation

final class TemporaryGitRepository: @unchecked Sendable {
    let url: URL
    let temporaryRoot: URL

    private init(url: URL, temporaryRoot: URL) {
        self.url = url
        self.temporaryRoot = temporaryRoot
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    static func make(
        initialBranch: String = "main"
    ) throws -> TemporaryGitRepository {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "GitMateLocalGitTests", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let repositoryURL = temporaryRoot
            .appending(path: "repository", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true
        )
        _ = try runGit(
            ["init", "--initial-branch", initialBranch, repositoryURL.path]
        )

        let repository = TemporaryGitRepository(
            url: repositoryURL,
            temporaryRoot: temporaryRoot
        )
        try repository.run(["config", "user.name", "GitMate Tests"])
        try repository.run([
            "config",
            "user.email",
            "gitmate-tests@example.invalid"
        ])
        try repository.run(["config", "commit.gpgSign", "false"])
        return repository
    }

    @discardableResult
    func run(_ arguments: [String]) throws -> String {
        try Self.runGit(["-C", url.path] + arguments)
    }

    func write(path: String, content: String) throws {
        try write(path: path, data: Data(content.utf8))
    }

    func write(path: String, data: Data) throws {
        let fileURL = url.appending(path: path).standardizedFileURL
        guard fileURL.path.hasPrefix(url.standardizedFileURL.path + "/") else {
            throw TemporaryGitRepositoryError.pathOutsideRepository
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    func read(path: String) throws -> String {
        let data = try Data(contentsOf: url.appending(path: path))
        return String(decoding: data, as: UTF8.self)
    }

    func commitAll(message: String) throws {
        try run(["add", "--all"])
        try run(["commit", "-m", message])
    }

    func makeBareRemote() throws -> URL {
        let remoteURL = temporaryRoot
            .appending(path: "remote.git", directoryHint: .isDirectory)
        _ = try Self.runGit(["init", "--bare", remoteURL.path])
        return remoteURL
    }

    func installFailingHook(name: String, message: String) throws {
        let hookURL = url
            .appending(path: ".git/hooks", directoryHint: .isDirectory)
            .appending(path: name)
        let escapedMessage = message.replacingOccurrences(
            of: "'",
            with: "'\\''"
        )
        let script = "#!/bin/sh\nprintf '%s\\n' '\(escapedMessage)' >&2\nexit 1\n"
        try Data(script.utf8).write(to: hookURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: hookURL.path
        )
    }

    func hasUnmergedEntries() throws -> Bool {
        try !run(["ls-files", "--unmerged"]).isEmpty
    }

    func behindCount(upstream: String = "@{upstream}") throws -> Int {
        let output = try run([
            "rev-list",
            "--count",
            "HEAD..\(upstream)"
        ])
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    func remove() throws {
        try FileManager.default.removeItem(at: temporaryRoot)
    }

    private static func runGit(_ arguments: [String]) throws -> String {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(decoding: errorData, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw TemporaryGitRepositoryError.gitFailed(
                status: process.terminationStatus,
                message: errorText
            )
        }
        return String(decoding: outputData, as: UTF8.self)
    }
}

private enum TemporaryGitRepositoryError: Error {
    case pathOutsideRepository
    case gitFailed(status: Int32, message: String)
}
