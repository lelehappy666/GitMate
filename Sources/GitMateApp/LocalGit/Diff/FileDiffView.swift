import GitMateCore
import SwiftUI

struct FileDiffView: View {
    @Bindable var viewModel: FileDiffViewModel
    @State private var layout: DiffLayout = .unified

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                if viewModel.isLoading {
                    ProgressView("正在读取差异…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error {
                    ContentUnavailableView(
                        "无法读取差异",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error.message)
                    )
                } else if let document = viewModel.document {
                    documentView(document)
                } else {
                    ContentUnavailableView(
                        "选择文件查看差异",
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.white)
        .accessibilityIdentifier("localGit.diff")
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.selectedPath ?? "文件差异")
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let document = viewModel.document {
                    Text(
                        "+\(document.addedLineCount)  −\(document.deletedLineCount)"
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
                }
            }
            .frame(
                minWidth: 110,
                maxWidth: .infinity,
                alignment: .leading
            )

            Picker("差异布局", selection: $layout) {
                Text("统一").tag(DiffLayout.unified)
                Text("并排").tag(DiffLayout.sideBySide)
            }
            .pickerStyle(.segmented)
            .frame(width: 106)

            Toggle(
                "空白",
                isOn: Binding(
                    get: { viewModel.options.ignoreWhitespace },
                    set: {
                        viewModel.options.ignoreWhitespace = $0
                        Task { await viewModel.reload() }
                    }
                )
            )
            .toggleStyle(.checkbox)
            .font(.system(size: 10))
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    @ViewBuilder
    private func documentView(_ document: GitDiffDocument) -> some View {
        if document.loadingMode == .summary {
            VStack(spacing: 14) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 34))
                    .foregroundStyle(GitMateTheme.accent)
                Text("差异较大，已切换为摘要")
                    .font(.system(size: 16, weight: .bold))
                Text(
                    "\(document.lineCount) 行 · \(ByteCountFormatter.string(fromByteCount: Int64(document.byteCount), countStyle: .file))"
                )
                .foregroundStyle(GitMateTheme.textSecondary)
                Text("可分段加载或使用外部编辑器查看完整内容。")
                    .font(.system(size: 12))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(spacing: 12) {
                    ForEach(document.hunks) { hunk in
                        DiffHunkView(hunk: hunk)
                            .frame(
                                minWidth: layout == .sideBySide ? 820 : 560
                            )
                    }
                }
                .padding(14)
            }
            .background(GitMateTheme.panel.opacity(0.45))
        }
    }
}

private enum DiffLayout {
    case unified
    case sideBySide
}
