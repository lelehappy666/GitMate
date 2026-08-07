import Foundation

public protocol CommitGraphSceneStoring: Sendable {
    func load(repositoryID: Int64) async throws -> CommitGraphSceneState?

    func save(
        _ scene: CommitGraphSceneState,
        repositoryID: Int64
    ) async throws
}

public enum CommitGraphSceneStoreError: Error, Equatable, Sendable {
    case corruptedScene(repositoryID: Int64)
    case unsupportedSchema(repositoryID: Int64, schemaVersion: Int)
}

public actor JSONCommitGraphSceneStore: CommitGraphSceneStoring {
    private let rootDirectory: URL
    private let fileManager: FileManager

    public init(
        rootDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(
            path: "GitMate/CommitGraphScenes",
            directoryHint: .isDirectory
        ),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public func load(
        repositoryID: Int64
    ) async throws -> CommitGraphSceneState? {
        let url = sceneURL(repositoryID: repositoryID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let storedSchemaVersion: Int
        do {
            storedSchemaVersion = try JSONDecoder().decode(
                SceneVersionEnvelope.self,
                from: data
            ).schemaVersion
        } catch is DecodingError {
            throw CommitGraphSceneStoreError.corruptedScene(
                repositoryID: repositoryID
            )
        }
        guard (1...CommitGraphSceneState.currentSchemaVersion)
            .contains(storedSchemaVersion)
        else {
            throw CommitGraphSceneStoreError.unsupportedSchema(
                repositoryID: repositoryID,
                schemaVersion: storedSchemaVersion
            )
        }

        let scene: CommitGraphSceneState
        do {
            scene = try JSONDecoder().decode(
                CommitGraphSceneState.self,
                from: data
            )
        } catch is DecodingError {
            throw CommitGraphSceneStoreError.corruptedScene(
                repositoryID: repositoryID
            )
        }
        guard scene.schemaVersion
                == CommitGraphSceneState.currentSchemaVersion
        else {
            throw CommitGraphSceneStoreError.unsupportedSchema(
                repositoryID: repositoryID,
                schemaVersion: scene.schemaVersion
            )
        }
        return scene
    }

    public func save(
        _ scene: CommitGraphSceneState,
        repositoryID: Int64
    ) async throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(scene)
        try data.write(
            to: sceneURL(repositoryID: repositoryID),
            options: .atomic
        )
    }

    private func sceneURL(repositoryID: Int64) -> URL {
        rootDirectory.appending(path: "\(repositoryID).json")
    }

    private struct SceneVersionEnvelope: Decodable {
        let schemaVersion: Int
    }
}
