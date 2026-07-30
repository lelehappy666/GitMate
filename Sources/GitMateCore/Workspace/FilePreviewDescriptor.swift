import Foundation

public enum SourceLanguage: String, Codable, Equatable, Sendable {
    case swift
    case javascript
    case typescript
    case python
    case ruby
    case shell
    case go
    case rust
    case kotlin
    case java
    case c
    case cpp
    case csharp
    case php
    case lua
    case sql
    case yaml
    case json
    case xml
    case css
    case markdown
}

public enum FilePreviewKind: Equatable, Sendable {
    case source(SourceLanguage?)
    case markdown
    case html
    case rasterImage
    case vectorImage
    case pdf
    case unsupportedBinary
    case invalidText
}

public struct FilePreviewDocument: Equatable, Sendable {
    public let path: String
    public let data: Data
    public let text: String?
    public let kind: FilePreviewKind
    public let byteCount: Int
    public let baseURL: URL?

    public init(
        path: String,
        data: Data,
        text: String?,
        kind: FilePreviewKind,
        byteCount: Int,
        baseURL: URL? = nil
    ) {
        self.path = path
        self.data = data
        self.text = text
        self.kind = kind
        self.byteCount = max(byteCount, 0)
        self.baseURL = baseURL
    }
}

public enum FilePreviewPolicy {
    public static let sourceMaximumBytes = 2 * 1_024 * 1_024
    public static let imageMaximumBytes = 25 * 1_024 * 1_024
    public static let pdfMaximumBytes = 50 * 1_024 * 1_024

    public static func maximumBytes(for path: String) -> Int {
        let ext = URL(fileURLWithPath: path)
            .pathExtension
            .lowercased()
        if ext == "pdf" {
            return pdfMaximumBytes
        }
        if imageExtensions.contains(ext) {
            return imageMaximumBytes
        }
        return sourceMaximumBytes
    }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tif", "tiff", "bmp",
        "heic", "heif", "webp", "svg"
    ]
}

public enum FilePreviewClassifier {
    public static func classify(
        path: String,
        data: Data,
        decodedText: String?,
        baseURL: URL? = nil
    ) -> FilePreviewDocument {
        let kind: FilePreviewKind
        if isPDF(data) {
            kind = .pdf
        } else if isRasterImage(data) {
            kind = .rasterImage
        } else if let decodedText {
            if isSVG(path: path, text: decodedText) {
                kind = .vectorImage
            } else if isHTML(path: path, text: decodedText) {
                kind = .html
            } else if language(for: path) == .markdown {
                kind = .markdown
            } else {
                kind = .source(language(for: path))
            }
        } else if isKnownTextPath(path) {
            kind = .invalidText
        } else {
            kind = .unsupportedBinary
        }

        return FilePreviewDocument(
            path: path,
            data: data,
            text: decodedText,
            kind: kind,
            byteCount: data.count,
            baseURL: baseURL
        )
    }

    public static func language(for path: String) -> SourceLanguage? {
        let ext = URL(fileURLWithPath: path)
            .pathExtension
            .lowercased()
        return languagesByExtension[ext]
    }

    private static func isPDF(_ data: Data) -> Bool {
        data.starts(with: Array("%PDF-".utf8))
    }

