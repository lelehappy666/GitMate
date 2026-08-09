import Foundation

enum GitReferenceParser {
    private static let fieldSeparator: Character = "\u{1f}"
    private static let recordSeparator: Character = "\u{1e}"

    static func branches(from output: String) -> [GitBranch] {
        var branches: [String: GitBranch] = [:]

        for record in records(from: output) {
            let fields = record.split(
                separator: fieldSeparator,
                omittingEmptySubsequences: false
            ).map(String.init)
            guard fields.count >= 5 else {
                continue
            }

            let reference = fields[0]
            let objectSHA = fields[1]
            let upstreamShort = fields[3]
            let authorName = fields[4]

            if reference.hasPrefix("refs/heads/") {
                let name = String(reference.dropFirst("refs/heads/".count))
                guard !name.isEmpty else {
                    continue
                }
                var branch = branches[name] ?? GitBranch(
                    name: name,
                    localSHA: nil,
                    remoteSHA: nil,
                    upstreamName: nil
                )
                branch.localSHA = objectSHA.nilIfEmpty
                branch.upstreamName = upstreamShort.nilIfEmpty
                if let upstream = upstreamShort.nilIfEmpty {
                    branch.remoteName = upstream
                }
                branch.authorName = authorName.nilIfEmpty
                branches[name] = branch
                continue
            }

            guard reference.hasPrefix("refs/remotes/") else {
                continue
            }
            let remoteName = String(reference.dropFirst("refs/remotes/".count))
            guard
                !remoteName.hasSuffix("/HEAD"),
                let slash = remoteName.firstIndex(of: "/")
            else {
                continue
            }
            let nameStart = remoteName.index(after: slash)
            let name = String(remoteName[nameStart...])
            guard !name.isEmpty else {
                continue
            }
            var branch = branches[name] ?? GitBranch(
                name: name,
                localSHA: nil,
                remoteSHA: nil,
                upstreamName: nil
            )
            branch.remoteSHA = objectSHA.nilIfEmpty
            branch.remoteName = remoteName
            if branch.authorName == nil {
                branch.authorName = authorName.nilIfEmpty
            }
            branches[name] = branch
        }

        return branches.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func tags(from output: String) -> [GitTag] {
        records(from: output)
            .compactMap { record -> GitTag? in
                let fields = record.split(
                    separator: fieldSeparator,
                    omittingEmptySubsequences: false
                ).map(String.init)
                guard fields.count >= 5, !fields[0].isEmpty else {
                    return nil
                }
                return GitTag(
                    name: fields[0],
                    objectSHA: fields[1],
                    kind: fields[2] == "tag" ? .annotated : .lightweight,
                    existsLocally: true,
                    existsRemotely: false,
                    taggerName: fields[3].nilIfEmpty,
                    createdAt: parseGitDate(fields[4])
                )
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private static func records(from output: String) -> [String] {
        output.split(
            separator: recordSeparator,
            omittingEmptySubsequences: true
        ).map(String.init)
    }

    private static func parseGitDate(_ value: String) -> Date? {
        guard !value.isEmpty else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: value)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
