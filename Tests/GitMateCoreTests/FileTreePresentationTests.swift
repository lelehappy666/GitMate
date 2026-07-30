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
    },
    TestCase("文件树层级按完整父路径计算") {
        try expectEqual(
            FileTreePresentation.depth(for: "Sources"),
            0,
            "根目录深度必须为零"
        )
        try expectEqual(
            FileTreePresentation.depth(for: "Sources/App"),
            1,
            "子目录必须比父目录缩进一级"
        )
        try expectEqual(
            FileTreePresentation.depth(
                for: "Sources/App/Features/Home.swift"
            ),
            3,
            "深层文件必须保留全部父目录层级"
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
