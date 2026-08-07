import CryptoKit
import Foundation

public enum ConflictSide: Equatable, Sendable {
    case current
    case incoming
}

public struct GitConflictFile: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let isBinary: Bool

    public init(path: String, isBinary: Bool) {
        self.path = path
        self.isBinary = isBinary
    }
}

public struct GitConflictDocument: Equatable, Sendable {
    public let path: String
    public let baseData: Data?
    public let currentData: Data?
    public let incomingData: Data?
    public let baseText: String?
    public let currentText: String?
    public let incomingText: String?
    public let isBinary: Bool

    public init(
        path: String,
        baseData: Data?,
        currentData: Data?,
        incomingData: Data?,
        baseText: String?,
        currentText: String?,
        incomingText: String?,
        isBinary: Bool
    ) {
        self.path = path
        self.baseData = baseData
        self.currentData = currentData
        self.incomingData = incomingData
        self.baseText = baseText
        self.currentText = currentText
        self.incomingText = incomingText
        self.isBinary = isBinary
    }
}

public protocol GitConflictServicing: Sendable {
    func files(repositoryURL: URL) async throws -> [GitConflictFile]

    func document(
        repositoryURL: URL,
        path: String
    ) async throws -> GitConflictDocument

    func saveTextResult(
        repositoryURL: URL,
        path: String,
        text: String
    ) async throws

    func chooseWholeFile(
        repositoryURL: URL,
        path: String,
        side: ConflictSide,
        confirmation: RiskConfirmation
    ) async throws

    func wholeFileConfirmation(
        repositoryURL: URL,
        path: String,
        side: ConflictSide
    ) -> RiskConfirmation
}

public struct GitConflictService: GitConflictServicing, Sendable {
    private let executor: any GitCommandExecuting
    private let coordinator: RepositoryOperationCoordinator
    private let detector: GitOperationStateDetector
    private let commandBuilder: GitCommandBuilder

    public init(
        executor: any GitCommandExecuting = ProcessGitCommandExecutor(),
        coordinator: RepositoryOperationCoordinator =
            RepositoryOperationCoordinator(),
        detector: GitOperationStateDetector = GitOperationStateDetector(),
        commandBuilder: GitCommandBuilder = GitCommandBuilder()
    ) {
        self.executor = executor
        self.coordinator = coordinator
        self.detector = detector
        self.commandBuilder = commandBuilder
    }

    public func files(
        repositoryURL: URL
    ) async throws -> [GitConflictFile] {
        let paths = try await conflictPaths(repositoryURL: repositoryURL)
        var result: [GitConflictFile] = []
        result.reserveCapacity(paths.count)
        for path in paths {
            let document = try await document(
                repositoryURL: repositoryURL,
                path: path
            )
            result.append(
                GitConflictFile(
                    path: path,
                    isBinary: document.isBinary
                )
            )
        }
        return result
    }

    public func document(
        repositoryURL: URL,
        path: String
    ) async throws -> GitConflictDocument {
        let paths = try await conflictPaths(repositoryURL: repositoryURL)
        guard paths.contains(path) else {
            throw LocalGitError.stalePatch
        }

        async let base = blob(
            repositoryURL: repositoryURL,
            path: path,
            stage: 1
        )
        async let current = blob(
            repositoryURL: repositoryURL,
            path: path,
            stage: 2
        )
        async let incoming = blob(
            repositoryURL: repositoryURL,
            path: path,
            stage: 3
        )
        let values = try await (base, current, incoming)
        let isBinary = [values.0, values.1, values.2]
            .compactMap { $0 }
            .contains(where: Self.isBinary)
        return GitConflictDocument(
            path: path,
            baseData: values.0,
            currentData: values.1,
            incomingData: values.2,
            baseText: isBinary ? nil : values.0.flatMap(Self.text),
            currentText: isBinary ? nil : values.1.flatMap(Self.text),
            incomingText: isBinary ? nil : values.2.flatMap(Self.text),
            isBinary: isBinary
        )
    }

    public func saveTextResult(
        repositoryURL: URL,
        path: String,
        text: String
    ) async throws {
        let document = try await document(
            repositoryURL: repositoryURL,
            path: path
        )
        guard !document.isBinary else {
            throw LocalGitError.binaryConflictRequiresWholeFileChoice
        }
        try await save(
            repositoryURL: repositoryURL,
            path: path,
            data: Data(text.utf8)
        )
    }

