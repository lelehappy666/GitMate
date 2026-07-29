import Foundation
import Observation

@MainActor
@Observable
public final class ConflictResolutionViewModel {
    public private(set) var files: [GitConflictFile] = []
    public private(set) var selectedPath: String?
    public private(set) var document: GitConflictDocument?
    public private(set) var isLoading = false
    public private(set) var error: LocalGitUserFacingError?
    public var resultText = ""

    private let repositoryURL: URL
    private let service: any GitConflictServicing
    private var selectionGeneration: UInt64 = 0

    public init(
        repositoryURL: URL,
        service: any GitConflictServicing
    ) {
        self.repositoryURL = repositoryURL
        self.service = service
    }

    public func refresh() async {
        isLoading = true
        error = nil
        do {
            files = try await service.files(repositoryURL: repositoryURL)
            if let selectedPath,
               !files.contains(where: { $0.path == selectedPath }) {
                self.selectedPath = nil
                document = nil
                resultText = ""
            }
        } catch {
            present(error)
        }
        isLoading = false
    }

    public func select(path: String) async {
        selectionGeneration &+= 1
        let generation = selectionGeneration
        selectedPath = path
        isLoading = true
        error = nil
        do {
            let document = try await service.document(
                repositoryURL: repositoryURL,
                path: path
            )
            guard generation == selectionGeneration else {
                return
            }
            self.document = document
            resultText = document.currentText ?? ""
        } catch {
            guard generation == selectionGeneration else {
                return
            }
            present(error)
        }
        isLoading = false
    }

    public func adoptCurrent() {
        resultText = document?.currentText ?? ""
    }

    public func adoptIncoming() {
        resultText = document?.incomingText ?? ""
    }

    public func keepBoth() {
        resultText = [
            document?.currentText,
            document?.incomingText
        ].compactMap { $0 }.joined(separator: "\n")
    }

    public func saveText() async {
        guard let selectedPath else {
            return
        }
        isLoading = true
        do {
            try await service.saveTextResult(
                repositoryURL: repositoryURL,
                path: selectedPath,
                text: resultText
            )
            await refresh()
        } catch {
            present(error)
        }
        isLoading = false
    }

    public func chooseWholeFile(
        side: ConflictSide,
        confirmation: RiskConfirmation
    ) async {
        guard let selectedPath else {
            return
        }
        isLoading = true
        do {
            try await service.chooseWholeFile(
                repositoryURL: repositoryURL,
                path: selectedPath,
                side: side,
                confirmation: confirmation
            )
            await refresh()
        } catch {
            present(error)
        }
        isLoading = false
    }

    private func present(_ error: Error) {
        self.error = LocalGitUserFacingError(
            message: GitOutputRedactor.redact(error.localizedDescription),
            recoverySuggestion: "重新读取冲突文件后再试。"
        )
    }
}
