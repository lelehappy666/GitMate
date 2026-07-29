import Foundation

struct READMESanitizedContent {
    let markdown: String
    let codeBlocks: [String: READMEFencedCode]
    let htmlImages: [String: String]
}

struct READMEFencedCode {
    let language: String?
    let value: String
}

struct READMEHTMLSanitizer {
    private let dangerousContainerNames = ["script", "iframe", "object"]

    func sanitize(_ markdown: String) -> READMESanitizedContent {
        let protected = protectFencedCode(in: markdown)
        var output = ""
        var htmlImages: [String: String] = [:]
        var index = protected.markdown.startIndex
        var dangerousContainer: String?

        while index < protected.markdown.endIndex {
            if let activeContainer = dangerousContainer {
                if protected.markdown[index] == "<",
                   let tag = completeTag(
                    in: protected.markdown,
                    startingAt: index
                   ) {
                    appendNewlines(from: tag.value, to: &output)
                    index = tag.endIndex
                    let identity = tagIdentity(tag.value)
                    if identity.isClosing,
                       identity.name == activeContainer {
                        dangerousContainer = nil
                    }
                } else {
                    if protected.markdown[index] == "\n" {
                        output.append("\n")
                    }
                    index = protected.markdown.index(after: index)
                }
                continue
            }

            if protected.markdown[index...].hasPrefix("<!--") {
                let commentStart = index
                if let closingRange = protected.markdown[index...].range(
                    of: "-->"
                ) {
                    index = closingRange.upperBound
                    appendNewlines(
                        from: String(
                            protected.markdown[commentStart..<index]
                        ),
                        to: &output
                    )
                } else {
                    appendNewlines(
                        from: String(protected.markdown[commentStart...]),
                        to: &output
                    )
                    index = protected.markdown.endIndex
                }
                continue
            }

            if protected.markdown[index] == "<",
               isPotentialHTMLTag(in: protected.markdown, at: index) {
                guard let tag = completeTag(
                    in: protected.markdown,
                    startingAt: index
                ) else {
                    appendNewlines(
                        from: String(protected.markdown[index...]),
                        to: &output
                    )
                    break
                }

                let identity = tagIdentity(tag.value)
                if dangerousContainerNames.contains(identity.name),
                   !identity.isClosing,
                   !identity.isSelfClosing {
                    dangerousContainer = identity.name
                    appendNewlines(from: tag.value, to: &output)
                } else if identity.name == "img", !identity.isClosing {
                    let placeholder =
                        "\(protected.placeholderPrefix)IMAGE_\(htmlImages.count)\u{1E}"
                    htmlImages[placeholder] = tag.value
                    output.append(placeholder)
                    appendNewlines(from: tag.value, to: &output)
                } else {
                    appendNewlines(from: tag.value, to: &output)
                }
                index = tag.endIndex
                continue
            }

            output.append(protected.markdown[index])
            index = protected.markdown.index(after: index)
        }

        return READMESanitizedContent(
            markdown: output,
            codeBlocks: protected.codeBlocks,
            htmlImages: htmlImages
        )
    }

    private func protectFencedCode(
        in markdown: String
    ) -> (
        markdown: String,
        codeBlocks: [String: READMEFencedCode],
        placeholderPrefix: String
    ) {
        var placeholderPrefix = "\u{1E}GITMATE_"
        while markdown.contains(placeholderPrefix) {
            placeholderPrefix += "_"
        }

        let lines = markdown.components(separatedBy: .newlines)
        var output: [String] = []
        var codeBlocks: [String: READMEFencedCode] = [:]
        var index = 0

        while index < lines.count {
            guard let fence = openingFence(in: lines[index]) else {
                output.append(lines[index])
                index += 1
                continue
            }

            var codeLines: [String] = []
            index += 1
            while index < lines.count,
                  !isClosingFence(lines[index], opening: fence) {
                codeLines.append(lines[index])
                index += 1
            }
            if index < lines.count {
                index += 1
            }

            let placeholder =
                "\(placeholderPrefix)CODE_\(codeBlocks.count)\u{1E}"
            codeBlocks[placeholder] = READMEFencedCode(
                language: fence.language,
                value: codeLines.joined(separator: "\n")
            )
            output.append(placeholder)
        }

        return (
            output.joined(separator: "\n"),
            codeBlocks,
            placeholderPrefix
        )
    }

    private func openingFence(
        in line: String
    ) -> (character: Character, count: Int, language: String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let character = trimmed.first,
              character == "`" || character == "~"
        else {
            return nil
        }
        let count = trimmed.prefix { $0 == character }.count
        guard count >= 3 else { return nil }
        let info = trimmed.dropFirst(count)
            .trimmingCharacters(in: .whitespaces)
        return (character, count, info.isEmpty ? nil : info)
    }

    private func isClosingFence(
        _ line: String,
        opening: (character: Character, count: Int, language: String?)
    ) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let count = trimmed.prefix { $0 == opening.character }.count
        return count >= opening.count
            && trimmed.dropFirst(count)
                .trimmingCharacters(in: .whitespaces)
                .isEmpty
    }

    private func isPotentialHTMLTag(
        in markdown: String,
        at index: String.Index
    ) -> Bool {
        var cursor = markdown.index(after: index)
        guard cursor < markdown.endIndex else { return false }
        if markdown[cursor] == "/" {
            cursor = markdown.index(after: cursor)
            guard cursor < markdown.endIndex else { return false }
        }
        return markdown[cursor].isLetter
            || markdown[cursor] == "!"
            || markdown[cursor] == "?"
    }

    private func completeTag(
        in markdown: String,
        startingAt startIndex: String.Index
    ) -> (value: String, endIndex: String.Index)? {
        var cursor = markdown.index(after: startIndex)
        var quote: Character?

        while cursor < markdown.endIndex {
            let character = markdown[cursor]
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                let endIndex = markdown.index(after: cursor)
                return (
                    String(markdown[startIndex..<endIndex]),
                    endIndex
                )
            }
            cursor = markdown.index(after: cursor)
        }
        return nil
    }

    private func tagIdentity(
        _ tag: String
    ) -> (name: String, isClosing: Bool, isSelfClosing: Bool) {
        var body = tag.dropFirst().dropLast()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let isClosing = body.hasPrefix("/")
        if isClosing {
            body = body.dropFirst()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let name = body.prefix {
            !$0.isWhitespace && $0 != "/" && $0 != ">"
        }
        .lowercased()
        return (
            name,
            isClosing,
            body.trimmingCharacters(in: .whitespacesAndNewlines)
                .hasSuffix("/")
        )
    }

    private func appendNewlines(from removed: String, to output: inout String) {
        output.append(contentsOf: removed.filter { $0 == "\n" })
    }
}

enum READMEURLPolicy {
    static func resolvedRemoteURL(
        _ value: String,
        baseURL: URL?
    ) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let components = URLComponents(string: value),
           components.scheme != nil {
            guard let scheme = components.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  let url = components.url,
                  normalizedHost(url) != nil
            else {
                return nil
            }
            return url
        }

        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              normalizedHost(url) != nil
        else {
            return nil
        }
        return url
    }

    static func normalizedHost(_ url: URL) -> String? {
        guard var host = url.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }
        return host.isEmpty ? nil : host
    }
}
