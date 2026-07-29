import Foundation

public struct READMEExternalLink: Equatable, Sendable {
    public let title: String
    public let url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

public struct READMEInlineContent: Equatable, Sendable {
    public let text: String
    public let links: [READMEExternalLink]

    public init(text: String, links: [READMEExternalLink] = []) {
        self.text = text
        self.links = links
    }
}

public struct READMEOutlineItem: Equatable, Sendable {
    public let level: Int
    public let id: String
    public let title: String

    public init(level: Int, id: String, title: String) {
        self.level = level
        self.id = id
        self.title = title
    }
}

public typealias READMEOutline = [READMEOutlineItem]

public enum READMEBlock: Equatable, Sendable {
    case heading(level: Int, id: String, text: String)
    case paragraph(READMEInlineContent)
    case code(language: String?, value: String)
    case image(url: URL, alt: String)
    case table(headers: [String], rows: [[String]])
    case list(ordered: Bool, items: [String])
    case quote(String)
    case divider
}

public struct READMEDocument: Equatable, Sendable {
    public let blocks: [READMEBlock]
    public let outline: READMEOutline
    public let links: [READMEExternalLink]
    public let plainText: String

    public init(
        blocks: [READMEBlock],
        outline: READMEOutline,
        links: [READMEExternalLink],
        plainText: String
    ) {
        self.blocks = blocks
        self.outline = outline
        self.links = links
        self.plainText = plainText
    }
}

public struct RepositoryCoverCandidate: Equatable, Sendable {
    public let url: URL
    public let alt: String
    public let declaredWidth: Int?
    public let declaredHeight: Int?

    public init(
        url: URL,
        alt: String,
        declaredWidth: Int? = nil,
        declaredHeight: Int? = nil
    ) {
        self.url = url
        self.alt = alt
        self.declaredWidth = declaredWidth
        self.declaredHeight = declaredHeight
    }
}
