import Foundation
import Observation

public protocol READMEParsing: Sendable {
    func parse(
        _ markdown: String,
        baseURL: URL?
    ) throws -> READMEDocument
}

extension READMEBlockParser: READMEParsing {}

public struct READMEInlinePresentation: Equatable, Sendable {
    public let plainText: String
    public let externalLinks: [READMEExternalLink]

    public init(content: READMEInlineContent) {
        plainText = content.text
        externalLinks = content.links.compactMap { link in
            RepositoryPresentationSanitizer.remoteURL(link.url).map {
                READMEExternalLink(title: link.title, url: $0)
            }
        }
    }
}

public enum READMELoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case empty
    case failed(message: String)
}

public struct READMEViewState: Equatable, Sendable {
    public var loadPhase: READMELoadPhase
    public var document: READMEDocument?
    public var outline: READMEOutline
    public var repositoryID: Int64?
    public var nonBlockingErrorMessage: String?

    public init(repositoryID: Int64? = nil) {
        loadPhase = .idle
        document = nil
        outline = []
        self.repositoryID = repositoryID
        nonBlockingErrorMessage = nil
    }

    public var retryAction: WorkspaceRetryAction? {
        guard case .failed = loadPhase else {
            return nil
        }
        return WorkspaceRetryAction(
            title: "重试",
            accessibilityLabel: "重新加载 README",
            accessibilityIdentifier: "workspace.repository.readme.retry"
        )
    }
}

@MainActor
@Observable
public final class READMEViewModel {
    public private(set) var state: READMEViewState

    @ObservationIgnored
    private let parser: any READMEParsing

    @ObservationIgnored
    private let source: READMERepositorySource?

    @ObservationIgnored
    private var isLoading = false

    @ObservationIgnored
    private var hasLoadedSuccessfully = false

    public init(parser: any READMEParsing = READMEBlockParser()) {
        self.parser = parser
        source = nil
        state = READMEViewState()
    }

    public init(
        repository: Repository,
        account: GitHubAccount,
        token: String,
        loader: any RepositoryContentLoading,
        parser: any READMEParsing = READMEBlockParser()
    ) {
        self.parser = parser
        source = READMERepositorySource(
            repository: repository,
            account: account,
            token: token,
            loader: loader
        )
        state = READMEViewState(repositoryID: repository.id)
    }

    public func load(
        markdown: String,
        baseURL: URL?
    ) {
        state.loadPhase = .loading
        do {
            let document = try parser.parse(
                markdown,
                baseURL: RepositoryPresentationSanitizer.remoteURL(baseURL)
            )
            apply(document: document)
        } catch {
            state = failedState(
                repositoryID: state.repositoryID,
                message: "暂时无法解析 README，请稍后重试。"
            )
        }
    }

