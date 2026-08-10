import GitMateCore
import SwiftUI

struct GitMateSettingsView: View {
    @Bindable var preferences: ExperimentalFeaturePreferences
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.system(size: 22, weight: .bold))
                    Text("管理 GitMate 的本机功能偏好")
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
                Spacer()
                Button("完成", action: onClose)
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("实验功能")
                    .font(.system(size: 15, weight: .semibold))
                Toggle(
                    "分支、标签与议题管理",
                    isOn: Binding(
                        get: { preferences.repositoryManagementEnabled },
                        set: { preferences.setRepositoryManagementEnabled($0) }
                    )
                )
                .accessibilityIdentifier(
                    "settings.experimental.repositoryManagement"
                )
                Text("启用后可以管理 GitHub 分支、标签、规则和议题。该功能仍处于实验阶段。")
                    .font(.system(size: 12))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            .padding(24)
        }
        .frame(width: 520, height: 280)
        .background(.white)
    }
}
