import Foundation
import Observation

@MainActor
@Observable
public final class RemoteTransferViewModel {
    public var remote = "origin"
    public var branch = "main"
    public var pushMode: PushMode = .normal
    public private(set) var plan: GitTransferPlan?
    public private(set) var events: [GitTransferEvent] = []
    public private(set) var isRunning = false
    public private(set) var shouldShowConflicts = false
    public private(set) var error: LocalGitUserFacingError?

    private let repositoryURL: URL
    private let context: GitCredentialContext
    private let service: any GitTransferServicing
    private var transferTask: Task<Void, Never>?

    public init(
        repositoryURL: URL,
        context: GitCredentialContext,
        service: any GitTransferServicing
    ) {
        self.repositoryURL = repositoryURL
        self.context = context
        self.service = service
    }

    public func planPull() async {
        await makePlan {
            try await service.planPull(
                repositoryURL: repositoryURL,
                remote: remote,
                branch: branch
            )
        }
    }

    public func planPush() async {
        await makePlan {
            try await service.planPush(
                repositoryURL: repositoryURL,
                remote: remote,
                branch: branch,
                mode: pushMode
            )
        }
    }

    public func fetch() {
        run(
            service.fetch(
                repositoryURL: repositoryURL,
                remote: remote,
                context: context
            )
        )
    }

    public func executePlan() {
        guard let plan,
              let confirmation = plan.confirmation
        else {
            return
        }
        switch plan.operation {
        case .pull:
            run(
                service.pull(
                    repositoryURL: repositoryURL,
                    plan: plan,
                    context: context,
                    confirmation: confirmation
                )
            )
        case .push:
            run(
                service.push(
                    repositoryURL: repositoryURL,
                    plan: plan,
                    context: context,
                    confirmation: confirmation
                )
            )
        case .fetch:
            fetch()
        }
    }

    public func cancel() {
        transferTask?.cancel()
    }

    public func consumeConflictRoute() {
        shouldShowConflicts = false
    }

    private func makePlan(
        _ operation: () async throws -> GitTransferPlan
    ) async {
        error = nil
        do {
            plan = try await operation()
        } catch {
            present(error)
        }
    }

    private func run(
        _ stream: AsyncThrowingStream<GitTransferEvent, Error>
    ) {
        transferTask?.cancel()
        events = []
        isRunning = true
        error = nil
        transferTask = Task {
            do {
                for try await event in stream {
                    events.append(event)
                    if event.phase == .conflicted {
                        shouldShowConflicts = true
                    }
                }
            } catch GitCommandError.cancelled {
            } catch {
                present(error)
            }
            isRunning = false
        }
    }

    private func present(_ error: Error) {
        self.error = LocalGitUserFacingError(
            message: GitOutputRedactor.redact(error.localizedDescription),
            recoverySuggestion: "检查网络、认证和远程分支状态后重试。"
        )
    }
}
