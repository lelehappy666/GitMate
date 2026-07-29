import Foundation

public enum GitOutputParser {
    public static func parseCommits(_ output: String) throws -> [GitCommit] {
        try output
            .split(separator: "\u{1e}", omittingEmptySubsequences: true)
            .map { record in
                let normalized = record.trimmingCharacters(in: .newlines)
                let fields = normalized.split(
                    separator: "\u{1f}",
                    maxSplits: 7,
                    omittingEmptySubsequences: false
                )
                guard fields.count == 7 || fields.count == 8 else {
                    throw GitOutputParsingError.malformedCommit(normalized)
                }
                guard let authoredAt = ISO8601DateFormatter().date(
                    from: String(fields[5])
                ) else {
                    throw GitOutputParsingError.malformedCommit(normalized)
                }

                return GitCommit(
                    shortHash: String(fields[0]),
                    fullHash: String(fields[1]),
                    subject: String(fields[2]),
                    authorName: String(fields[3]),
                    authorEmail: String(fields[4]),
                    authoredAt: authoredAt,
                    parentHashes: fields[6].split(separator: " ").map(String.init),
                    decorations: fields.count == 8
                        ? fields[7]
                            .split(separator: ",")
                            .map {
                                $0.trimmingCharacters(in: .whitespaces)
                            }
                            .filter { !$0.isEmpty }
                        : []
                )
            }
    }

    public static func parseTree(_ output: String) throws -> [GitFileEntry] {
        try output
            .split(separator: "\u{0}", omittingEmptySubsequences: true)
            .compactMap { rawRecord in
                let record = String(rawRecord)
                guard let tab = record.firstIndex(of: "\t") else {
                    throw GitOutputParsingError.malformedTreeEntry(record)
                }
                let metadata = record[..<tab].split(separator: " ")
                let path = String(record[record.index(after: tab)...])
                guard metadata.count == 4 else {
                    throw GitOutputParsingError.malformedTreeEntry(record)
                }
                guard isSafeRelativePath(path) else {
                    return nil
                }

                let mode = String(metadata[0])
                let type = String(metadata[1])
                let byteCount: Int64?
                if metadata[3] == "-" {
                    byteCount = nil
                } else if let value = Int64(metadata[3]) {
                    byteCount = value
                } else {
                    throw GitOutputParsingError.malformedTreeEntry(record)
                }

                return GitFileEntry(
                    path: path,
                    name: path.split(separator: "/").last.map(String.init) ?? path,
                    kind: kind(mode: mode, type: type),
                    objectID: String(metadata[2]),
                    byteCount: byteCount
                )
            }
    }

    public static func parseStatus(_ output: String) throws -> LocalRepositoryStatus {
        var branch: String?
        var upstream: String?
        var ahead = 0
        var behind = 0
        var stagedCount = 0
        var unstagedCount = 0
        var untrackedCount = 0
        var conflictCount = 0

        for rawRecord in output.split(
            separator: "\u{0}",
            omittingEmptySubsequences: true
        ) {
            let record = String(rawRecord)
            if record.hasPrefix("# branch.head ") {
                branch = String(record.dropFirst("# branch.head ".count))
            } else if record.hasPrefix("# branch.upstream ") {
                upstream = String(record.dropFirst("# branch.upstream ".count))
            } else if record.hasPrefix("# branch.ab ") {
                let values = record
                    .dropFirst("# branch.ab ".count)
                    .split(separator: " ")
                guard values.count == 2,
                      values[0].first == "+",
                      values[1].first == "-",
                      let parsedAhead = Int(values[0].dropFirst()),
                      let parsedBehind = Int(values[1].dropFirst())
                else {
                    throw GitOutputParsingError.malformedStatus(record)
                }
                ahead = parsedAhead
                behind = parsedBehind
            } else if record.hasPrefix("1 ") || record.hasPrefix("2 ") {
                let fields = record.split(
                    separator: " ",
                    maxSplits: 2,
                    omittingEmptySubsequences: true
                )
                guard fields.count >= 2, fields[1].count == 2 else {
                    throw GitOutputParsingError.malformedStatus(record)
                }
                let status = Array(fields[1])
                if status[0] != "." {
                    stagedCount += 1
                }
                if status[1] != "." {
                    unstagedCount += 1
                }
            } else if record.hasPrefix("u ") {
                conflictCount += 1
            } else if record.hasPrefix("? ") {
                untrackedCount += 1
            }
        }

        return LocalRepositoryStatus(
            branch: branch,
            upstream: upstream,
            ahead: ahead,
            behind: behind,
            stagedCount: stagedCount,
            unstagedCount: unstagedCount,
            untrackedCount: untrackedCount,
            conflictCount: conflictCount
        )
    }