    public func load() async {
        guard let source, !isLoading, !hasLoadedSuccessfully else {
            return
        }

        let stateBeforeLoad = state
        let hasVisibleDocument = state.loadPhase == .loaded
            && state.document != nil
        isLoading = true
        if !hasVisibleDocument {
            state.loadPhase = .loading
        }
        defer { isLoading = false }
        var hasAppliedContent = hasVisibleDocument

        do {
            try Task.checkCancellation()
            for try await update in source.loader.repositoryContentUpdates(
                repository: source.repository,
                account: source.account,
                token: source.token
            ) {
                try Task.checkCancellation()
                let readmeRefreshFailed = update.content.panelErrors.contains {
                    $0.panel == .readme
                }
                if let readme = update.content.readme {
                    let document = try parser.parse(
                        readme.markdown,
                        baseURL: RepositoryPresentationSanitizer.remoteURL(
                            readme.downloadURL
                        )
                    )
                    try Task.checkCancellation()
                    apply(document: document)
                    hasAppliedContent = true
                    if readmeRefreshFailed {
                        state.nonBlockingErrorMessage =
                            "后台刷新失败，已保留缓存内容。"
                    }
                } else if readmeRefreshFailed {
                    if state.document != nil {
                        state.nonBlockingErrorMessage =
                            "后台刷新失败，已保留缓存内容。"
                        hasAppliedContent = true
                    } else {
                        state = failedState(
                            repositoryID: source.repository.id,
                            message: "暂时无法加载 README，请稍后重试。"
                        )
                    }
                } else if update.isFinal {
                    state = READMEViewState(
                        repositoryID: source.repository.id
                    )
                    state.loadPhase = .empty
                    hasAppliedContent = true
                }
                if update.isFinal && !readmeRefreshFailed {
                    hasLoadedSuccessfully = true
                }
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            if !hasAppliedContent {
                state = stateBeforeLoad
            }
        } catch {
            if hasAppliedContent {
                state.nonBlockingErrorMessage =
                    "后台刷新失败，已保留缓存内容。"
            } else {
                state = failedState(
                    repositoryID: source.repository.id,
                    message: "暂时无法加载 README，请稍后重试。"
                )
            }
        }
    }

    private func apply(document: READMEDocument) {
        let sanitized = READMEPresentationSanitizer.sanitize(document)
        guard !sanitized.blocks.isEmpty else {
            let repositoryID = state.repositoryID
            state = READMEViewState(repositoryID: repositoryID)
            state.loadPhase = .empty
            return
        }

        let repositoryID = state.repositoryID
        state = READMEViewState(repositoryID: repositoryID)
        state.loadPhase = .loaded
        state.document = sanitized
        state.outline = sanitized.outline
    }

    private func failedState(
        repositoryID: Int64?,
        message: String
    ) -> READMEViewState {
        var failed = READMEViewState(repositoryID: repositoryID)
        failed.loadPhase = .failed(message: message)
        return failed
    }
}

private struct READMERepositorySource: Sendable {
    let repository: Repository
    let account: GitHubAccount
    let token: String
    let loader: any RepositoryContentLoading
}

enum READMEPresentationSanitizer {
    static func sanitize(_ document: READMEDocument) -> READMEDocument {
        let blocks = document.blocks.compactMap(sanitizedBlock)
        let links = document.links.compactMap(sanitizedLink)
        let outline = blocks.compactMap { block -> READMEOutlineItem? in
            guard case let .heading(level, id, text) = block else {
                return nil
            }
            return READMEOutlineItem(level: level, id: id, title: text)
        }
        return READMEDocument(
            blocks: blocks,
            outline: outline,
            links: links,
            plainText: blocks.compactMap(plainText).joined(separator: "\n")
        )
    }

    private static func sanitizedBlock(
        _ block: READMEBlock
    ) -> READMEBlock? {
        switch block {
        case let .heading(level, id, text):
            return .heading(level: level, id: id, text: text)
        case let .paragraph(content):
            return .paragraph(
                READMEInlineContent(
                    text: content.text,
                    links: content.links.compactMap(sanitizedLink)
                )
            )
        case let .code(language, value):
            return .code(language: language, value: value)
        case let .image(url, alt):
            guard let url = RepositoryPresentationSanitizer.remoteURL(url) else {
                return nil
            }
            return .image(url: url, alt: alt)
        case let .table(headers, rows):
            return .table(headers: headers, rows: rows)
        case let .list(ordered, items):
            return .list(ordered: ordered, items: items)
        case let .quote(value):
            return .quote(value)
        case .divider:
            return .divider
        }
    }

    private static func sanitizedLink(
        _ link: READMEExternalLink
    ) -> READMEExternalLink? {
        RepositoryPresentationSanitizer.remoteURL(link.url).map {
            READMEExternalLink(title: link.title, url: $0)
        }
    }

    private static func plainText(
        _ block: READMEBlock
    ) -> String? {
        switch block {
        case let .heading(_, _, text):
            return text
        case let .paragraph(content):
            return content.text
        case let .code(_, value):
            return value
        case let .image(_, alt):
            return alt.isEmpty ? nil : alt
        case let .table(headers, rows):
            return ([headers] + rows)
                .map { $0.joined(separator: " ") }
                .joined(separator: "\n")
        case let .list(_, items):
            return items.joined(separator: "\n")
        case let .quote(value):
            return value
        case .divider:
            return nil
        }
    }
}
