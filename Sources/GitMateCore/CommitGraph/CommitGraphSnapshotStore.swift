import Foundation

public protocol CommitGraphSnapshotStoring: Sendable {
    func load(repositoryID: Int64) async throws -> CommitGraphSnapshot?

    func save(
        _ snapshot: CommitGraphSnapshot,
        repositoryID: Int64
    ) async throws
}

public enum CommitGraphSnapshotStoreError: Error, Equatable, Sendable {
    case corruptedSnapshot(repositoryID: Int64)
    case unsupportedSchema(repositoryID: Int64, schemaVersion: Int)
}

public actor BinaryCommitGraphSnapshotStore: CommitGraphSnapshotStoring {
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let dataReader: @Sendable (URL) throws -> Data

    public init(
        rootDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(
            path: "GitMate/CommitGraphSnapshots",
            directoryHint: .isDirectory
        ),
        fileManager: FileManager = .default,
        dataReader: @escaping @Sendable (URL) throws -> Data = {
            try Data(contentsOf: $0)
        }
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        self.dataReader = dataReader
    }

    public func load(
        repositoryID: Int64
    ) async throws -> CommitGraphSnapshot? {
        let url = snapshotURL(repositoryID: repositoryID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try dataReader(url)

        let storedSchemaVersion: Int
        do {
            storedSchemaVersion = try PropertyListDecoder().decode(
                SnapshotVersionEnvelope.self,
                from: data
            ).schemaVersion
        } catch {
            throw CommitGraphSnapshotStoreError.corruptedSnapshot(
                repositoryID: repositoryID
            )
        }
        guard (1...CommitGraphSnapshot.currentSchemaVersion)
            .contains(storedSchemaVersion)
        else {
            throw CommitGraphSnapshotStoreError.unsupportedSchema(
                repositoryID: repositoryID,
                schemaVersion: storedSchemaVersion
            )
        }

        let snapshot: CommitGraphSnapshot
        do {
            snapshot = try PropertyListDecoder().decode(
                CommitGraphSnapshot.self,
                from: data
            )
        } catch {
            throw CommitGraphSnapshotStoreError.corruptedSnapshot(
                repositoryID: repositoryID
            )
        }

        if storedSchemaVersion < CommitGraphSnapshot.currentSchemaVersion {
            try await save(snapshot, repositoryID: repositoryID)
        }
        return snapshot
    }

    public func save(
        _ snapshot: CommitGraphSnapshot,
        repositoryID: Int64
    ) async throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        let destination = snapshotURL(repositoryID: repositoryID)
        if fileManager.fileExists(atPath: destination.path),
           let existingSchemaVersion = try? PropertyListDecoder().decode(
               SnapshotVersionEnvelope.self,
               from: dataReader(destination)
           ).schemaVersion,
           existingSchemaVersion > CommitGraphSnapshot.currentSchemaVersion {
            // 新版应用写入的快照不能被当前版本回退覆盖；保留文件，等
            // 支持对应 schema 的版本接手。
            throw CommitGraphSnapshotStoreError.unsupportedSchema(
                repositoryID: repositoryID,
                schemaVersion: existingSchemaVersion
            )
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(snapshot)

        // Foundation 在目标文件同一目录创建临时文件后再替换，保证读者不会观察到半写入快照。
        try data.write(
            to: destination,
            options: .atomic
        )
    }

    private func snapshotURL(repositoryID: Int64) -> URL {
        rootDirectory.appending(path: "\(repositoryID).plist")
    }

    private struct SnapshotVersionEnvelope: Decodable {
        let schemaVersion: Int
    }
}
