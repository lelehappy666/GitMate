import Foundation

public enum GitDiffParser {
    public static let maximumFullDiffBytes = 2_097_152
    public static let maximumFullDiffLines = 20_000

    public static func parse(
        path: String,
        data: Data
    ) -> GitDiffDocument {
        let value = String(decoding: data, as: UTF8.self)
        let lines = value.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        let lineCount = max(lines.count - (lines.last == "" ? 1 : 0), 0)
        let counts = countChanges(lines)
        let isBinary = lines.contains(where: {
            $0.hasPrefix("Binary files ") || $0 == "GIT binary patch"
        })

        guard data.count <= maximumFullDiffBytes,
              lineCount <= maximumFullDiffLines,
              !isBinary
        else {
            return GitDiffDocument(
                path: path,
                files: [
                    GitDiffFile(
                        oldPath: nil,
                        path: path,
                        isBinary: isBinary
                    )
                ],
                hunks: [],
                byteCount: data.count,
                lineCount: lineCount,
                addedLineCount: counts.added,
                deletedLineCount: counts.deleted,
                loadingMode: .summary
            )
        }

        let hunks = parseHunks(path: path, lines: lines)
        return GitDiffDocument(
            path: path,
            files: [
                GitDiffFile(
                    oldPath: oldPath(from: lines),
                    path: path,
                    isBinary: false
                )
            ],
            hunks: hunks,
            byteCount: data.count,
            lineCount: lineCount,
            addedLineCount: counts.added,
            deletedLineCount: counts.deleted,
            loadingMode: .full
        )
    }

    private static func parseHunks(
        path: String,
        lines: [String]
    ) -> [GitDiffHunk] {
        var fileHeader: [String] = []
        var currentHeader: String?
        var currentLines: [String] = []
        var hunks: [GitDiffHunk] = []

        func appendCurrentHunk() {
            guard let header = currentHeader else {
                return
            }
            let hunkIndex = hunks.count
            let displayLines = currentLines.enumerated().map { index, line in
                GitDiffLine(
                    id: "\(path)#\(hunkIndex)#\(index)",
                    kind: lineKind(line),
                    text: line
                )
            }
            let counts = countChanges(currentLines)
            let patchText = (fileHeader + [header] + currentLines)
                .joined(separator: "\n") + "\n"
            hunks.append(
                GitDiffHunk(
                    id: "\(path)#\(hunkIndex)#\(header)",
                    header: header,
                    lines: displayLines,
                    patch: Data(patchText.utf8),
                    addedLineCount: counts.added,
                    deletedLineCount: counts.deleted
                )
            )
        }

        for line in lines {
            if line.hasPrefix("@@ ") {
                appendCurrentHunk()
                currentHeader = line
                currentLines = []
            } else if currentHeader == nil {
                if !line.isEmpty {
                    fileHeader.append(line)
                }
            } else {
                currentLines.append(line)
            }
        }
        appendCurrentHunk()
        return hunks
    }

    private static func countChanges(
        _ lines: [String]
    ) -> (added: Int, deleted: Int) {
        var added = 0
        var deleted = 0
        for line in lines {
            if line.hasPrefix("+"), !line.hasPrefix("+++") {
                added += 1
            } else if line.hasPrefix("-"), !line.hasPrefix("---") {
                deleted += 1
            }
        }
        return (added, deleted)
    }

    private static func lineKind(_ line: String) -> GitDiffLineKind {
        if line.hasPrefix("+"), !line.hasPrefix("+++") {
            return .addition
        }
        if line.hasPrefix("-"), !line.hasPrefix("---") {
            return .deletion
        }
        if line.hasPrefix("\\") {
            return .metadata
        }
        return .context
    }

    private static func oldPath(from lines: [String]) -> String? {
        guard let line = lines.first(where: { $0.hasPrefix("--- ") }) else {
            return nil
        }
        let value = String(line.dropFirst(4))
        guard value != "/dev/null" else {
            return nil
        }
        return value.hasPrefix("a/") ? String(value.dropFirst(2)) : value
    }
}
