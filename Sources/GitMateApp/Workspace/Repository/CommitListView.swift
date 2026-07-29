import AppKit
import GitMateCore
import SwiftUI

struct CommitListView: View {
    private enum TimeFilter: String, CaseIterable {
        case all = "全部时间"
        case sevenDays = "最近 7 天"
        case thirtyDays = "最近 30 天"
        case oneYear = "最近一年"
    }

    @Bindable var viewModel: FilesCommitsViewModel
    @State private var timeFilter = TimeFilter.all

    var body: some View {
        VStack(spacing: 0) {
            filters
            Divider()
            list
        }
        .background(.white)
        .accessibilityIdentifier("workspace.commits.list")
    }

    private var filters: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                filterField(
                    title: "作者",
                    symbol: "person",
                    binding: authorQuery
                )
                filterField(
                    title: "关键词或哈希",
                    symbol: "magnifyingglass",
                    binding: keywordQuery
                )
            }

            Picker("提交时间", selection: $timeFilter) {
                ForEach(TimeFilter.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: timeFilter) { _, _ in
                updateTimeFilter()
            }
        }
        .padding(12)
        .background(GitMateTheme.panel)
    }

    private func filterField(
        title: String,
        symbol: String,
        binding: Binding<String>
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(GitMateTheme.textTertiary)
            TextField(title, text: binding)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
        }
        .padding(.horizontal, 9)
        .frame(height: 34)
        .background(.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 8,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 8,
                style: .continuous
            )
            .stroke(GitMateTheme.border, lineWidth: 1)
        }
    }

    private var authorQuery: Binding<String> {
        Binding(
            get: { viewModel.state.commitAuthorQuery },
            set: {
                viewModel.updateCommitFilters(
                    authorQuery: $0,
                    keywordQuery: viewModel.state.commitKeywordQuery,
                    since: viewModel.state.commitSince,
                    until: viewModel.state.commitUntil
                )
            }
        )
    }

    private var keywordQuery: Binding<String> {
        Binding(
            get: { viewModel.state.commitKeywordQuery },
            set: {
                viewModel.updateCommitFilters(
                    authorQuery: viewModel.state.commitAuthorQuery,
                    keywordQuery: $0,
                    since: viewModel.state.commitSince,
                    until: viewModel.state.commitUntil
                )
            }
        )
    }

    @ViewBuilder
    private var list: some View {
        if viewModel.state.isLoadingCommits
            && viewModel.state.commits.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在读取提交历史")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.state.filteredCommits.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.system(size: 31))
                    .foregroundStyle(GitMateTheme.textTertiary)
                Text(
                    viewModel.state.commits.isEmpty
                        ? "暂无提交记录"
                        : "没有符合筛选条件的提交"
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GitMateTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.state.filteredCommits) { commit in
                        commitRow(commit)
                        Divider()
                            .padding(.leading, 59)
                    }

                    if viewModel.state.nextCommitCursor != nil {
                        HStack(spacing: 8) {
                            if viewModel.state.isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(
                                viewModel.state.isLoadingMore
                                    ? "正在加载更早提交"
                                    : "继续滚动以加载更多"
                            )
                            .font(.system(size: 11.5))
                            .foregroundStyle(GitMateTheme.textTertiary)
                        }
                        .frame(height: 45)
                        .onAppear {
                            Task {
                                await viewModel.loadMoreCommits()
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.visible)
        }
    }

    private func commitRow(_ commit: GitCommit) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Button {
                Task {
                    await viewModel.selectCommit(hash: commit.fullHash)
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    GitMateAvatar(url: nil, size: 34)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(commit.subject)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(GitMateTheme.textPrimary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 6) {
                            Text(commit.authorName)
                            Text("·")
                            Text(
                                commit.authoredAt.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                )
                            )
                        }
                        .font(.system(size: 11.5))
                        .foregroundStyle(GitMateTheme.textSecondary)

                        decorationRow(commit.decorations)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(commit.subject)，\(commit.authorName)，\(commit.shortHash)"
            )
            .accessibilityHint("显示提交说明、文件统计和差异")

            Button {
                copy(commit.fullHash)
            } label: {
                VStack(spacing: 4) {
                    Text(commit.shortHash)
                        .font(.system(size: 10.5, design: .monospaced))
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                }
                .foregroundStyle(GitMateTheme.accent)
                .padding(.horizontal, 7)
                .frame(minHeight: 34)
                .background(GitMateTheme.accentSoft)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 7,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("复制完整提交哈希 \(commit.fullHash)")
            .accessibilityIdentifier("workspace.commits.copyHash")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            viewModel.state.selectedCommitHash == commit.fullHash
                ? GitMateTheme.accentSoft.opacity(0.75)
                : Color.clear
        )
    }

    @ViewBuilder
    private func decorationRow(_ decorations: [String]) -> some View {
        if !decorations.isEmpty {
            HStack(spacing: 5) {
                ForEach(decorations.prefix(3), id: \.self) { decoration in
                    Label(
                        decoration,
                        systemImage: decoration.contains("tag:")
                            ? "tag.fill"
                            : "arrow.triangle.branch"
                    )
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(GitMateTheme.textSecondary)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(GitMateTheme.panel)
                    .clipShape(Capsule())
                    .lineLimit(1)
                }
            }
        }
    }

    private func updateTimeFilter() {
        let now = Date()
        let since: Date?
        switch timeFilter {
        case .all:
            since = nil
        case .sevenDays:
            since = Calendar.current.date(
                byAdding: .day,
                value: -7,
                to: now
            )
        case .thirtyDays:
            since = Calendar.current.date(
                byAdding: .day,
                value: -30,
                to: now
            )
        case .oneYear:
            since = Calendar.current.date(
                byAdding: .year,
                value: -1,
                to: now
            )
        }
        viewModel.updateCommitFilters(
            authorQuery: viewModel.state.commitAuthorQuery,
            keywordQuery: viewModel.state.commitKeywordQuery,
            since: since,
            until: nil
        )
    }

    private func copy(_ hash: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hash, forType: .string)
    }
}
