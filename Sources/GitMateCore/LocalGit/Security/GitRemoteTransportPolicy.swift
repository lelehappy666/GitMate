import Foundation

public enum GitRemoteProtocol: Equatable, Sendable {
    case https
    case ssh
    case localFileForTests
    case unsupported
}

public enum GitRemoteTransportPolicy: Equatable, Sendable {
    case production
    case localTest(allowedRoot: URL)

    public func validate(
        remoteURLString: String
    ) throws -> GitRemoteProtocol {
        guard !remoteURLString.isEmpty,
              !remoteURLString.contains("\0"),
              !remoteURLString.contains("\n"),
              !remoteURLString.contains("\r")
        else {
            throw LocalGitError.unsupportedRemoteProtocol
        }

        if let components = URLComponents(string: remoteURLString),
           let scheme = components.scheme?.lowercased() {
            switch scheme {
            case "https":
                guard components.host?.isEmpty == false else {
                    throw LocalGitError.unsupportedRemoteProtocol
                }
                return .https
            case "ssh":
                guard components.host?.isEmpty == false else {
                    throw LocalGitError.unsupportedRemoteProtocol
                }
                return .ssh
            case "file":
                guard let url = components.url else {
                    throw LocalGitError.unsupportedRemoteProtocol
                }
                return try validateLocalURL(url)
            default:
                throw LocalGitError.unsupportedRemoteProtocol
            }
        }

        if isSCPStyleSSH(remoteURLString) {
            return .ssh
        }

        if NSString(string: remoteURLString).isAbsolutePath {
            return try validateLocalURL(
                URL(fileURLWithPath: remoteURLString)
            )
        }

        throw LocalGitError.unsupportedRemoteProtocol
    }

    private func validateLocalURL(
        _ url: URL
    ) throws -> GitRemoteProtocol {
        guard case let .localTest(allowedRoot) = self else {
            throw LocalGitError.unsupportedRemoteProtocol
        }

        let root = allowedRoot
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let candidate = url
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard candidate == root
                || candidate.path.hasPrefix(root.path + "/")
        else {
            throw LocalGitError.unsupportedRemoteProtocol
        }
        return .localFileForTests
    }

    private func isSCPStyleSSH(_ value: String) -> Bool {
        guard let atIndex = value.firstIndex(of: "@"),
              let colonIndex = value[atIndex...].firstIndex(of: ":")
        else {
            return false
        }
        let user = value[..<atIndex]
        let host = value[value.index(after: atIndex)..<colonIndex]
        let path = value[value.index(after: colonIndex)...]
        return !user.isEmpty && !host.isEmpty && !path.isEmpty
    }
}
