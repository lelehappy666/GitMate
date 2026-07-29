import Foundation

public enum WorkingTreeParseError: Error, Equatable, Sendable {
    case malformedRecord(String)
    case invalidBatchSize
    case incompleteNULRecord
}

public enum WorkingTreeParser {
    public static func parseTracked(
        _ data: Data,
        generation: UInt64 = 0
    ) throws -> WorkingTreeSnapshot {
        let records = data.split(
            separator: 0,
            omittingEmptySubsequences: true
        )
        var branchName: String?
        var upstream: String?
        var ahead = 0
        var behind = 0
        var files: [WorkingTreeFile] = []
        var index = 0

        while index < records.count {
            let record = String(decoding: records[index], as: UTF8.self)
            if record.hasPrefix("# ") {
                parseHeader(
                    record,
                    branchName: &branchName,
                    upstream: &upstream,
                    ahead: &ahead,
                    behind: &behind
                )
            } else if record.hasPrefix("1 ") {
                files.append(try parseOrdinary(record))
            } else if record.hasPrefix("2 ") {
                guard index + 1 < records.count else {
                    throw WorkingTreeParseError.malformedRecord(record)
                }
                let originalPath = String(
                    decoding: records[index + 1],
                    as: UTF8.self
                )
                files.append(
                    try parseRenamed(
                        record,
                        originalPath: originalPath
                    )
                )
                index += 1
            } else if record.hasPrefix("u ") {
                files.append(try parseUnmerged(record))
            }
            index += 1
        }

        return WorkingTreeSnapshot(
            branch: LocalBranchStatus(
                name: branchName,
                upstream: upstream,
                ahead: ahead,
                behind: behind
            ),
            files: files,
            untrackedScan: .notStarted,
            generation: generation
        )
    }

    public static func parseUntrackedBatches(
        _ data: Data,
        generation: UInt64,
        batchSize: Int
    ) throws -> [WorkingTreeBatch] {
        guard batchSize > 0 else {
            throw WorkingTreeParseError.invalidBatchSize
        }

        let paths = data.split(
            separator: 0,
            omittingEmptySubsequences: true
        )
        var batches: [WorkingTreeBatch] = []
        batches.reserveCapacity(
            (paths.count + batchSize - 1) / batchSize
        )

        var start = 0
        while start < paths.count {
            let end = min(start + batchSize, paths.count)
            let files = paths[start..<end].map {
                WorkingTreeFile(
                    path: String(decoding: $0, as: UTF8.self),
                    category: .untracked
                )
            }
            batches.append(
                WorkingTreeBatch(
                    generation: generation,
                    files: files,
                    isLast: end == paths.count
                )
            )
            start = end
        }
        return batches
    }

    private static func parseHeader(
        _ record: String,
        branchName: inout String?,
        upstream: inout String?,
        ahead: inout Int,
        behind: inout Int
    ) {
        if record.hasPrefix("# branch.head ") {
            let value = String(record.dropFirst("# branch.head ".count))
            branchName = value == "(detached)" ? nil : value
        } else if record.hasPrefix("# branch.upstream ") {
            upstream = String(
                record.dropFirst("# branch.upstream ".count)
            )
        } else if record.hasPrefix("# branch.ab ") {
            let values = record
                .dropFirst("# branch.ab ".count)
                .split(separator: " ")
            for value in values {
                if value.hasPrefix("+") {
                    ahead = Int(value.dropFirst()) ?? 0
                } else if value.hasPrefix("-") {
                    behind = Int(value.dropFirst()) ?? 0
                }
            }
        }
    }

    private static func parseOrdinary(
        _ record: String
    ) throws -> WorkingTreeFile {
        let fields = record.split(
            separator: " ",
            maxSplits: 8,
            omittingEmptySubsequences: true
        )
        guard fields.count == 9 else {
            throw WorkingTreeParseError.malformedRecord(record)
        }
        return makeFile(
            path: String(fields[8]),
            originalPath: nil,
            xy: fields[1],
            conflicted: false
        )
    }

    private static func parseRenamed(
        _ record: String,
        originalPath: String
    ) throws -> WorkingTreeFile {
        let fields = record.split(
            separator: " ",
            maxSplits: 9,
            omittingEmptySubsequences: true
        )
        guard fields.count == 10 else {
            throw WorkingTreeParseError.malformedRecord(record)
        }
        return makeFile(
            path: String(fields[9]),
            originalPath: originalPath,
            xy: fields[1],
            conflicted: false
        )
    }

    private static func parseUnmerged(
        _ record: String
    ) throws -> WorkingTreeFile {
        let fields = record.split(
            separator: " ",
            maxSplits: 10,
            omittingEmptySubsequences: true
        )
        guard fields.count == 11 else {
            throw WorkingTreeParseError.malformedRecord(record)
        }
        return makeFile(
            path: String(fields[10]),
            originalPath: nil,
            xy: fields[1],
            conflicted: true
        )
    }

    private static func makeFile(
        path: String,
        originalPath: String?,
        xy: Substring,
        conflicted: Bool
    ) -> WorkingTreeFile {
        let statuses = Array(xy)
        let indexStatus = statuses.first.flatMap { $0 == "." ? nil : $0 }
        let workTreeStatus = statuses.dropFirst().first.flatMap {
            $0 == "." ? nil : $0
        }
        let category: WorkingTreeCategory
        if conflicted {
            category = .conflicted
        } else if indexStatus != nil {
            category = .staged
        } else {
            category = .unstaged
        }
        return WorkingTreeFile(
            path: path,
            originalPath: originalPath,
            category: category,
            indexStatus: indexStatus,
            workTreeStatus: workTreeStatus
        )
    }
}
