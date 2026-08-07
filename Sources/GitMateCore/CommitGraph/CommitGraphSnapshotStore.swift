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

    public init(
        rootDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(
            path: "GitMate/CommitGraphSnapshots",
            directoryHint: .isDirectory
        ),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public func load(
        repositoryID: Int64
    ) async throws -> CommitGraphSnapshot? {
        let url = snapshotURL(repositoryID: repositoryID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let snapshot: CommitGraphSnapshot
        do {
            snapshot = try PropertyListDecoder().decode(
                CommitGraphSnapshot.self,
                from: Data(contentsOf: url)
            )
        } catch {
            throw CommitGraphSnapshotStoreError.corruptedSnapshot(
                repositoryID: repositoryID
            )
        }

        guard snapshot.schemaVersion == CommitGraphSnapshot.currentSchemaVersion
        else {
            throw CommitGraphSnapshotStoreError.unsupportedSchema(
                repositoryID: repositoryID,
                schemaVersion: snapshot.schemaVersion
            )
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
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(snapshot)

        // Foundation 在目标文件同一目录创建临时文件后再替换，保证读者不会观察到半写入快照。
        try data.write(
            to: snapshotURL(repositoryID: repositoryID),
            options: .atomic
        )
    }

    private func snapshotURL(repositoryID: Int64) -> URL {
        rootDirectory.appending(path: "\(repositoryID).plist")
    }
}
