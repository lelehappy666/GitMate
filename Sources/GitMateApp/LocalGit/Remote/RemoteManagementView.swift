import GitMateCore
import SwiftUI

struct RemoteManagementView: View {
    @Bindable var viewModel: RemoteManagementViewModel
    let service: any GitRemoteServicing
    let repositoryURL: URL
    let credentialContext: GitCredentialContext

    @State private var removalImpact: RemoteRemovalImpact?

    var body: some View {
        HSplitView {
            remoteList
                .frame(minWidth: 280, idealWidth: 340)
            editor
                .frame(minWidth: 400)
        }
        .background(.white)
        .accessibilityIdentifier("localGit.remotes")
        .task { await viewModel.refresh() }
        .confirmationDialog(
            removalTitle,
            isPresented: Binding(
                get: { removalImpact != nil },
                set: {
                    if !$0 {
                        removalImpact = nil
                    }
                }
            )
        ) {
            Button("删除远程", role: .destructive) {
                guard let impact = removalImpact else {
                    return
                }
                removalImpact = nil
                Task { await viewModel.remove(impact: impact) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var remoteList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("远程仓库")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button {
                    viewModel.clearEditor()
                } label: {
                    Label("添加", systemImage: "plus")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            Divider()

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.remotes) { remote in
                        Button {
                            viewModel.select(remote)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(remote.name)
                                        .font(.system(size: 13, weight: .bold))
                                    Spacer()
                                    protocolBadge(remote.fetchProtocol)
                                }
                                Label(
                                    remote.fetchURL,
                                    systemImage: "arrow.down.circle"
                                )
                                Label(
                                    remote.pushURL,
                                    systemImage: "arrow.up.circle"
                                )
                                Text(
                                    remote.trackingBranches.isEmpty
                                        ? "无跟踪分支"
                                        : "跟踪 \(remote.trackingBranches.joined(separator: "、"))"
                                )
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(GitMateTheme.textPrimary)
                            .padding(13)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                            .background(
                                viewModel.selectedName == remote.name
                                    ? GitMateTheme.accentSoft
                                    : .white
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius:
                                        GitMateTheme.compactCornerRadius
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius:
                                        GitMateTheme.compactCornerRadius
                                )
                                .stroke(GitMateTheme.border, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .background(GitMateTheme.panel.opacity(0.4))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                viewModel.selectedName == nil
                    ? "添加远程"
                    : "编辑远程"
            )
            .font(.system(size: 20, weight: .bold))

            field("名称", text: $viewModel.name)
            field("Fetch URL", text: $viewModel.fetchURL)
            field(
                "Push URL（留空则沿用 Fetch）",
                text: $viewModel.pushURL
            )

            if let result = viewModel.connectionResult {
                Label(
                    connectionText(result),
                    systemImage: connectionIcon(result)
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    result.isConnected
                        ? GitMateTheme.success
                        : GitMateTheme.warning
                )
            }

            if let error = viewModel.error {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GitMateTheme.danger)
            }

            Spacer()

            HStack {
                if viewModel.selectedName != nil {
                    Button("测试连接") {
                        Task {
                            await viewModel.testConnection(
                                context: credentialContext
                            )
                        }
                    }
                    Button("删除", role: .destructive) {
                        prepareRemoval()
                    }
                }
                Spacer()
                Button("保存") {
                    Task { await viewModel.save() }
                }
                .buttonStyle(.borderedProminent)
                .tint(GitMateTheme.accent)
                .disabled(
                    viewModel.name.isEmpty || viewModel.fetchURL.isEmpty
                )
            }
        }
        .padding(22)
        .background(.white)
    }

    private func field(
        _ title: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func protocolBadge(
        _ value: GitRemoteProtocol
    ) -> some View {
        Text(protocolText(value))
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(GitMateTheme.accentSoft)
            .clipShape(Capsule())
    }

    private var removalTitle: String {
        guard let impact = removalImpact else {
            return "删除远程？"
        }
        if impact.trackingBranches.isEmpty {
            return "确定删除远程 \(impact.remote)？"
        }
        return "删除后 \(impact.trackingBranches.joined(separator: "、")) 将失去上游配置"
    }

    private func prepareRemoval() {
        guard let name = viewModel.selectedName else {
            return
        }
        Task {
            removalImpact = try? await service.removalImpact(
                repositoryURL: repositoryURL,
                remote: name
            )
        }
    }

    private func protocolText(_ value: GitRemoteProtocol) -> String {
        switch value {
        case .https:
            return "HTTPS"
        case .ssh:
            return "SSH"
        case .localFileForTests:
            return "本地"
        case .unsupported:
            return "不支持"
        }
    }

    private func connectionText(
        _ result: RemoteConnectionResult
    ) -> String {
        switch result {
        case let .connected(referenceCount):
            return "已连接 · \(referenceCount) 个分支引用"
        case .authenticationRequired:
            return "需要重新授权"
        case .sshAgentUnavailable:
            return "SSH Agent 不可用"
        }
    }

    private func connectionIcon(
        _ result: RemoteConnectionResult
    ) -> String {
        result.isConnected
            ? "checkmark.circle.fill"
            : "exclamationmark.triangle.fill"
    }
}

private extension RemoteConnectionResult {
    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}
