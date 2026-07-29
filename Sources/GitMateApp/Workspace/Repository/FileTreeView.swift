import GitMateCore
import SwiftUI

struct FileTreeView: View {
    @Bindable var viewModel: FilesCommitsViewModel
    @State private var expandedDirectories = Set<String>()

    var body: some View {
        VStack(spacing: 0) {
            search
            Divider()
            tree
        }
        .background(.white)
        .accessibilityIdentifier("workspace.files.tree")
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(GitMateTheme.textTertiary)
            TextField("按路径搜索", text: pathQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !viewModel.state.pathQuery.isEmpty {
                Button {
                    viewModel.updatePathQuery("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(GitMateTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除路径搜索")
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 44)
        .background(GitMateTheme.panel)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 9,
                style: .continuous
            )
        )
        .padding(12)
        .accessibilityIdentifier("workspace.files.search")
    }

    private var pathQuery: Binding<String> {
        Binding(
            get: { viewModel.state.pathQuery },
            set: { viewModel.updatePathQuery($0) }
        )
    }

    @ViewBuilder
    private var tree: some View {
        if viewModel.state.isLoadingTree && viewModel.state.tree.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在读取文件树")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleEntries.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 29))
                    .foregroundStyle(GitMateTheme.textTertiary)
                Text(
                    viewModel.state.pathQuery.isEmpty
                        ? "仓库中没有可浏览文件"
                        : "没有匹配的路径"
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GitMateTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(visibleEntries) { entry in
                        entryRow(entry)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 9)
            }
            .scrollIndicators(.visible)
        }
    }

    private var visibleEntries: [GitFileEntry] {
        viewModel.state.filteredTree
            .filter { entry in
                if !viewModel.state.pathQuery.isEmpty {
                    return true
                }
                let components = entry.path.split(separator: "/")
                guard components.count > 1 else {
                    return true
                }
                var ancestors: [String] = []
                for index in 1..<components.count {
                    ancestors.append(
                        components.prefix(index).joined(separator: "/")
                    )
                }
                return ancestors.allSatisfy {
                    expandedDirectories.contains($0)
                }
            }
            .sorted {
                if $0.path.split(separator: "/").count
                    != $1.path.split(separator: "/").count {
                    return $0.path.split(separator: "/").count
                        < $1.path.split(separator: "/").count
                }
                if $0.kind == .directory && $1.kind != .directory {
                    return true
                }
                if $0.kind != .directory && $1.kind == .directory {
                    return false
                }
                return $0.path.localizedStandardCompare($1.path)
                    == .orderedAscending
            }
    }

    private func entryRow(_ entry: GitFileEntry) -> some View {
        Button {
            activate(entry)
        } label: {
            HStack(spacing: 7) {
                if entry.kind == .directory {
                    Image(
                        systemName: expandedDirectories.contains(entry.path)
                            ? "chevron.down"
                            : "chevron.right"
                    )
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 10)
                    .foregroundStyle(GitMateTheme.textTertiary)
                } else {
                    Color.clear.frame(width: 10, height: 1)
                }

                Image(systemName: symbol(for: entry))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(color(for: entry))
                    .frame(width: 17)

                Text(entry.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(GitMateTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.leading, indentation(for: entry))
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(
                viewModel.state.selectedFilePath == entry.path
                    ? GitMateTheme.accentSoft
                    : Color.clear
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 7,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: entry))
        .accessibilityHint(
            entry.kind == .file ? "显示只读文件内容" : "展开或收起目录"
        )
    }

    private func activate(_ entry: GitFileEntry) {
        if entry.kind == .directory {
            if expandedDirectories.remove(entry.path) == nil {
                expandedDirectories.insert(entry.path)
                Task {
                    let pathspec = entry.path.hasSuffix("/")
                        ? entry.path
                        : "\(entry.path)/"
                    await viewModel.loadTree(path: pathspec)
                }
            }
        } else if entry.kind == .file {
            Task {
                await viewModel.selectFile(path: entry.path)
            }
        }
    }

    private func indentation(for entry: GitFileEntry) -> CGFloat {
        CGFloat(max(entry.path.split(separator: "/").count - 1, 0)) * 14
    }

    private func symbol(for entry: GitFileEntry) -> String {
        switch entry.kind {
        case .directory:
            expandedDirectories.contains(entry.path)
                ? "folder.fill.badge.minus"
                : "folder.fill"
        case .file:
            "doc.text"
        case .submodule:
            "shippingbox"
        case .symlink:
            "link"
        }
    }

    private func color(for entry: GitFileEntry) -> Color {
        entry.kind == .directory
            ? GitMateTheme.accent
            : GitMateTheme.textSecondary
    }

    private func accessibilityLabel(for entry: GitFileEntry) -> String {
        let kind: String
        switch entry.kind {
        case .directory:
            kind = "目录"
        case .file:
            kind = "文件"
        case .submodule:
            kind = "子模块"
        case .symlink:
            kind = "符号链接"
        }
        return "\(kind)，\(entry.path)"
    }
}
