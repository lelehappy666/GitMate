import GitMateCore
import SwiftUI

struct WorkingTreeView: View {
    @Bindable var workingTreeViewModel: WorkingTreeViewModel
    @Bindable var diffViewModel: FileDiffViewModel
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            HSplitView {
                fileList
                    .frame(minWidth: 340, idealWidth: 400)
                FileDiffView(viewModel: diffViewModel)
                    .frame(minWidth: 560)
            }
        }
        .background(.white)
        .accessibilityIdentifier("localGit.workingTree")
        .task {
            await workingTreeViewModel.refresh()
            workingTreeViewModel.startAutomaticRefresh()
        }
        .onDisappear {
            workingTreeViewModel.stopAutomaticRefresh()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("工作区变更")
                    .font(.system(size: 19, weight: .bold))
                if let branch = workingTreeViewModel.snapshot?.branch {
                    Text(
                        "\(branch.name ?? "分离 HEAD") · 领先 \(branch.ahead) / 落后 \(branch.behind)"
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
                }
            }

            Spacer()

            TextField("搜索文件", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onChange(of: searchText) { _, value in
                    workingTreeViewModel.updateSearch(value)
                }

            Picker(
                "状态",
                selection: $workingTreeViewModel.filter
            ) {
                Text("全部").tag(WorkingTreeFilter.all)
                Text("冲突").tag(WorkingTreeFilter.conflicted)
                Text("已暂存").tag(WorkingTreeFilter.staged)
                Text("未暂存").tag(WorkingTreeFilter.unstaged)
                Text("未跟踪").tag(WorkingTreeFilter.untracked)
            }
            .frame(width: 118)

            Button("取消暂存") {
                Task { await workingTreeViewModel.unstageSelection() }
            }
            .disabled(workingTreeViewModel.selection.isEmpty)

            Button("暂存所选") {
                Task { await workingTreeViewModel.stageSelection() }
            }
            .buttonStyle(.borderedProminent)
            .tint(GitMateTheme.accent)
            .disabled(workingTreeViewModel.selection.isEmpty)
        }
        .padding(.horizontal, 18)
        .frame(height: 72)
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(workingTreeViewModel.visibleFiles.count) 个文件")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GitMateTheme.textSecondary)
                Spacer()
                if case let .loading(received) =
                    workingTreeViewModel.snapshot?.untrackedScan
                {
                    ProgressView()
                        .controlSize(.small)
                    Text("扫描未跟踪 \(received)")
                        .font(.system(size: 10))
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 42)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(groupedCategories, id: \.category) { group in
                        sectionHeader(
                            group.category,
                            count: group.files.count
                        )
                        ForEach(group.files) { file in
                            WorkingTreeFileRow(
                                file: file,
                                isSelected: workingTreeViewModel.selection
                                    .contains(file.id),
                                onToggle: {
                                    workingTreeViewModel.toggleSelection(
                                        file.id
                                    )
                                },
                                onOpenDiff: {
                                    Task {
                                        await diffViewModel.select(
                                            path: file.path,
                                            source: file.category == .staged
                                                ? .index
                                                : .workingTree
                                        )
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
        .background(.white)
    }

    private var groupedCategories:
        [(category: WorkingTreeCategory, files: [WorkingTreeFile])]
    {
        let categories: [WorkingTreeCategory] = [
            .conflicted,
            .staged,
            .unstaged,
            .untracked
        ]
        return categories.compactMap { category in
            let files = workingTreeViewModel.visibleFiles.filter {
                $0.category == category
            }
            return files.isEmpty ? nil : (category, files)
        }
    }

    private func sectionHeader(
        _ category: WorkingTreeCategory,
        count: Int
    ) -> some View {
        HStack {
            Text(title(for: category))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(GitMateTheme.textSecondary)
            Text("\(count)")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(GitMateTheme.panel)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(GitMateTheme.canvas)
    }

    private func title(for category: WorkingTreeCategory) -> String {
        switch category {
        case .conflicted: return "冲突"
        case .staged: return "已暂存"
        case .unstaged: return "未暂存"
        case .untracked: return "未跟踪"
        }
    }
}
