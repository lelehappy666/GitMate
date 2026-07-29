import CryptoKit
import Foundation

public protocol LocalRepositoryImporting: Sendable {
    func importRepository(
        at selectedURL: URL,
        account: GitHubAccount
    ) async throws -> ImportedLocalRepository
}

public enum LocalRepositoryImportError: Error, LocalizedError, Sendable {
    case invalidSelection
    case notGitRepository
    case missingOrigin
    case malformedOrigin
    case unsupportedHost(expected: String)
    case detachedHead
    case unreadableRepository(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSelection:
            "请选择一个有效的本地文件夹。"
        case .notGitRepository:
            "所选文件夹不是有效的 Git 仓库。"
        case .missingOrigin:
            "仓库没有名为 origin 的远端地址。"
        case .malformedOrigin:
            "无法识别仓库的 origin 远端地址。"
        case let .unsupportedHost(expected):
            "该仓库不属于当前账户的 GitHub 主机 \(expected)。"
        case .detachedHead:
            "仓库当前处于分离 HEAD 状态，请先切换到一个分支。"
        case let .unreadableRepository(message):
            "无法读取本地仓库：\(message)"
        }
    }
}

public final class LocalRepositoryImporter:
    LocalRepositoryImporting,
    @unchecked Sendable
{
    private struct RemoteIdentity {
        let host: String
        let owner: String
        let name: String
    }

    private let executor: any CommandExecuting
    private let fileManager: FileManager

    public init(
        executor: any CommandExecuting = ProcessCommandExecutor(),
        fileManager: FileManager = .default
    ) {
        self.executor = executor
        self.fileManager = fileManager
    }

    public func importRepository(
        at selectedURL: URL,
        account: GitHubAccount
    ) async throws -> ImportedLocalRepository {
        guard selectedURL.isFileURL, selectedURL.path.hasPrefix("/") else {
            throw LocalRepositoryImportError.invalidSelection
        }
        let selectedPath = selectedURL.standardizedFileURL.path
        let repositoryPath: String
        do {
            repositoryPath = try await gitText([
                "-C", selectedPath, "rev-parse", "--show-toplevel"
            ])
        } catch {
            throw LocalRepositoryImportError.notGitRepository
        }
        guard repositoryPath.hasPrefix("/") else {
            throw LocalRepositoryImportError.notGitRepository
        }
        let repositoryURL = URL(fileURLWithPath: repositoryPath)
            .standardizedFileURL

        let origin: String
        do {
            origin = try await gitText([
                "-C", repositoryURL.path, "remote", "get-url", "origin"
            ])
        } catch {
            throw LocalRepositoryImportError.missingOrigin
        }
        let identity = try parseRemote(origin)
        let expectedHost = account.serverURL.host?.lowercased() ?? ""
        guard !expectedHost.isEmpty, identity.host == expectedHost else {
            throw LocalRepositoryImportError.unsupportedHost(
                expected: expectedHost.isEmpty
                    ? account.serverURL.absoluteString
                    : expectedHost
            )
        }

        let currentBranch: String
        do {
            currentBranch = try await gitText([
                "-C", repositoryURL.path,
                "symbolic-ref", "--short", "HEAD"
            ])
        } catch {
            throw LocalRepositoryImportError.detachedHead
        }
        guard !currentBranch.isEmpty else {
            throw LocalRepositoryImportError.detachedHead
        }

        let byteCount: Int64
        do {
            byteCount = try recursiveByteCount(at: repositoryURL)
        } catch {
            throw LocalRepositoryImportError.unreadableRepository(
                error.localizedDescription
            )
        }
        let sizeInKilobytes = Int(
            min(
                Int64(Int.max),
                max(1, (byteCount + 1_023) / 1_024)
            )
        )
        let cloneURL = try canonicalCloneURL(
            account: account,
            identity: identity
        )
        let repository = Repository(
            id: stableRepositoryID(identity),
            name: identity.name,
            fullName: "\(identity.owner)/\(identity.name)",
            isPrivate: false,
            defaultBranch: currentBranch,
            sizeInKilobytes: sizeInKilobytes,
            cloneURL: cloneURL,
            ownerAvatarURL: nil
        )
        return ImportedLocalRepository(
            repository: repository,
            localURL: repositoryURL
        )
    }

    private func gitText(_ arguments: [String]) async throws -> String {
        var data = Data()
        for try await output in executor.execute(
            arguments: arguments,
            environment: [:]
        ) {
            switch output {
            case let .standardOutput(value):
                data.append(contentsOf: value.utf8)
            case let .standardOutputData(value):
                data.append(value)
            case .standardError, .standardErrorData:
                break
            }
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw LocalRepositoryImportError.unreadableRepository(
                "Git 输出不是有效的 UTF-8 文本。"
            )
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseRemote(_ value: String) throws -> RemoteIdentity {
        let host: String
        let rawPath: String
        if !value.contains("://"),
           let separator = value.firstIndex(of: ":"),
           let atSign = value[..<separator].lastIndex(of: "@")
        {
            host = String(value[value.index(after: atSign)..<separator])
                .lowercased()
            rawPath = String(value[value.index(after: separator)...])
        } else if let components = URLComponents(string: value),
                  let parsedHost = components.host
        {
            host = parsedHost.lowercased()
            rawPath = components.path
        } else {
            throw LocalRepositoryImportError.malformedOrigin
        }

        var pathComponents = rawPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard pathComponents.count >= 2 else {
            throw LocalRepositoryImportError.malformedOrigin
        }
        var name = pathComponents.removeLast()
        if name.lowercased().hasSuffix(".git") {
            name.removeLast(4)
        }
        let owner = pathComponents.removeLast()
        guard isValidRepositoryComponent(owner),
              isValidRepositoryComponent(name),
              !host.isEmpty
        else {
            throw LocalRepositoryImportError.malformedOrigin
        }
        return RemoteIdentity(host: host, owner: owner, name: name)
    }

    private func isValidRepositoryComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("\\")
            && !value.contains(":")
    }

    private func canonicalCloneURL(
        account: GitHubAccount,
        identity: RemoteIdentity
    ) throws -> URL {
        guard var components = URLComponents(
            url: account.serverURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw LocalRepositoryImportError.malformedOrigin
        }
        components.scheme = components.scheme?.lowercased() == "http"
            ? "http"
            : "https"
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        let prefix = components.path.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        let suffix = "\(identity.owner)/\(identity.name).git"
        components.path = "/" + ([prefix, suffix].filter { !$0.isEmpty })
            .joined(separator: "/")
        guard let url = components.url else {
            throw LocalRepositoryImportError.malformedOrigin
        }
        return url
    }

    private func stableRepositoryID(_ identity: RemoteIdentity) -> Int64 {
        let normalized = [
            identity.host,
            identity.owner.lowercased(),
            identity.name.lowercased()
        ].joined(separator: "/")
        let digest = SHA256.hash(data: Data(normalized.utf8))
        var value: UInt64 = 0
        for byte in digest.prefix(8) {
            value = (value << 8) | UInt64(byte)
        }
        value &= UInt64(Int64.max)
        return Int64(value == 0 ? 1 : value)
    }

    private func recursiveByteCount(at directory: URL) throws -> Int64 {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true,
              let enumerator = fileManager.enumerator(
                  at: directory,
                  includingPropertiesForKeys: [
                      .isRegularFileKey,
                      .fileSizeKey
                  ]
              )
        else {
            throw CocoaError(.fileReadUnknown)
        }
        var byteCount: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            )
            if values.isRegularFile == true {
                byteCount += Int64(values.fileSize ?? 0)
            }
        }
        return byteCount
    }
}
