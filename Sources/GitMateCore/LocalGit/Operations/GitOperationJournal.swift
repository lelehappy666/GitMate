import CryptoKit
import Foundation

public enum GitRepositoryIdentifier {
    public static func make(repositoryURL: URL) -> String {
        let path = repositoryURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public protocol GitOperationJournalRecording: Sendable {
    func record(_ entry: GitOperationJournalEntry) async throws
    func entries(
        repositoryID: String
    ) async throws -> [GitOperationJournalEntry]
}

public actor GitOperationJournal: GitOperationJournalRecording {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        self.directoryURL = directoryURL
            ?? applicationSupport
                .appending(path: "GitMate", directoryHint: .isDirectory)
                .appending(
                    path: "LocalGitJournal",
                    directoryHint: .isDirectory
                )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    public func record(
        _ entry: GitOperationJournalEntry
    ) throws {
        try validate(repositoryID: entry.repositoryID)
        try ensureDirectory()

        var storedEntries = try readEntries(
            repositoryID: entry.repositoryID
        )
        storedEntries.append(entry.redacted())
        let data = try encoder.encode(storedEntries)
        try data.write(
            to: fileURL(repositoryID: entry.repositoryID),
            options: .atomic
        )
    }

    public func entries(
        repositoryID: String
    ) throws -> [GitOperationJournalEntry] {
        try validate(repositoryID: repositoryID)
        return try readEntries(repositoryID: repositoryID)
    }

    private func readEntries(
        repositoryID: String
    ) throws -> [GitOperationJournalEntry] {
        let url = fileURL(repositoryID: repositoryID)
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }
        return try decoder.decode(
            [GitOperationJournalEntry].self,
            from: Data(contentsOf: url)
        )
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func fileURL(repositoryID: String) -> URL {
        directoryURL.appending(path: "\(repositoryID).json")
    }

    private func validate(repositoryID: String) throws {
        guard repositoryID.count == 64,
              repositoryID.unicodeScalars.allSatisfy({
                  CharacterSet(
                      charactersIn: "0123456789abcdef"
                  ).contains($0)
              })
        else {
            throw LocalGitError.invalidPath
        }
    }
}
