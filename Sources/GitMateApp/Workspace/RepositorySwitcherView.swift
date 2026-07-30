import GitMateCore
import SwiftUI

struct RepositorySwitcherView: View {
    let repositories: [Repository]
    let selectedRepositoryID: Int64?
    let onSelect: (Repository) -> Void
    let onSelectedRepositoryRemoved: () -> Void

    @State private var isPresented = false
    @State private var query = ""

    private var selectedRepository: Repository? {
        repositories.first { $0.id == selectedRepositoryID }
    }

    private var filteredRepositories: [Repository] {
        RepositorySwitcherModel.filteredRepositories(repositories, query: query)
    }

    var body: some View {
        Button {
            query = ""
            isPresented = true
        } label: {
            RepositorySwitcherCard(repository: selectedRepository)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            selectedRepository.map { "切换当前仓库：\($0.fullName)" }
                ?? "选择当前仓库"
        )
        .accessibilityIdentifier("workspace.sidebar.repository")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            RepositorySearchPopover(
                repositories: filteredRepositories,
                selectedRepositoryID: selectedRepositoryID,
                query: $query,
                onSelect: select,
                onClose: close
            )
            .frame(width: 320, height: 390)
        }
        .onChange(of: repositories.map(\.id)) { _, repositoryIDs in
            guard let selectedRepositoryID,
                  !repositoryIDs.contains(selectedRepositoryID)
            else {
                return
            }
            isPresented = false
            onSelectedRepositoryRemoved()
        }
    }

    private func select(_ repository: Repository) {
        guard repositories.contains(where: { $0.id == repository.id }) else {
            isPresented = false
            onSelectedRepositoryRemoved()
            return
        }
        onSelect(repository)
        isPresented = false
    }

    private func close() {
        isPresented = false
    }
}

private struct RepositorySwitcherCard: View {
    let repository: Repository?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(repository?.name ?? "选择仓库")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if let repository {
                        Text(ownerName(for: repository))
                        Text("·")
                        Text(primaryLanguage(for: repository))
                        if repository.isPrivate {
                            Image(systemName: "lock.fill")
                                .accessibilityLabel("私有仓库")
                        }
                    } else {
                        Text("从本地仓库中选择")
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(GitMateTheme.textTertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GitMateTheme.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitMateTheme.panel)
        .clipShape(RoundedRectangle(
            cornerRadius: GitMateTheme.compactCornerRadius,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(
                cornerRadius: GitMateTheme.compactCornerRadius,
                style: .continuous
            )
            .stroke(GitMateTheme.border, lineWidth: 1)
        }
    }

    private func ownerName(for repository: Repository) -> String {
        String(
            repository.fullName.split(separator: "/", maxSplits: 1).first
                ?? Substring(repository.fullName)
        )
    }

    private func primaryLanguage(for repository: Repository) -> String {
        guard let primaryLanguage = repository.primaryLanguage?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !primaryLanguage.isEmpty
        else {
            return "未知语言"
        }
        return primaryLanguage
    }
}

private struct RepositorySearchPopover: View {
    let repositories: [Repository]
    let selectedRepositoryID: Int64?
    @Binding var query: String
    let onSelect: (Repository) -> Void
    let onClose: () -> Void

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("切换仓库")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(GitMateTheme.textSecondary)
                .accessibilityLabel("关闭仓库切换器")
                .accessibilityHint("也可按 Escape 键关闭")
            }

            TextField("搜索仓库或所有者", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .accessibilityLabel("搜索仓库或所有者")

            if repositories.isEmpty {
                ContentUnavailableView(
                    "没有匹配的仓库",
                    systemImage: "magnifyingglass",
                    description: Text("请尝试搜索其他仓库名称或所有者。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(repositories) { repository in
                            RepositorySearchRow(
                                repository: repository,
                                isSelected: repository.id == selectedRepositoryID,
                                onSelect: onSelect
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.white)
        .onAppear {
            isSearchFocused = true
        }
        .onExitCommand(perform: onClose)
    }
}

private struct RepositorySearchRow: View {
    let repository: Repository
    let isSelected: Bool
    let onSelect: (Repository) -> Void

    var body: some View {
        Button {
            onSelect(repository)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(repository.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GitMateTheme.textPrimary)
                        .lineLimit(1)
                    Text(repository.fullName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(GitMateTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(GitMateTheme.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(isSelected ? GitMateTheme.accentSoft : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(repository.fullName)
        .accessibilityValue(isSelected ? "已选中" : "未选中")
        .accessibilityHint("选择此仓库")
    }
}