    private static func isRasterImage(_ data: Data) -> Bool {
        if data.starts(with: [
            0x89, 0x50, 0x4E, 0x47,
            0x0D, 0x0A, 0x1A, 0x0A
        ]) {
            return true
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF])
            || data.starts(with: Array("GIF87a".utf8))
            || data.starts(with: Array("GIF89a".utf8))
            || data.starts(with: [0x49, 0x49, 0x2A, 0x00])
            || data.starts(with: [0x4D, 0x4D, 0x00, 0x2A])
            || data.starts(with: [0x42, 0x4D]) {
            return true
        }
        if data.count >= 12,
           String(data: data.prefix(4), encoding: .ascii) == "RIFF",
           String(
               data: data.dropFirst(8).prefix(4),
               encoding: .ascii
           ) == "WEBP" {
            return true
        }
        if data.count >= 12,
           String(
               data: data.dropFirst(4).prefix(4),
               encoding: .ascii
           ) == "ftyp",
           let brand = String(
               data: data.dropFirst(8).prefix(4),
               encoding: .ascii
           )?.lowercased(),
           heifBrands.contains(brand) {
            return true
        }
        return false
    }

    private static func isSVG(path: String, text: String) -> Bool {
        let ext = URL(fileURLWithPath: path)
            .pathExtension
            .lowercased()
        let prefix = String(text.prefix(2_048))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return (ext == "svg" || prefix.hasPrefix("<svg")
            || prefix.hasPrefix("<?xml"))
            && prefix.contains("<svg")
    }

    private static func isHTML(path: String, text: String) -> Bool {
        let ext = URL(fileURLWithPath: path)
            .pathExtension
            .lowercased()
        let prefix = String(text.prefix(2_048))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return htmlExtensions.contains(ext)
            || prefix.hasPrefix("<!doctype html")
            || prefix.hasPrefix("<html")
    }

    private static func isKnownTextPath(_ path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        let ext = URL(fileURLWithPath: path)
            .pathExtension
            .lowercased()
        return textExtensions.contains(ext)
            || textFilenames.contains(name)
    }

    private static let htmlExtensions: Set<String> = [
        "html", "htm", "xhtml"
    ]

    private static let textFilenames: Set<String> = [
        "makefile", "dockerfile", "gemfile", "podfile",
        "license", "readme", ".gitignore", ".gitattributes"
    ]

    private static let textExtensions: Set<String> =
        Set(languagesByExtension.keys)
        .union([
            "txt", "text", "log", "csv", "tsv", "toml",
            "ini", "conf", "config", "env", "properties"
        ])
        .union(htmlExtensions)
        .union(["svg"])

    private static let heifBrands: Set<String> = [
        "heic", "heix", "hevc", "hevx", "heim", "heis",
        "mif1", "msf1", "avif"
    ]

    private static let languagesByExtension: [String: SourceLanguage] = [
        "swift": .swift,
        "js": .javascript,
        "jsx": .javascript,
        "mjs": .javascript,
        "cjs": .javascript,
        "ts": .typescript,
        "tsx": .typescript,
        "py": .python,
        "pyw": .python,
        "rb": .ruby,
        "sh": .shell,
        "bash": .shell,
        "zsh": .shell,
        "fish": .shell,
        "go": .go,
        "rs": .rust,
        "kt": .kotlin,
        "kts": .kotlin,
        "java": .java,
        "c": .c,
        "h": .c,
        "m": .c,
        "mm": .cpp,
        "cc": .cpp,
        "cpp": .cpp,
        "cxx": .cpp,
        "hpp": .cpp,
        "cs": .csharp,
        "php": .php,
        "lua": .lua,
        "sql": .sql,
        "yaml": .yaml,
        "yml": .yaml,
        "json": .json,
        "jsonc": .json,
        "xml": .xml,
        "plist": .xml,
        "css": .css,
        "scss": .css,
        "sass": .css,
        "less": .css,
        "md": .markdown,
        "markdown": .markdown,
        "mdown": .markdown
    ]
}

public enum HTMLPreviewSecurityPolicy {
    public static func allowsNavigation(to url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else {
            return false
        }
        return [
            "about",
            "data",
            "blob",
            "file",
            "http",
            "https",
        ].contains(scheme)
    }
}

public enum SourcePreviewLayoutPolicy {
    public static func minimumContentWidth(
        viewportWidth: Double,
        horizontalPadding: Double
    ) -> Double {
        guard viewportWidth.isFinite, horizontalPadding.isFinite else {
            return 0
        }
        return max(viewportWidth - max(horizontalPadding, 0), 0)
    }

}
