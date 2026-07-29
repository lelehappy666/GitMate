import Foundation

public enum SyncDestinationInspector {
    public static func conflicts(
        repositories: [Repository],
        selectedRepositoryIDs: Set<Int64>,
        destination: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        return repositories.compactMap { repository in
            guard selectedRepositoryIDs.contains(repository.id) else {
                return nil
            }
            let repositoryDirectory = repositoryDirectory(
                for: repository,
                destination: destination
            )
            return hasConflict(
                repository: repository,
                directory: repositoryDirectory,
                fileManager: fileManager
            ) ? repositoryDirectory : nil
        }
    }

    public static func repositoryDirectory(
        for repository: Repository,
        destination: URL
    ) -> URL {
        destination.appending(
            path: safeDirectoryName(repository.name),
            directoryHint: .isDirectory
        )
    }

    private static func hasConflict(
        repository: Repository,
        directory: URL,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        ) else {
            return false
        }
        guard isDirectory.boolValue else {
            return true
        }

        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        guard !contents.isEmpty else {
            return false
        }

        let gitDirectory = directory.appending(
            path: ".git",
            directoryHint: .isDirectory
        )
        var isGitDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: gitDirectory.path,
            isDirectory: &isGitDirectory
        ), isGitDirectory.boolValue else {
            return true
        }

        let configURL = gitDirectory.appending(path: "config")
        guard let config = try? String(
            contentsOf: configURL,
            encoding: .utf8
        ) else {
            return true
        }

        let normalizedConfig = config.lowercased()
        let expectedFullName = repository.fullName.lowercased()
        let expectedCloneURL = repository.cloneURL.absoluteString.lowercased()
        return !normalizedConfig.contains(expectedFullName)
            && !normalizedConfig.contains(expectedCloneURL)
    }

    private static func safeDirectoryName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\")
        return name.components(separatedBy: invalid).joined(separator: "-")
    }
}
