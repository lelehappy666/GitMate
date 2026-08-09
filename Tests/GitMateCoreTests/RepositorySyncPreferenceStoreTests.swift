import Foundation
import GitMateCore

let repositorySyncPreferenceStoreTests = [
    TestCase("同步偏好按账户持久保存并稳定覆盖") {
        let suiteName = "GitMatePreferenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = UserDefaultsRepositorySyncPreferenceStore(
            defaults: defaults
        )

        try store.save(
            [
                RepositorySyncPreference(
                    repositoryID: 1,
                    mode: .automatic
                ),
                RepositorySyncPreference(
                    repositoryID: 2,
                    mode: .never
                )
            ],
            accountID: "github.com:1"
        )
        try store.save(
            [
                RepositorySyncPreference(
                    repositoryID: 1,
                    mode: .manual
                )
            ],
            accountID: "github.com:1"
        )

        let firstAccountPreferences = try store.load(
            accountID: "github.com:1"
        )
        let secondAccountPreferences = try store.load(
            accountID: "github.com:2"
        )

        try expectEqual(
            firstAccountPreferences,
            [
                RepositorySyncPreference(
                    repositoryID: 1,
                    mode: .manual
                )
            ],
            "覆盖保存后不得复活旧偏好"
        )
        try expectEqual(
            secondAccountPreferences,
            [],
            "不同账户偏好必须隔离"
        )
    }
]
