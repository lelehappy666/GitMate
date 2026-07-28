import GitMateCore

let repositorySyncPreferenceTests = [
    TestCase("不同步模式不会进入首次同步") {
        let preference = RepositorySyncPreference(repositoryID: 1, mode: .never)
        try expect(!preference.shouldSyncInitially, "不同步模式应排除仓库")
    },
    TestCase("手动与自动模式都会进入首次同步") {
        var preference = RepositorySyncPreference(repositoryID: 1, mode: .manual)
        try expect(preference.shouldSyncInitially, "手动模式应允许本次同步")

        preference.mode = .automatic
        try expect(preference.shouldSyncInitially, "自动模式应允许本次同步")
    }
]
