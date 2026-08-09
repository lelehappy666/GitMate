import Foundation

public struct READMEBlockParser: Sendable {
    public init() {}

    public func parse(
        _ markdown: String,
        baseURL: URL? = nil
    ) -> READMEDocument {
        let sanitized = READMEHTMLSanitizer().sanitize(markdown)
        let lines = sanitized.markdown.components(separatedBy: .newlines)
        var blocks: [READMEBlock] = []
        var outline: READMEOutline = []
        var links: [READMEExternalLink] = []
        var headingCounts: [String: Int] = [:]
        var paragraphLines: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let parsedLines = paragraphLines.map(parseInline)
                .filter { !$0.text.isEmpty || !$0.links.isEmpty }
            paragraphLines.removeAll(keepingCapacity: true)
            guard !parsedLines.isEmpty else { return }
            blocks.append(
                .paragraph(
                    READMEInlineContent(
                        text: parsedLines.map(\.text).joined(separator: "\n"),
                        links: parsedLines.flatMap(\.links)
                    )
                )
            )
            links.append(contentsOf: parsedLines.flatMap(\.links))
        }

        while index < lines.count {
            let rawLine = lines[index]
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let code = sanitized.codeBlocks[line] {
                flushParagraph()
                blocks.append(.code(language: code.language, value: code.value))
                index += 1
                continue
            }

            if let htmlImage = sanitized.htmlImages[line] {
                flushParagraph()
                if let candidate = htmlImageCandidate(
                    from: htmlImage,
                    baseURL: baseURL
                ) {
                    blocks.append(
                        .image(url: candidate.url, alt: candidate.alt)
                    )
                }
                index += 1
                continue
            }

            if let heading = heading(from: line) {
                flushParagraph()
                let parsed = parseInline(heading.text)
                let baseID = headingID(for: parsed.text)
                let count = (headingCounts[baseID] ?? 0) + 1
                headingCounts[baseID] = count
                let id = count == 1 ? baseID : "\(baseID)-\(count)"
                blocks.append(
                    .heading(level: heading.level, id: id, text: parsed.text)
                )
                outline.append(
                    READMEOutlineItem(
                        level: heading.level,
                        id: id,
                        title: parsed.text
                    )
                )
                links.append(contentsOf: parsed.links)
                index += 1
                continue
            }

            if isDivider(line) {
                flushParagraph()
                blocks.append(.divider)
                index += 1
                continue
            }

            if index + 1 < lines.count,
               let headers = tableCells(from: line),
               isTableSeparator(lines[index + 1]),
               !headers.isEmpty {
                flushParagraph()
                var rows: [[String]] = []
                index += 2
                while index < lines.count,
                      let cells = tableCells(from: lines[index]),
                      !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(cells.map { parseInline($0).text })
                    index += 1
                }
                blocks.append(
                    .table(
                        headers: headers.map { parseInline($0).text },
                        rows: rows
                    )
                )
                continue
            }

            if let firstItem = listItem(from: rawLine) {
                flushParagraph()
                var items = [parseInline(firstItem.text)]
                let ordered = firstItem.ordered
                index += 1
                while index < lines.count,
                      let item = listItem(from: lines[index]),
                      item.ordered == ordered {
                    items.append(parseInline(item.text))
                    index += 1
                }
                blocks.append(
                    .list(ordered: ordered, items: items.map(\.text))
                )
                links.append(contentsOf: items.flatMap(\.links))
                continue
            }

