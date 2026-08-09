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
        let sanitized = READMEHTMLSanitizer().sanitize(markdown)
        for source in candidateSources(in: sanitized) {
            let candidate: RepositoryCoverCandidate?
            switch source.value {
            case let .markdown(alt, destination):
                candidate = markdownCandidate(
                    alt: alt,
                    destination: destination,
                    baseURL: baseURL
                )
            case let .html(tag):
                candidate = htmlCandidate(from: tag, baseURL: baseURL)
            }
            if let candidate, isAllowed(candidate) {
                return candidate
            }
        }
        return nil
    }

    private func candidateSources(
        in sanitized: READMESanitizedContent
    ) -> [LocatedCoverSource] {
        var sources: [LocatedCoverSource] = []
        if let expression = try? NSRegularExpression(
            pattern: #"!\[([^\]]*)\]\(\s*(<[^>\n]+>|[^\s)]+)(?:\s+[^)]*)?\s*\)"#
        ) {
            let range = NSRange(
                sanitized.markdown.startIndex..<sanitized.markdown.endIndex,
                in: sanitized.markdown
            )
            for match in expression.matches(
                in: sanitized.markdown,
                range: range
            ) {
                guard let altRange = Range(
                    match.range(at: 1),
                    in: sanitized.markdown
                ),
                let destinationRange = Range(
                    match.range(at: 2),
                    in: sanitized.markdown
                ) else {
                    continue
                }
                sources.append(
                    LocatedCoverSource(
                        location: match.range.location,
                        value: .markdown(
                            alt: String(sanitized.markdown[altRange]),
                            destination: String(
                                sanitized.markdown[destinationRange]
                            )
                        )
                    )
                )
            }
        }

        for (placeholder, tag) in sanitized.htmlImages {
            guard let range = sanitized.markdown.range(of: placeholder) else {
                continue
            }
            sources.append(
                LocatedCoverSource(
                    location: NSRange(range, in: sanitized.markdown).location,
                    value: .html(tag: tag)
                )
            )
        }
        return sources.sorted { $0.location < $1.location }
    }

    private func markdownCandidate(
        alt: String,
        destination: String,
        baseURL: URL?
    ) -> RepositoryCoverCandidate? {
        var destination = destination
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if destination.hasPrefix("<"), destination.hasSuffix(">") {
            destination.removeFirst()
            destination.removeLast()
        }
        guard let url = resolvedURL(destination, baseURL: baseURL) else {
            return nil
        }
        return RepositoryCoverCandidate(url: url, alt: alt)
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
        READMEURLPolicy.resolvedRemoteURL(value, baseURL: baseURL)
    }

    private func isAllowed(_ candidate: RepositoryCoverCandidate) -> Bool {
        guard let host = READMEURLPolicy.normalizedHost(candidate.url) else {
            return false
        }
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

private struct LocatedCoverSource {
    let location: Int
    let value: CoverSource
}

private enum CoverSource {
    case markdown(alt: String, destination: String)
    case html(tag: String)
}

private extension String {
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
