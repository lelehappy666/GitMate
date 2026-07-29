import Foundation
import Observation

@MainActor
@Observable
public final class CommitComposerViewModel {
    public var title = ""
    public var body = ""
    public private(set) var identity: CommitIdentity?
    public private(set) var signingState: CommitSigningState = .disabled
    public private(set) var result: CommitResult?
    public private(set) var error: LocalGitUserFacingError?
    public private(set) var isCommitting = false

    private let repositoryURL: URL
    private let service: any GitCommitServicing

    public init(
        repositoryURL: URL,
        service: any GitCommitServicing
    ) {
        self.repositoryURL = repositoryURL
        self.service = service
    }

    public func loadContext() async {
        do {
            identity = try await service.identity(
                repositoryURL: repositoryURL
            )
            signingState = try await service.signingState(
                repositoryURL: repositoryURL
            )
            error = nil
        } catch {
            self.error = userFacingError(error)
        }
    }

    public func commit() async {
        isCommitting = true
        error = nil
        defer {
            isCommitting = false
        }

        do {
            let result = try await service.commit(
                repositoryURL: repositoryURL,
                message: CommitMessage(title: title, body: body),
                signing: .followGitConfiguration
            )
            self.result = result
            title = ""
            body = ""
        } catch {
            self.error = userFacingError(error)
        }
    }

    private func userFacingError(_ error: Error) -> LocalGitUserFacingError {
        switch error {
        case let LocalGitError.hookFailed(message):
            return LocalGitUserFacingError(
                message: GitOutputRedactor.redact(message),
                recoverySuggestion: "修复 Hook 报告的问题后重试。"
            )
        case let LocalGitError.signingFailed(message):
            return LocalGitUserFacingError(
                message: GitOutputRedactor.redact(message),
                recoverySuggestion: "请检查当前仓库的签名配置。"
            )
        case LocalGitError.emptyIndex:
            return LocalGitUserFacingError(
                message: "暂存区没有可提交的变更。",
                recoverySuggestion: "请先暂存文件或代码块。"
            )
        case LocalGitError.emptyCommitMessage:
            return LocalGitUserFacingError(
                message: "提交标题不能为空。",
                recoverySuggestion: nil
            )
        default:
            return LocalGitUserFacingError(
                message: GitOutputRedactor.redact(
                    error.localizedDescription
                ),
                recoverySuggestion: "请刷新仓库状态后重试。"
            )
        }
    }
}
