import GitMateCore
import SwiftUI

struct CommitDiffView: View {
    @Bindable var viewModel: FilesCommitsViewModel

    var body: some View {
        Group {
            if viewModel.state.selectedCommitHash == nil {
                emptyState
            } else if viewModel.state.selectedCommit == nil
                && viewModel.state.selectedDiff == nil {
                loadingState
            } else {
                detail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
        .accessibilityIdentifier("workspace.commits.diff")
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 35, weight: .medium))
                .foregroundStyle(GitMateTheme.accent)
            Text("选择一条提交")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(GitMateTheme.textPrimary)
            Text("可查看完整说明、文件统计和只读差异。")
                .font(.system(size: 12.5))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 11) {
            ProgressView()
            Text("正在读取提交详情")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let detail = viewModel.state.selectedCommit {
                    commitHeader(detail)
                }
                if let diff = viewModel.state.selectedDiff {
                    diffSummary(diff)
                    changedFiles(diff.files)
                    patch(diff.patch)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.visible)
    }

    private func commitHeader(
        _ detail: GitCommitDetail
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                GitMateAvatar(url: nil, size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.commit.subject)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(GitMateTheme.textPrimary)
                    Text(
                        "\(detail.commit.authorName) · \(detail.commit.authoredAt.formatted(date: .long, time: .shortened)) · \(detail.commit.shortHash)"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(GitMateTheme.textSecondary)
                }
            }

            if detail.message != detail.commit.subject {
                Text(detail.message)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(GitMateTheme.textPrimary)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GitMateTheme.panel)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 9,
                            style: .continuous
                        )
                    )
            }
        }
    }

    private func diffSummary(_ diff: GitDiff) -> some View {
        HStack(spacing: 10) {
            summaryBadge(
                "\(diff.files.count) 个文件",
                symbol: "doc.on.doc",
                color: GitMateTheme.accent
            )
            summaryBadge(
                "+\(diff.additions)",
                symbol: "plus",
                color: GitMateTheme.success
            )
            summaryBadge(
                "−\(diff.deletions)",
                symbol: "minus",
                color: GitMateTheme.danger
            )
            Spacer()
        }
    }

    private func summaryBadge(
        _ title: String,
        symbol: String,
        color: Color
    ) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }

    private func changedFiles(
        _ files: [GitChangedFile]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("变更文件")
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(GitMateTheme.textPrimary)
            ForEach(files, id: \.path) { file in
                HStack(spacing: 8) {
                    Image(
                        systemName: file.isBinary
                            ? "doc.zipper"
                            : "doc.text"
                    )
                    .foregroundStyle(GitMateTheme.textSecondary)
                    Text(file.path)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(GitMateTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if let additions = file.additions {
                        Text("+\(additions)")
                            .foregroundStyle(GitMateTheme.success)
                    }
                    if let deletions = file.deletions {
                        Text("−\(deletions)")
                            .foregroundStyle(GitMateTheme.danger)
                    }
                }
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(GitMateTheme.panel)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 7,
                        style: .continuous
                    )
                )
            }
        }
    }

    private func patch(_ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("差异")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                Spacer()
                if viewModel.state.isSelectedDiffTruncated {
                    Label("内容已截断", systemImage: "scissors")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(GitMateTheme.warning)
                }
            }

            ScrollView(.horizontal) {
                Text(value.isEmpty ? "此提交没有文本差异。" : value)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(GitMateTheme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(14)
            }
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(red: 0.975, green: 0.982, blue: 0.992)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 9,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 9,
                    style: .continuous
                )
                .stroke(GitMateTheme.border, lineWidth: 1)
            }
            .accessibilityLabel("提交差异纯文本")
        }
    }
}
