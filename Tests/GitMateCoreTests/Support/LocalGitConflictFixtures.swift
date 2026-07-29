import Foundation
import GitMateCore

struct MergeConflictFixture: Sendable {
    let repository: TemporaryGitRepository
    let service: GitHistoryOperationService
    let detector: GitOperationStateDetector
    let conflictService: GitConflictService
    let sourceBranch: String
    let path: String
    let confirmation: RiskConfirmation

    static func make() async throws -> MergeConflictFixture {
        let repository = try TemporaryGitRepository.make()
        let path = "conflict.txt"
        try repository.write(path: path, content: "base\n")
        try repository.commitAll(message: "初始")
        try repository.run(["switch", "-c", "source"])
        try repository.write(path: path, content: "incoming\n")
        try repository.commitAll(message: "来源修改")
        try repository.run(["switch", "main"])
        try repository.write(path: path, content: "current\n")
        try repository.commitAll(message: "当前修改")

        let detector = GitOperationStateDetector()
        let service = GitHistoryOperationService(detector: detector)
        let conflictService = GitConflictService(detector: detector)
        let preflight = try await service.preflight(
            repositoryURL: repository.url,
            request: .merge(source: "source")
        )
        guard let confirmation = preflight.confirmation else {
            throw TestFailure(description: "合并预检应返回确认信息")
        }
        return MergeConflictFixture(
            repository: repository,
            service: service,
            detector: detector,
            conflictService: conflictService,
            sourceBranch: "source",
            path: path,
            confirmation: confirmation
        )
    }

    func startMerge() async throws -> GitHistoryOperationResult {
        try await service.start(
            repositoryURL: repository.url,
            request: .merge(source: sourceBranch),
            confirmation: confirmation
        )
    }
}

struct BinaryConflictFixture: Sendable {
    let repository: TemporaryGitRepository
    let service: GitConflictService
    let path: String

    static func make() async throws -> BinaryConflictFixture {
        let repository = try TemporaryGitRepository.make()
        let path = "conflict.bin"
        try repository.write(path: path, data: Data([0, 1, 2]))
        try repository.commitAll(message: "初始二进制")
        try repository.run(["switch", "-c", "source"])
        try repository.write(path: path, data: Data([0, 3, 4]))
        try repository.commitAll(message: "来源二进制")
        try repository.run(["switch", "main"])
        try repository.write(path: path, data: Data([0, 5, 6]))
        try repository.commitAll(message: "当前二进制")

        let detector = GitOperationStateDetector()
        let historyService = GitHistoryOperationService(detector: detector)
        let request = GitHistoryOperationRequest.merge(source: "source")
        let preflight = try await historyService.preflight(
            repositoryURL: repository.url,
            request: request
        )
        guard let confirmation = preflight.confirmation else {
            throw TestFailure(description: "二进制合并预检应可执行")
        }
        let result = try await historyService.start(
            repositoryURL: repository.url,
            request: request,
            confirmation: confirmation
        )
        try expectEqual(result, .conflicted, "应创建真实二进制冲突")
        return BinaryConflictFixture(
            repository: repository,
            service: GitConflictService(detector: detector),
            path: path
        )
    }
}