            if line.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [InlineResult] = []
                while index < lines.count {
                    let quoteLine = lines[index]
                        .trimmingCharacters(in: .whitespaces)
                    guard quoteLine.hasPrefix(">") else { break }
                    quoteLines.append(
                        parseInline(
                            String(quoteLine.dropFirst())
                                .trimmingCharacters(in: .whitespaces)
                        )
                    )
                    index += 1
                }
                blocks.append(
                    .quote(quoteLines.map(\.text).joined(separator: "\n"))
                )
                links.append(contentsOf: quoteLines.flatMap(\.links))
                continue
            }

            if let image = image(from: line, baseURL: baseURL) {
                flushParagraph()
                if let candidate = image.candidate {
                    blocks.append(
                        .image(url: candidate.url, alt: candidate.alt)
                    )
                }
                index += 1
                continue
            }

            paragraphLines.append(line)
            index += 1
        }

        flushParagraph()
        return READMEDocument(
            blocks: blocks,
            outline: outline,
            links: links,
            plainText: blocks.compactMap(plainText).joined(separator: "\n")
        )
    }

    private func heading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count),
              line.dropFirst(hashes.count).first == " "
        else {
            return nil
        }
        let text = line.dropFirst(hashes.count + 1)
            .trimmingCharacters(in: .whitespaces)
            .replacingMatches(pattern: #"\s+#+\s*$"#, with: "")
        return (hashes.count, text)
    }

    private func headingID(for title: String) -> String {
        var result = ""
        var pendingDash = false
        for scalar in title.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                if pendingDash, !result.isEmpty {
                    result.append("-")
                }
                result.unicodeScalars.append(scalar)
                pendingDash = false
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar)
                        || scalar == "-" {
                pendingDash = !result.isEmpty
            }
        }
        return result.isEmpty ? "section" : result
    }

    private func isDivider(_ line: String) -> Bool {
        line.range(
            of: #"^(?:\*\s*){3,}$|^(?:-\s*){3,}$|^(?:_\s*){3,}$"#,
            options: .regularExpression
        ) != nil
    }

    private func tableCells(from line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        let withoutEdges = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        return withoutEdges.split(
            separator: "|",
            omittingEmptySubsequences: false
        )
        .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func isTableSeparator(_ line: String) -> Bool {
        guard let cells = tableCells(from: line), !cells.isEmpty else {
            return false
        }
        return cells.allSatisfy {
            $0.range(
                of: #"^:?-{3,}:?$"#,
                options: .regularExpression
            ) != nil
        }
    }

    private func listItem(
        from line: String
    ) -> (ordered: Bool, text: String)? {
        if let match = line.firstMatch(
            pattern: #"^\s*[-+*]\s+(.+)$"#,
            captureCount: 1
        ) {
            return (false, match[0])
        }
        if let match = line.firstMatch(
            pattern: #"^\s*\d+[.)]\s+(.+)$"#,
            captureCount: 1
        ) {
            return (true, match[0])
        }
        return nil
    }

    private func htmlImageCandidate(
        from tag: String,
        baseURL: URL?
    ) -> RepositoryCoverCandidate? {
        attribute("src", in: tag)
            .flatMap { safeURL($0, baseURL: baseURL) }
            .map {
                RepositoryCoverCandidate(
                    url: $0,
                    alt: attribute("alt", in: tag) ?? ""
                )
            }
    }

    private func image(
        from line: String,
        baseURL: URL?
    ) -> RecognizedImage? {
        if let match = line.firstMatch(
            pattern: #"^\s*!\[([^\]]*)\]\((.*)\)\s*$"#,
            captureCount: 2
        ) {
            let destination = linkDestination(from: match[1])
            let candidate = safeURL(destination, baseURL: baseURL).map {
                RepositoryCoverCandidate(url: $0, alt: match[0])
            }
            return RecognizedImage(candidate: candidate)
        }

        return nil
    }

    private func attribute(_ name: String, in attributes: String) -> String? {
        attributes.firstMatch(
            pattern: #"(?i)(?:^|\s)"#
                + NSRegularExpression.escapedPattern(for: name)
                + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
            captureCount: 3,
            preservingMissingCaptures: true
        )?
        .first { !$0.isEmpty }
    }

    private func parseInline(_ input: String) -> InlineResult {
        let input = input.replacingMatches(
            pattern: #"(?is)<(?!img\b)[^>]+>"#,
            with: ""
        )
        var output = ""
        var links: [READMEExternalLink] = []
        var cursor = input.startIndex

        while cursor < input.endIndex {
            guard input[cursor] == "[",
                  cursor == input.startIndex
                    || input[input.index(before: cursor)] != "!",
                  let closeBracket = input[cursor...].firstIndex(of: "]"),
                  input.index(after: closeBracket) < input.endIndex,
                  input[input.index(after: closeBracket)] == "("
            else {
                output.append(input[cursor])
                cursor = input.index(after: cursor)
                continue
            }

            let destinationStart = input.index(closeBracket, offsetBy: 2)
            var destinationEnd = destinationStart
            var depth = 0
            var foundEnd: String.Index?
            while destinationEnd < input.endIndex {
                let character = input[destinationEnd]
                if character == "(" {
                    depth += 1
                } else if character == ")" {
                    if depth == 0 {
                        foundEnd = destinationEnd
                        break
                    }
                    depth -= 1
                }
                destinationEnd = input.index(after: destinationEnd)
            }

            guard let foundEnd else {
                output.append(input[cursor])
                cursor = input.index(after: cursor)
                continue
            }

            let label = String(
                input[input.index(after: cursor)..<closeBracket]
            )
            let rawDestination = String(input[destinationStart..<foundEnd])
            output.append(label)
            let destination = linkDestination(from: rawDestination)
            if let url = safeExternalURL(destination) {
                links.append(READMEExternalLink(title: label, url: url))
            }
            cursor = input.index(after: foundEnd)
        }

        return InlineResult(text: output, links: links)
    }

    private func linkDestination(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("<"), let closing = trimmed.firstIndex(of: ">") {
            return String(trimmed[trimmed.index(after: trimmed.startIndex)..<closing])
        }
        return trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init)
            ?? ""
    }

    private func safeExternalURL(_ value: String) -> URL? {
        READMEURLPolicy.resolvedRemoteURL(value, baseURL: nil)
    }

    private func safeURL(_ value: String, baseURL: URL?) -> URL? {
        READMEURLPolicy.resolvedRemoteURL(value, baseURL: baseURL)
    }

    private func plainText(for block: READMEBlock) -> String? {
        switch block {
        case let .heading(_, _, text):
            text
        case let .paragraph(content):
            content.text
        case let .code(_, value):
            value
        case let .image(_, alt):
            alt.isEmpty ? nil : alt
        case let .table(headers, rows):
            ([headers] + rows).map { $0.joined(separator: " ") }
                .joined(separator: "\n")
        case let .list(_, items):
            items.joined(separator: "\n")
        case let .quote(value):
            value
        case .divider:
            nil
        }
    }
}

private struct InlineResult {
    let text: String
    let links: [READMEExternalLink]
}

private struct RecognizedImage {
    let candidate: RepositoryCoverCandidate?
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
