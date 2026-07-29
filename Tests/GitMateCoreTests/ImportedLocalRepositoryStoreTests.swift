import Foundation
import GitMateCore

private func importedRepositoryStoreTestDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "GitMateImportedRepositoryStoreTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory
}

private func importedRepositoryFixture(
    id: Int64 = 42,
    path: String = "/Users/test/Projects/mac-client",
    cloneURL: String = "https://github.com/gitmate/mac-client.git"
) -> ImportedLocalRepository {
    ImportedLocalRepository(
        repository: Repository(
            id: id,
            name: "mac-client",
            fullName: "gitmate/mac-client",
            isPrivate: true,
            defaultBranch: "main",
            sizeInKilobytes: 2_048,
            cloneURL: URL(string: cloneURL)!,
            ownerAvatarURL: nil,
            primaryLanguage: "Swift"
        ),
        localURL: URL(fileURLWithPath: path)
    )
}

let importedLocalRepositoryStoreTests = [
    TestCase("导入的本地仓库按账户持久化") {
        let directory = try importedRepositoryStoreTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONImportedLocalRepositoryStore(rootDirectory: directory)
        let record = importedRepositoryFixture()

        try store.save([record], accountID: "octo-cat")
        let reloadedStore = JSONImportedLocalRepositoryStore(
            rootDirectory: directory
        )
        let loaded = try reloadedStore.load(accountID: "octo-cat")

        try expectEqual(loaded, [record], "应恢复仓库元数据与原始本地路径")
    },
    TestCase("重复导入同一远端时保留最新本地路径") {
        let directory = try importedRepositoryStoreTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONImportedLocalRepositoryStore(rootDirectory: directory)
        let oldRecord = importedRepositoryFixture(path: "/Users/test/Old/mac-client")
        let newRecord = importedRepositoryFixture(path: "/Users/test/New/mac-client")

        try store.save([oldRecord, newRecord], accountID: "octo-cat")
        let loaded = try store.load(accountID: "octo-cat")

        try expectEqual(loaded.count, 1, "同一仓库不应生成重复登记")
        try expectEqual(
            loaded.first?.localURL.path,
            "/Users/test/New/mac-client",
            "应保留最近一次选择的位置"
        )
    },
    TestCase("导入记录不会把远端凭据写入磁盘") {
        let directory = try importedRepositoryStoreTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONImportedLocalRepositoryStore(rootDirectory: directory)
        let sensitiveValue = "should-not-be-written"
        let record = importedRepositoryFixture(
            cloneURL: "https://reader:\(sensitiveValue)@github.com/gitmate/mac-client.git?token=\(sensitiveValue)#fragment"
        )

        try store.save([record], accountID: "octo-cat")

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let data = try Data(contentsOf: files[0])
        let content = String(decoding: data, as: UTF8.self)
        let loaded = try store.load(accountID: "octo-cat")
        try expect(!content.contains(sensitiveValue), "本地记录不得包含 URL 凭据")
        try expectEqual(
            loaded.first?.repository.cloneURL,
            URL(string: "https://github.com/gitmate/mac-client.git"),
            "清洗后仍应可恢复仓库地址"
        )
        try expectEqual(
            loaded.first?.repository.primaryLanguage,
            "Swift",
            "清洗记录时不得丢失主要语言"
        )
    }
]
