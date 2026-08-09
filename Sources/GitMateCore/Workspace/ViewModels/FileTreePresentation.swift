import Foundation

public enum FileTreePresentation {
    public static func depth(for path: String) -> Int {
        max(
            path.split(
                separator: "/",
                omittingEmptySubsequences: true
            ).count - 1,
            0
        )
    }

    public static func visibleEntries(
        entries: [GitFileEntry],
        expandedDirectories: Set<String>,
        query: String
    ) -> [GitFileEntry] {
        let entriesByPath = Dictionary(
            entries.map { ($0.path, $0) },
            uniquingKeysWith: { _, later in later }
        )
        let retainedPaths = retainedPaths(
            in: entries,
            query: query
        )
        let childrenByParent = childrenByParent(
            entries: entries,
            entriesByPath: entriesByPath
        )

        var result: [GitFileEntry] = []

        func appendChildren(of parentPath: String?) {
            for entry in childrenByParent[parentPath, default: []] {
                guard retainedPaths?.contains(entry.path) ?? true else {
                    continue
                }
                result.append(entry)
                if entry.kind == .directory,
                   retainedPaths != nil || expandedDirectories.contains(entry.path) {
                    appendChildren(of: entry.path)
                }
            }
        }

        appendChildren(of: nil)
        return result
    }

    private static func retainedPaths(
        in entries: [GitFileEntry],
        query: String
    ) -> Set<String>? {
        let normalizedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedQuery.isEmpty else {
            return nil
        }

        var paths = Set<String>()
        for entry in entries where entry.path.localizedCaseInsensitiveContains(normalizedQuery) {
            var path: String? = entry.path
            while let currentPath = path {
                paths.insert(currentPath)
                path = parentPath(of: currentPath)
            }
        }
        return paths
    }

    private static func childrenByParent(
        entries: [GitFileEntry],
        entriesByPath: [String: GitFileEntry]
    ) -> [String?: [GitFileEntry]] {
        var result: [String?: [GitFileEntry]] = [:]
        for entry in entries {
            let parentPath = parentPath(of: entry.path)
            let parentIsLoadedDirectory = parentPath.flatMap { path in
                entriesByPath[path]
            }?.kind == .directory
            result[parentIsLoadedDirectory ? parentPath : nil, default: []]
                .append(entry)
        }
        for parentPath in Array(result.keys) {
            result[parentPath]?.sort(by: isOrderedBefore)
        }
        return result
    }

    private static func parentPath(of path: String) -> String? {
        guard let separatorIndex = path.lastIndex(of: "/") else {
            return nil
        }
        return String(path[..<separatorIndex])
    }

    private static func isOrderedBefore(
        _ lhs: GitFileEntry,
        _ rhs: GitFileEntry
    ) -> Bool {
        if lhs.kind == .directory && rhs.kind != .directory {
            return true
        }
        if lhs.kind != .directory && rhs.kind == .directory {
            return false
        }
        let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
    }
}
