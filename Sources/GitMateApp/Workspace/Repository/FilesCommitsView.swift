import GitMateCore
import SwiftUI

struct FilesCommitsView: View {
    @Bindable var viewModel: FilesCommitsViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let message = viewModel.state.errorMessage {
                errorBanner(message)
            }
            modeContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GitMateTheme.canvas)
        .task {
            await viewModel.load()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: GitMateTheme.compactCornerRadius,
                    style: .continuous
                )
                .fill(GitMateTheme.accentSoft)
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(GitMateTheme.accent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("文件与提交")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                Text("只读浏览仓库内容、历史记录和纯文本差异")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }

            Spacer(minLength: 20)

            Picker("浏览模式", selection: modeBinding) {
                Label("文件", systemImage: "folder")
                    .tag(FilesCommitsMode.files)
                Label("提交", systemImage: "clock.arrow.circlepath")
                    .tag(FilesCommitsMode.commits)
            }
            .pickerStyle(.segmented)
            .frame(width: 230)
            .accessibilityIdentifier("workspace.files.mode")
        }
        .padding(.horizontal, 26)
        .frame(height: 82)
        .background(.white)
    }

    private var modeBinding: Binding<FilesCommitsMode> {
        Binding(
            get: { viewModel.state.mode },
            set: { viewModel.selectMode($0) }
        )
    }

    @ViewBuilder
    private var modeContent: some View {
        switch viewModel.state.mode {
        case .files:
            HStack(spacing: 0) {
                FileTreeView(viewModel: viewModel)
                    .frame(width: 310)
                Divider()
                FileContentView(viewModel: viewModel)
            }
        case .commits:
            HStack(spacing: 0) {
                CommitListView(viewModel: viewModel)
                    .frame(width: 430)
                Divider()
                CommitDiffView(viewModel: viewModel)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(GitMateTheme.textPrimary)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(GitMateTheme.warning.opacity(0.13))
    }
}
