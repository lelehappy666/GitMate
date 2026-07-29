import Foundation

public struct RepositoryCoverExtractor: Sendable {
    private let blockedHosts = [
        "img.shields.io",
        "badge.fury.io",
        "coveralls.io",
        "codecov.io"
    ]

    public init() {}

    public func firstCandidate(
        markdown: String,
        baseURL: URL?
    ) -> RepositoryCoverCandidate? {
        let safeMarkdown = markdownForExtraction(from: markdown)
        for line in safeMarkdown.components(separatedBy: .newlines) {
            if let candidate = markdownCandidate(from: line, baseURL: baseURL),
               isAllowed(candidate) {
                return candidate
            }
            if let candidate = htmlCandidate(from: line, baseURL: baseURL),
               isAllowed(candidate) {
                return candidate
            }
        }
        return nil
    }

    private func markdownForExtraction(from markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        var safeLines: [String] = []
        var fence: (character: Character, count: Int)?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let currentFence = fence {
                let count = trimmed.prefix {
                    $0 == currentFence.character
                }.count
                if count >= currentFence.count,
                   trimmed.dropFirst(count)
                    .trimmingCharacters(in: .whitespaces)
                    .isEmpty {
                    fence = nil
                }
                continue
            }

            if let character = trimmed.first,
               character == "`" || character == "~" {
                let count = trimmed.prefix { $0 == character }.count
                if count >= 3 {
                    fence = (character, count)
                    continue
                }
            }
            safeLines.append(line)
        }

        var result = safeLines.joined(separator: "\n")
        result = result.replacingMatches(
            pattern: #"(?is)<!--.*?-->"#,
            with: ""
        )
        result = result.replacingMatches(
            pattern: #"(?is)<\s*(script|iframe|object)\b[^>]*>.*?<\s*/\s*\1\s*>"#,
            with: ""
        )
        result = result.replacingMatches(
            pattern: #"(?is)<\s*(script|iframe|object)\b[^>]*>.*\z"#,
            with: ""
        )
        return result.replacingMatches(
            pattern: #"(?is)<\s*/?\s*(script|iframe|object)\b[^>]*?/?>"#,
            with: ""
        )
    }

    private func markdownCandidate(
        from line: String,
        baseURL: URL?
    ) -> RepositoryCoverCandidate? {
        guard let match = line.firstMatch(
            pattern: #"!\[([^\]]*)\]\(([^)\s]+)"#,
            captureCount: 2
        ),
        let url = resolvedURL(match[1], baseURL: baseURL)
        else {
            return nil
        }
        return RepositoryCoverCandidate(url: url, alt: match[0])
    }

    private func htmlCandidate(
        from line: String,
        baseURL: URL?
    ) -> RepositoryCoverCandidate? {
        guard let tag = line.firstMatch(
            pattern: #"(?i)<img\b([^>]*)>"#,
            captureCount: 1
        )?.first,
        let source = attribute("src", in: tag),
        let url = resolvedURL(source, baseURL: baseURL)
        else {
            return nil
        }

        return RepositoryCoverCandidate(
            url: url,
            alt: attribute("alt", in: tag) ?? "",
            declaredWidth: dimension(attribute("width", in: tag)),
            declaredHeight: dimension(attribute("height", in: tag))
        )
    }

    private func dimension(_ value: String?) -> Int? {
        guard let value,
              let digits = value.firstMatch(
                pattern: #"^\s*(\d+)(?:px)?\s*$"#,
                captureCount: 1
              )?.first
        else {
            return nil
        }
        return Int(digits)
    }

    private func attribute(_ name: String, in attributes: String) -> String? {
        attributes.firstMatch(
            pattern: #"(?i)(?:^|\s)"# + NSRegularExpression.escapedPattern(
                for: name
            ) + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
            captureCount: 3,
            preservingMissingCaptures: true
        )?
        .first { !$0.isEmpty }
    }

    private func resolvedURL(_ value: String, baseURL: URL?) -> URL? {
        let url = URL(string: value, relativeTo: baseURL)?.absoluteURL
        guard let url,
              ["http", "https"].contains(url.scheme?.lowercased())
        else {
            return nil
        }
        return url
    }

    private func isAllowed(_ candidate: RepositoryCoverCandidate) -> Bool {
        let host = candidate.url.host?.lowercased() ?? ""
        guard !blockedHosts.contains(where: {
            host == $0 || host.hasSuffix(".\($0)")
        }) else {
            return false
        }

        let fileName = candidate.url.lastPathComponent.lowercased()
        guard !["badge", "status", "icon"].contains(where: fileName.contains),
              candidate.url.pathExtension.lowercased() != "svg",
              candidate.declaredWidth.map({ $0 >= 240 }) ?? true,
              candidate.declaredHeight.map({ $0 >= 240 }) ?? true
        else {
            return false
        }
        return true
    }
}

private extension String {
    func replacingMatches(pattern: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return self
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        return expression.stringByReplacingMatches(
            in: self,
            range: range,
            withTemplate: replacement
        )
    }

    func firstMatch(
        pattern: String,
        captureCount: Int,
        preservingMissingCaptures: Bool = false
    ) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let searchRange = NSRange(startIndex..<endIndex, in: self)
        guard let result = expression.firstMatch(in: self, range: searchRange),
              result.numberOfRanges > captureCount
        else {
            return nil
        }

        return (1...captureCount).compactMap { index in
            guard result.range(at: index).location != NSNotFound,
                  let range = Range(result.range(at: index), in: self)
            else {
                return preservingMissingCaptures ? "" : nil
            }
            return String(self[range])
        }
    }
}
