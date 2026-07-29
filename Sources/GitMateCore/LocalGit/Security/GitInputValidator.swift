import Foundation

public enum GitInputValidator {
    public static func isSafeReference(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.hasPrefix("-"),
              value != "@",
              !value.hasSuffix("/"),
              !value.hasSuffix("."),
              !value.hasSuffix(".lock"),
              !value.contains(".."),
              !value.contains("//"),
              !value.contains("@{")
        else {
            return false
        }

        let forbidden = CharacterSet(
            charactersIn: "\0 ~^:?*[\\"
        ).union(.controlCharacters)
        return value.unicodeScalars.allSatisfy {
            !forbidden.contains($0)
        }
    }

    public static func isSafeHash(_ value: String) -> Bool {
        guard (4...64).contains(value.count) else {
            return false
        }
        let hexadecimal = CharacterSet(
            charactersIn: "0123456789abcdefABCDEF"
        )
        return value.unicodeScalars.allSatisfy { hexadecimal.contains($0) }
    }

    public static func isSafeRemoteName(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("-") else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "._-")
        )
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    public static func validatedRepositoryURL(_ url: URL) throws -> URL {
        guard url.isFileURL else {
            throw LocalGitError.notGitRepository
        }

        let resolvedURL = url
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: resolvedURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw LocalGitError.notGitRepository
        }

        let gitMetadataURL = resolvedURL.appending(path: ".git")
        guard FileManager.default.fileExists(atPath: gitMetadataURL.path) else {
            throw LocalGitError.notGitRepository
        }
        return resolvedURL
    }

    public static func validatedRelativePath(
        _ path: String,
        repositoryURL: URL
    ) throws -> String {
        guard !path.isEmpty,
              !path.contains("\0"),
              !NSString(string: path).isAbsolutePath
        else {
            throw LocalGitError.invalidPath
        }

        let repository = try validatedRepositoryURL(repositoryURL)
        let candidate = repository
            .appending(path: path)
            .standardizedFileURL
        let expectedPrefix = repository.path + "/"
        guard candidate.path.hasPrefix(expectedPrefix) else {
            throw LocalGitError.invalidPath
        }

        let resolvedParent = candidate
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
        guard resolvedParent == repository
                || resolvedParent.path.hasPrefix(expectedPrefix)
        else {
            throw LocalGitError.invalidPath
        }
        return path
    }

}
