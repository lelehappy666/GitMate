import Foundation
import GitMateCore

private let repositorySwitcherRepositories = [
    Repository(
        id: 1,
        name: "gitmate",
        fullName: "octo-org/gitmate",
        isPrivate: false,
        defaultBranch: "main",
        sizeInKilobytes: 1,
        cloneURL: URL(string: "https://github.com/octo-org/gitmate.git")!,
        ownerAvatarURL: nil
    ),
    Repository(
        id: 2,
        name: "notes",
        fullName: "design-team/notes",
        isPrivate: true,
        defaultBranch: "main",
        sizeInKilobytes: 1,
        cloneURL: URL(string: "https://github.com/design-team/notes.git")!,
        ownerAvatarURL: nil
    )
]

let repositorySwitcherModelTests = [
    TestCase("仓库切换搜索同时匹配仓库名和所有者") {
        let results = RepositorySwitcherModel.filteredRepositories(
            repositorySwitcherRepositories,
            query: "  team  "
        )

        try expectEqual(
            results.map(\.id),
            [2],
            "搜索应忽略首尾空白并匹配仓库所有者"
        )

        let nameResults = RepositorySwitcherModel.filteredRepositories(
            repositorySwitcherRepositories,
            query: "gitmate"
        )
        try expectEqual(
            nameResults.map(\.id),
            [1],
            "搜索应匹配仓库短名称"
        )
    },
    TestCase("仓库切换空搜索保持原始顺序") {
        let results = RepositorySwitcherModel.filteredRepositories(
            repositorySwitcherRepositories,
            query: "  \n"
        )

        try expectEqual(
            results.map(\.id),
            [1, 2],
            "空搜索应保留输入仓库的顺序"
        )
    }
]
