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
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(
                        "分支、标签与议题管理",
                        isOn: Binding(
                            get: { preferences.repositoryManagementEnabled },
                            set: {
                                preferences.setRepositoryManagementEnabled($0)
                            }
                        )
                    )
                    .accessibilityIdentifier(
                        "settings.experimental.repositoryManagement"
                    )
                    Text("启用后可以管理 GitHub 分支、标签、规则和议题。该功能仍处于实验阶段。")
                        .font(.system(size: 12))
                        .foregroundStyle(GitMateTheme.textSecondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(
                        "提交图画布布局",
                        isOn: Binding(
                            get: { preferences.commitGraphCanvasEnabled },
                            set: {
                                preferences.setCommitGraphCanvasEnabled($0)
                            }
                        )
                    )
                    .accessibilityIdentifier(
                        "settings.experimental.commitGraphCanvas"
                    )
                    Text("开启后可在传统泳道与无限画布之间切换；关闭时仅显示传统布局。")
                        .font(.system(size: 12))
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
            }
            .padding(24)
        }
        .frame(width: 520, height: 360)
        .background(.white)
    }
}
