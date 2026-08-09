import CryptoKit
import Foundation

public struct ImportedLocalRepository: Equatable, Codable, Sendable {
    public let repository: Repository
    public let localURL: URL

    public init(repository: Repository, localURL: URL) {
        self.repository = repository
        self.localURL = localURL
    }
}

public protocol ImportedLocalRepositoryStoring: Sendable {
    func load(accountID: String) throws -> [ImportedLocalRepository]
    func save(
        _ records: [ImportedLocalRepository],
        accountID: String
    ) throws
}

public final class JSONImportedLocalRepositoryStore:
    ImportedLocalRepositoryStoring,
    @unchecked Sendable
{
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        rootDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(
            path: "GitMate/ImportedRepositories",
            directoryHint: .isDirectory
        ),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public func load(accountID: String) throws -> [ImportedLocalRepository] {
        lock.lock()
        defer { lock.unlock() }
        let url = storageURL(accountID: accountID)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode(
            [ImportedLocalRepository].self,
            from: Data(contentsOf: url)
        )
    }

    public func save(
        _ records: [ImportedLocalRepository],
        accountID: String
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )

        var latestByRepositoryID: [Int64: ImportedLocalRepository] = [:]
        var repositoryIDs: [Int64] = []
        for record in records {
            if latestByRepositoryID[record.repository.id] == nil {
                repositoryIDs.append(record.repository.id)
            }
            latestByRepositoryID[record.repository.id] = sanitized(record)
        }
        let normalized = repositoryIDs.compactMap { latestByRepositoryID[$0] }
        try JSONEncoder().encode(normalized).write(
            to: storageURL(accountID: accountID),
            options: .atomic
        )
    }

    private func storageURL(accountID: String) -> URL {
        let digest = SHA256.hash(data: Data(accountID.utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined()
        return rootDirectory.appending(path: "\(filename).json")
    }

    private func sanitized(
        _ record: ImportedLocalRepository
    ) -> ImportedLocalRepository {
        let repository = record.repository
        return ImportedLocalRepository(
            repository: Repository(
                id: repository.id,
                name: repository.name,
                fullName: repository.fullName,
                isPrivate: repository.isPrivate,
                defaultBranch: repository.defaultBranch,
                sizeInKilobytes: repository.sizeInKilobytes,
                cloneURL: sanitizedURL(repository.cloneURL),
                ownerAvatarURL: repository.ownerAvatarURL.map(sanitizedURL),
                primaryLanguage: repository.primaryLanguage
            ),
            localURL: standardizedFileURL(record.localURL)
        )
    }

    private func sanitizedURL(_ url: URL) -> URL {
        var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )
        components?.user = nil
        components?.password = nil
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? url
    }

    private func standardizedFileURL(_ url: URL) -> URL {
        guard url.isFileURL else { return sanitizedURL(url) }
        return url.standardizedFileURL
    }
}
