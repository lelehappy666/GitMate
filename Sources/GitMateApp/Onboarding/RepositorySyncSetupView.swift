import GitMateCore
import SwiftUI

struct RepositorySyncSetupView: View {
    let viewModel: OnboardingViewModel

    private var selectedCount: Int {
        viewModel.state.preferences.filter(\.shouldSyncInitially).count
    }

    private var selectedSize: Int64 {
        let selectedIDs = Set(
            viewModel.state.preferences
                .filter(\.shouldSyncInitially)
                .map(\.repositoryID)
        )
        return viewModel.state.repositories
            .filter { selectedIDs.contains($0.id) }
            .reduce(0) { $0 + Int64($1.sizeInKilobytes) * 1_024 }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("选择首次同步方式")
                        .font(.system(size: 28, weight: .bold))
                    Text("每个仓库都可以设为不同步、手动同步或自动同步。")
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
                Spacer()
                Menu {
                    batchButton("全部不同步", mode: .never)
                    batchButton("全部手动同步", mode: .manual)
                    batchButton("全部自动同步", mode: .automatic)
                } label: {
                    Label("批量设置", systemImage: "slider.horizontal.3")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(spacing: 12) {
                summaryMetric(
                    value: "\(viewModel.state.repositories.count)",
                    label: "仓库总数"
                )
                summaryMetric(value: "\(selectedCount)", label: "本次同步")
                summaryMetric(value: formattedSize(selectedSize), label: "预计占用")
            }

            VStack(spacing: 0) {
                HStack {
                    Text("仓库")
                    Spacer()
                    Text("同步方式")
                        .frame(width: 300)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GitMateTheme.textSecondary)
                .padding(.horizontal, 18)
                .frame(height: 38)
                .background(GitMateTheme.panel)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.state.repositories) { repository in
                            repositoryRow(repository)
                            Divider().padding(.leading, 64)
                        }
                    }
                }
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(GitMateTheme.border, lineWidth: 1)
            }

            HStack {
                Button("返回权限说明") {
                    viewModel.returnToPermissionReview()
                }
                .buttonStyle(GitMateButtonStyle(role: .secondary))

                Spacer()

                Text("\(selectedCount) 个仓库 · \(formattedSize(selectedSize))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)

                Button {
                    Task { await viewModel.startSync() }
                } label: {
                    HStack {
                        Text(selectedCount == 0 ? "跳过首次同步" : "开始首次同步")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(GitMateButtonStyle(role: .primary))
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func repositoryRow(_ repository: Repository) -> some View {
        HStack(spacing: 13) {
            GitMateAvatar(url: repository.ownerAvatarURL, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(repository.fullName)
                        .font(.system(size: 14, weight: .semibold))
                    Text(repository.isPrivate ? "私有" : "公开")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(GitMateTheme.panel)
                        .clipShape(Capsule())
                }
                HStack(spacing: 12) {
                    Label(repository.defaultBranch, systemImage: "arrow.triangle.branch")
                    Text(formattedSize(Int64(repository.sizeInKilobytes) * 1_024))
                }
                .font(.system(size: 11))
                .foregroundStyle(GitMateTheme.textSecondary)
            }
            Spacer()
            Picker(
                "同步方式",
                selection: Binding(
                    get: { preference(for: repository.id).mode },
                    set: {
                        viewModel.updateSyncMode(
                            repositoryID: repository.id,
                            mode: $0
                        )
                    }
                )
            ) {
                Text("不同步").tag(RepositorySyncMode.never)
                Text("手动").tag(RepositorySyncMode.manual)
                Text("自动").tag(RepositorySyncMode.automatic)
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            .accessibilityLabel("\(repository.fullName) 同步方式")
            .accessibilityIdentifier(
                "onboarding.repository.syncMode.\(repository.id)"
            )
        }
        .padding(.horizontal, 18)
        .frame(height: 68)
    }

    private func preference(for repositoryID: Int64) -> RepositorySyncPreference {
        viewModel.state.preferences.first { $0.repositoryID == repositoryID }
            ?? RepositorySyncPreference(repositoryID: repositoryID, mode: .automatic)
    }

    private func summaryMetric(value: String, label: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(GitMateTheme.border, lineWidth: 1)
        }
    }

    private func batchButton(
        _ title: String,
        mode: RepositorySyncMode
    ) -> some View {
        Button(title) {
            for repository in viewModel.state.repositories {
                viewModel.updateSyncMode(repositoryID: repository.id, mode: mode)
            }
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file
        )
    }
}
