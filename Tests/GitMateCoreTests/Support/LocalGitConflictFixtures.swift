import Foundation
import GitMateCore

struct MergeConflictFixture: Sendable {
    let repository: TemporaryGitRepository
    let service: GitHistoryOperationService
    let detector: GitOperationStateDetector
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