    public static func parseShow(_ output: String) throws -> ParsedGitShow {
        guard let metadataEnd = output.firstIndex(of: "\u{1e}") else {
            throw GitOutputParsingError.malformedShow(output)
        }
        let metadata = String(output[..<metadataEnd])
        let fields = metadata.split(
            separator: "\u{1f}",
            maxSplits: 10,
            omittingEmptySubsequences: false
        )
        guard fields.count == 11,
              let authoredAt = ISO8601DateFormatter().date(
                  from: String(fields[5])
              )
        else {
            throw GitOutputParsingError.malformedShow(metadata)
        }

        let commit = GitCommit(
            shortHash: String(fields[0]),
            fullHash: String(fields[1]),
            subject: String(fields[2]),
            authorName: String(fields[3]),
            authorEmail: String(fields[4]),
            authoredAt: authoredAt,
            parentHashes: fields[6].split(separator: " ").map(String.init),
            decorations: fields[7]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        let message = String(fields[8])
        let signatureStatus: GitSignatureStatus
        switch fields[9] {
        case "G":
            signatureStatus = .verified
        case "B", "E", "R", "U", "X", "Y":
            signatureStatus = .unverified
        default:
            signatureStatus = .unknown
        }
        let signerValue = String(fields[10])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = GitCommitDetail(
            commit: commit,
            message: message,
            signatureStatus: signatureStatus,
            signer: signerValue.isEmpty ? nil : signerValue
        )

        let bodyStart = output.index(after: metadataEnd)
        let body = output[bodyStart...]
            .drop(while: { $0 == "\n" || $0 == "\r" })
        let lines = body.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        let patchStart = lines.firstIndex(where: { $0.hasPrefix("diff --git ") })
            ?? lines.endIndex
        var changedFiles: [GitChangedFile] = []
        var additions = 0
        var deletions = 0

        for rawLine in lines[..<patchStart] {
            let line = String(rawLine)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let values = line.split(
                separator: "\t",
                maxSplits: 2,
                omittingEmptySubsequences: false
            )
            guard values.count == 3 else {
                throw GitOutputParsingError.malformedNumstat(line)
            }
            let isBinary = values[0] == "-" && values[1] == "-"
            let fileAdditions: Int?
            let fileDeletions: Int?
            if isBinary {
                fileAdditions = nil
                fileDeletions = nil
            } else if let parsedAdditions = Int(values[0]),
                      let parsedDeletions = Int(values[1]) {
                fileAdditions = parsedAdditions
                fileDeletions = parsedDeletions
                additions += parsedAdditions
                deletions += parsedDeletions
            } else {
                throw GitOutputParsingError.malformedNumstat(line)
            }
            changedFiles.append(
                GitChangedFile(
                    path: String(values[2]),
                    additions: fileAdditions,
                    deletions: fileDeletions,
                    isBinary: isBinary
                )
            )
        }

        let patch = patchStart == lines.endIndex
            ? ""
            : lines[patchStart...].joined(separator: "\n")
        let diff = GitDiff(
            commitHash: commit.fullHash,
            files: changedFiles,
            patch: patch,
            additions: additions,
            deletions: deletions
        )
        return ParsedGitShow(detail: detail, diff: diff)
    }

    static func isSafeRelativePath(_ path: String, allowsEmpty: Bool = false) -> Bool {
        if path.isEmpty {
            return allowsEmpty
        }
        guard !path.isEmpty, !path.hasPrefix("/") else {
            return false
        }
        guard !path.contains("\u{0}") else {
            return false
        }
        return !path.split(separator: "/", omittingEmptySubsequences: false)
            .contains("..")
    }

    private static func kind(mode: String, type: String) -> GitFileEntry.Kind {
        if mode == "120000" {
            return .symlink
        }
        if mode == "160000" || type == "commit" {
            return .submodule
        }
        if type == "tree" {
            return .directory
        }
        return .file
    }
}
