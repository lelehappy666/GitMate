import GitMateCore
import SwiftUI

struct CommitGraphBranchPicker: View {
    private enum SourceFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case local = "本地"
        case remote = "远程"

        var id: String { rawValue }
    }

    let catalog: CommitGraphBranchCatalog
    let projection: CommitGraphTraditionalBranchProjection
    let pinnedBranchIDs: Set<String>
    let selectBranch: (String) -> Void
    let togglePinned: (String) -> Void

    @State private var searchText = ""
    @State private var sourceFilter = SourceFilter.all
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("分支与上下文泳道")
                            .font(.system(size: 15, weight: .bold))
                        Text("选择任意本地或远程分支，不改变当前历史位置。")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(GitMateTheme.textSecondary)
                    }
                    Spacer()
                    Text("显示 \(projection.slots.count) / \(catalog.branches.count)")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(GitMateTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(GitMateTheme.accent.opacity(0.09))
                        .clipShape(Capsule())
                }

                TextField("搜索分支名称", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Picker("来源", selection: $sourceFilter) {
                    ForEach(SourceFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    if filteredBranches.isEmpty {
                        ContentUnavailableView(
                            "没有匹配分支",
                            systemImage: "arrow.triangle.branch",
                            description: Text("尝试更换关键词或来源筛选。")
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        ForEach(filteredBranches) { branch in
                            branchRow(branch)
                        }
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 420, height: 500)
        .background(.white)
    }

    private var filteredBranches: [CommitGraphBranchDescriptor] {
        catalog.branches.filter { branch in
            let sourceMatches: Bool = switch sourceFilter {
            case .all: true
            case .local: branch.source != .remote
            case .remote: branch.source == .remote
            }
            let normalized = searchText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return sourceMatches && (
                normalized.isEmpty
                    || branch.displayName.localizedCaseInsensitiveContains(
                        normalized
                    )
            )
        }
    }

    private func branchRow(
        _ branch: CommitGraphBranchDescriptor
    ) -> some View {
        let isVisible = projection.visibleBranches.contains {
            $0.id == branch.id
        }
        let isPinned = pinnedBranchIDs.contains(branch.id)
        let color = CommitGraphPalette.color(branch.lane)

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        branch.source == .remote
                            ? .white
                            : color.opacity(0.15)
                    )
                Circle()
                    .stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: 1.8,
                            dash: branch.source == .remote ? [3, 2] : []
                        )
                    )
                Image(
                    systemName: branch.isHead
                        ? "arrow.down.to.line.compact"
                        : "arrow.triangle.branch"
                )
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
            }
            .frame(width: 28, height: 28)

            Button {
                selectBranch(branch.id)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(branch.displayName)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(GitMateTheme.textPrimary)
                            .lineLimit(1)
                        if branch.isHead {
                            Text("HEAD")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(GitMateTheme.accent)
                        }
                    }
                    HStack(spacing: 7) {
                        Text(branch.source == .remote ? "远程" : "本地")
                        if branch.isMerged {
                            Text("已合并")
                        }
                        if isVisible {
                            Text("当前显示")
                                .foregroundStyle(GitMateTheme.success)
                        }
                    }
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                togglePinned(branch.id)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        isPinned
                            ? GitMateTheme.accent
                            : GitMateTheme.textSecondary
                    )
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "取消固定分支" : "固定到传统布局")
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
        .background(isVisible ? GitMateTheme.accent.opacity(0.055) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