    public func chooseWholeFile(
        repositoryURL: URL,
        path: String,
        side: ConflictSide,
        confirmation: RiskConfirmation
    ) async throws {
        try validate(
            confirmation,
            repositoryURL: repositoryURL,
            path: path,
            side: side
        )
        let document = try await document(
            repositoryURL: repositoryURL,
            path: path
        )
        let data = side == .current
            ? document.currentData
            : document.incomingData
        try await save(
            repositoryURL: repositoryURL,
            path: path,
            data: data
        )
    }

    public func wholeFileConfirmation(
        repositoryURL: URL,
        path: String,
        side: ConflictSide
    ) -> RiskConfirmation {
        RiskConfirmation(
            repositoryID: GitRepositoryIdentifier.make(
                repositoryURL: repositoryURL
            ),
            impactFingerprint: Self.fingerprint(path: path, side: side)
        )
    }

    private func conflictPaths(
        repositoryURL: URL
    ) async throws -> [String] {
        let command = try commandBuilder.conflictEntries(
            repositoryURL: repositoryURL
        )
        let output = try await executor.collect(command)
        var paths = Set<String>()
        for record in output.stdoutData.split(separator: 0) {
            guard let tab = record.firstIndex(of: 0x09) else {
                continue
            }
            let pathStart = record.index(after: tab)
            paths.insert(
                String(decoding: record[pathStart...], as: UTF8.self)
            )
        }
        return paths.sorted()
    }

    private func blob(
        repositoryURL: URL,
        path: String,
        stage: Int
    ) async throws -> Data? {
        let command = try commandBuilder.conflictBlob(
            repositoryURL: repositoryURL,
            path: path,
            stage: stage
        )
        do {
            return try await executor.collect(command).stdoutData
        } catch let GitCommandError.exitStatus(status, _)
            where status == 128 {
            return nil
        }
    }

    private func save(
        repositoryURL: URL,
        path: String,
        data: Data?
    ) async throws {
        let repository = try GitInputValidator.validatedRepositoryURL(
            repositoryURL
        )
        let validatedPath = try GitInputValidator.validatedRelativePath(
            path,
            repositoryURL: repository
        )
        let targetURL = repository.appending(path: validatedPath)
        let stageCommand = try commandBuilder.stagePaths(
            repositoryURL: repository,
            paths: [validatedPath]
        )
        let executor = executor
        try await coordinator.run(
            repositoryURL: repository,
            kind: .conflictResolution
        ) {
            if let data {
                try Self.atomicReplace(data: data, targetURL: targetURL)
            } else if FileManager.default.fileExists(
                atPath: targetURL.path
            ) {
                try FileManager.default.removeItem(at: targetURL)
            }
            _ = try await executor.collect(stageCommand)
        }
    }

    private func validate(
        _ confirmation: RiskConfirmation,
        repositoryURL: URL,
        path: String,
        side: ConflictSide
    ) throws {
        let age = Date().timeIntervalSince(confirmation.createdAt)
        guard confirmation.repositoryID == GitRepositoryIdentifier.make(
            repositoryURL: repositoryURL
        ),
        confirmation.impactFingerprint == Self.fingerprint(
            path: path,
            side: side
        ),
        age >= 0,
        age <= 300
        else {
            throw LocalGitError.confirmationExpired
        }
    }

    private static func atomicReplace(
        data: Data,
        targetURL: URL
    ) throws {
        let fileManager = FileManager.default
        let parentURL = targetURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parentURL,
            withIntermediateDirectories: true
        )
        let temporaryURL = parentURL.appending(
            path: ".gitmate-\(UUID().uuidString).tmp"
        )
        do {
            try data.write(to: temporaryURL, options: .atomic)
            if fileManager.fileExists(atPath: targetURL.path) {
                _ = try fileManager.replaceItemAt(
                    targetURL,
                    withItemAt: temporaryURL
                )
            } else {
                try fileManager.moveItem(
                    at: temporaryURL,
                    to: targetURL
                )
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private static func isBinary(_ data: Data) -> Bool {
        data.contains(0) || String(data: data, encoding: .utf8) == nil
    }

    private static func text(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)
    }

    private static func fingerprint(
        path: String,
        side: ConflictSide
    ) -> String {
        SHA256.hash(
            data: Data("\(path)\0\(side)".utf8)
        ).map {
            String(format: "%02x", $0)
        }.joined()
    }
}
