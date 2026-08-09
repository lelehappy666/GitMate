import Foundation
import GitMateCore

private func classifierRepository(_ id: Int64) -> Repository {
    Repository(
        id: id,
        name: "repository-\(id)",
        fullName: "lele/repository-\(id)",
        isPrivate: false,
        defaultBranch: "main",
        sizeInKilobytes: 1_024,
        cloneURL: URL(
            string: "https://github.com/lele/repository-\(id).git"
        )!,
        ownerAvatarURL: nil
    )
}

private func classifierRecord(
    repository: Repository,
    availability: LocalRepositoryAvailability
) -> LocalRepositoryRecord {
    LocalRepositoryRecord(
        repository: repository,
        localURL: URL(
            filePath: "/同步目录/\(repository.name)",
            directoryHint: .isDirectory
        ),
        availability: availability,
        localSizeInBytes: 1_024,
        lastInspectedAt: Date(timeIntervalSince1970: 1_000)
    )
}

let workspaceRepositoryClassifierTests = [
    TestCase("本地存在或已选择同步的仓库进入本地集合") {
        let repositories = (1...4).map {
            classifierRepository(Int64($0))
        }
        let records = [
            classifierRecord(
                repository: repositories[0],
                availability: .available
            ),
            classifierRecord(
                repository: repositories[1],
                availability: .damaged
            ),
            classifierRecord(
                repository: repositories[2],
                availability: .missing
            ),
            classifierRecord(
                repository: repositories[3],
                availability: .missing
            )
        ]
        let preferences = [
            RepositorySyncPreference(repositoryID: 1, mode: .never),
            RepositorySyncPreference(repositoryID: 2, mode: .never),
            RepositorySyncPreference(repositoryID: 3, mode: .automatic),
            RepositorySyncPreference(repositoryID: 4, mode: .never)
        ]

        let groups = WorkspaceRepositoryClassifier.classify(
            repositories: repositories,
            records: records,
            preferences: preferences
        )

        try expectEqual(
            groups.local.map(\.id),
            [1, 2, 3],
            "可用、损坏和已选择同步但缺失的仓库都应本地管理"
        )
        try expectEqual(
            groups.cloud.map(\.id),
            [4],
            "未同步且本地缺失的仓库只能进入云端集合"
        )
    }
]
