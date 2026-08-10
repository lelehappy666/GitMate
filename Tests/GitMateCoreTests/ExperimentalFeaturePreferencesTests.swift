import Foundation
import GitMateCore

let experimentalFeaturePreferenceTests = [
    TestCase("实验功能默认关闭且持久化开关值") {
        let suiteName = "GitMateExperimentalFeatures-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsExperimentalFeaturePreferenceStore(
            defaults: defaults
        )

        try expect(
            store.repositoryManagementEnabled() == false,
            "未保存偏好时必须默认关闭"
        )
        store.setRepositoryManagementEnabled(true)
        try expect(
            store.repositoryManagementEnabled(),
            "开启状态必须可以读回"
        )
        store.setRepositoryManagementEnabled(false)
        try expect(
            store.repositoryManagementEnabled() == false,
            "关闭状态必须可以覆盖保存"
        )
    },
    TestCase("实验功能内存存储实例相互隔离") {
        let first = InMemoryExperimentalFeaturePreferenceStore()
        let second = InMemoryExperimentalFeaturePreferenceStore()
        first.setRepositoryManagementEnabled(true)

        try expect(first.repositoryManagementEnabled(), "第一个存储应开启")
        try expect(
            second.repositoryManagementEnabled() == false,
            "第二个存储不得被污染"
        )
    },
    TestCase("管理工作区访问策略拒绝关闭状态") {
        let disabled = RepositoryManagementAccessPolicy(isEnabled: false)
        let enabled = RepositoryManagementAccessPolicy(isEnabled: true)

        try expect(disabled.canOpenWorkspace == false, "关闭时不得打开")
        try expect(
            disabled.shouldDismissWorkspace(isPresented: true),
            "关闭时必须清理已展示的工作区"
        )
        try expect(enabled.canOpenWorkspace, "开启时应允许打开")
        try expect(
            enabled.shouldDismissWorkspace(isPresented: true) == false,
            "开启时不得误关闭工作区"
        )
    },
    TestCase("实验功能模型更新界面状态并保存") {
        let store = InMemoryExperimentalFeaturePreferenceStore()
        let model = await MainActor.run {
            ExperimentalFeaturePreferences(store: store)
        }

        await MainActor.run {
            model.setRepositoryManagementEnabled(true)
        }

        let value = await MainActor.run {
            model.repositoryManagementEnabled
        }
        try expect(value, "模型应立即更新界面状态")
        try expect(store.repositoryManagementEnabled(), "模型应同步保存偏好")
    }
]
