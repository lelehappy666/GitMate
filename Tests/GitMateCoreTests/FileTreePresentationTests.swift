import GitMateCore

let fileTreePresentationTests = [
    TestCase("文件树以前序排列子项并保留搜索祖先") {
        let entries = [
            fileEntry(path: "README.md", kind: .file),
            fileEntry(path: "Sources/Theme.swift", kind: .file),
            fileEntry(path: "Sources/App/App.swift", kind: .file),
            fileEntry(path: "Sources", kind: .directory),
            fileEntry(path: "Sources/App", kind: .directory),
            fileEntry(path: "Detached/Orphan.swift", kind: .file)
        ]

        let visible = FileTreePresentation.visibleEntries(
            entries: entries,
            expandedDirectories: ["Sources", "Sources/App"],
            query: ""
        )
        let searched = FileTreePresentation.visibleEntries(
            entries: entries,
            expandedDirectories: [],
            query: "App.swift"
        )

        try expectEqual(
            visible.map(\.path),
            [
                "Sources",
                "Sources/App",
                "Sources/App/App.swift",
                "Sources/Theme.swift",
                "Detached/Orphan.swift",
                "README.md"
            ],
            "子项必须紧跟父目录并按目录优先排列"
        )
        try expectEqual(
            searched.map(\.path),
            ["Sources", "Sources/App", "Sources/App/App.swift"],
            "搜索结果必须带上祖先路径"
        )
    }
]

private func fileEntry(
    path: String,
    kind: GitFileEntry.Kind
) -> GitFileEntry {
    GitFileEntry(
        path: path,
        name: path.split(separator: "/").last.map(String.init) ?? path,
        kind: kind,
        objectID: path,
        byteCount: nil
    )
}
