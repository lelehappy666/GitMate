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
    TestCase("提交画布默认隐藏且持久化开启状态") {
        let suiteName = "GitMateCanvasFeature-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsExperimentalFeaturePreferenceStore(
            defaults: defaults
        )

        try expect(
            store.commitGraphCanvasEnabled() == false,
            "未保存偏好时画布布局必须隐藏"
        )
        store.setCommitGraphCanvasEnabled(true)
        try expect(
            store.commitGraphCanvasEnabled(),
            "开启画布布局后必须可以读回"
        )
        store.setCommitGraphCanvasEnabled(false)
        try expect(
            store.commitGraphCanvasEnabled() == false,
            "关闭画布布局必须覆盖之前的开启状态"
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
    },
    TestCase("提交画布模型更新界面状态并保存") {
        let store = InMemoryExperimentalFeaturePreferenceStore()
        let model = await MainActor.run {
            ExperimentalFeaturePreferences(store: store)
        }

        await MainActor.run {
            model.setCommitGraphCanvasEnabled(true)
        }

        let value = await MainActor.run {
            model.commitGraphCanvasEnabled
        }
        try expect(value, "开启后界面应立即显示画布入口")
        try expect(store.commitGraphCanvasEnabled(), "画布偏好必须同步保存")
    },
    TestCase("关闭提交画布时强制使用传统布局") {
        let disabled = CommitGraphCanvasAccessPolicy(isEnabled: false)
        let enabled = CommitGraphCanvasAccessPolicy(isEnabled: true)

        try expectEqual(
            disabled.resolve(.canvas),
            .traditional,
            "关闭画布功能时不得继续展示画布布局"
        )
        try expect(
            disabled.showsLayoutPicker == false,
            "关闭画布功能时必须隐藏布局切换入口"
        )
        try expectEqual(
            enabled.resolve(.canvas),
            .canvas,
            "开启画布功能时必须保留用户选择"
        )
        try expect(enabled.showsLayoutPicker, "开启后必须显示布局切换入口")
    }
]
