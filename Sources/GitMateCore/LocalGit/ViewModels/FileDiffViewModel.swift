import Foundation
import Observation

@MainActor
@Observable
public final class FileDiffViewModel {
    public private(set) var selectedPath: String?
    public private(set) var source: GitDiffSource = .workingTree
    public private(set) var document: GitDiffDocument?
    public private(set) var isLoading = false
    public private(set) var error: LocalGitUserFacingError?
    public var options = GitDiffOptions.default

    private let repositoryURL: URL
    private let service: any GitDiffServicing
    private var selectionGeneration: UInt64 = 0
    private var loadTask: Task<Void, Never>?

    public init(
        repositoryURL: URL,
        service: any GitDiffServicing
    ) {
        self.repositoryURL = repositoryURL
        self.service = service
    }

    public func select(
        path: String,
        source: GitDiffSource
    ) async {
        loadTask?.cancel()
        selectionGeneration &+= 1
        let generation = selectionGeneration
        selectedPath = path
        self.source = source
        isLoading = true
        error = nil

        let service = service
        let repositoryURL = repositoryURL
        let options = options
        let task = Task {
            do {
                let document = try await service.diff(
                    repositoryURL: repositoryURL,
                    path: path,
                    source: source,
                    options: options
                )
                guard generation == selectionGeneration,
                      !Task.isCancelled
                else {
                    return
                }
                self.document = document
                self.isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard generation == selectionGeneration else {
                    return
                }
                self.error = LocalGitUserFacingError(
                    message: GitOutputRedactor.redact(
                        error.localizedDescription
                    ),
                    recoverySuggestion: "请重新选择文件。"
                )
                self.isLoading = false
            }
        }
        loadTask = task
        await task.value
    }

    public func reload() async {
        guard let selectedPath else {
            return
        }
        await select(path: selectedPath, source: source)
    }

    public func clear() {
        loadTask?.cancel()
        selectionGeneration &+= 1
        selectedPath = nil
        document = nil
        isLoading = false
        error = nil
    }
}
