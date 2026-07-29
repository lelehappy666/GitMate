import GitMateCore
import SwiftUI

struct ConflictResolverView: View {
    @Bindable var viewModel: ConflictResolutionViewModel
    let service: GitConflictService
    let repositoryURL: URL
    var onOpenExternalEditor: (URL) -> Void = { _ in }

    @State private var pendingBinarySide: ConflictSide?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                fileList
                    .frame(minWidth: 240, idealWidth: 280)
                editorArea
                    .frame(minWidth: 720)
            }
        }
        .background(.white)
        .accessibilityIdentifier("localGit.conflicts")
        .task { await viewModel.refresh() }
        .confirmationDialog(
            "整文件选择将覆盖当前工作区版本，是否继续？",
            isPresented: Binding(
                get: { pendingBinarySide != nil },
                set: {
                    if !$0 {
                        pendingBinarySide = nil
                    }
                }
            )
        ) {
            Button("确认选择", role: .destructive) {
                runBinaryChoice()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("解决冲突")
                    .font(.system(size: 20, weight: .bold))
                Text("三方内容来自 Git index，保存后自动标记已解决")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            Spacer()
            Text("剩余 \(viewModel.files.count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
        .padding(.horizontal, 20)
        .frame(height: 72)
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(viewModel.files) { file in
                    Button {
                        Task { await viewModel.select(path: file.path) }
                    } label: {
                        HStack {
                            Image(
                                systemName: file.isBinary
                                    ? "doc.badge.gearshape"
                                    : "doc.text"
                            )
                            Text(file.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GitMateTheme.textPrimary)
                        .padding(11)
                        .background(
                            file.path == viewModel.selectedPath
                                ? GitMateTheme.accentSoft
                                : .white
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: GitMateTheme.compactCornerRadius
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .background(GitMateTheme.panel.opacity(0.45))
    }

    @ViewBuilder
    private var editorArea: some View {
        if let document = viewModel.document {
            VStack(spacing: 12) {
                if document.isBinary {
                    binaryResolver(document)
                } else {
                    textResolver(document)
                }
                if let error = viewModel.error {
                    Label(
                        error.message,
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(GitMateTheme.danger)
                }
            }
            .padding(14)
        } else {
            ContentUnavailableView(
                "选择冲突文件",
                systemImage: "arrow.triangle.merge"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func textResolver(
        _ document: GitConflictDocument
    ) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button("采用当前") { viewModel.adoptCurrent() }
                Button("采用传入") { viewModel.adoptIncoming() }
                Button("同时保留") { viewModel.keepBoth() }
                Spacer()
                Button("用外部编辑器打开") {
                    onOpenExternalEditor(
                        repositoryURL.appending(path: document.path)
                    )
                }
                Button("保存并标记已解决") {
                    Task { await viewModel.saveText() }
                }
                .buttonStyle(.borderedProminent)
                .tint(GitMateTheme.accent)
            }

            HSplitView {
                ConflictEditorPane(
                    title: "当前",
                    text: document.currentText,
                    isEditable: false
                )
                ConflictEditorPane(
                    title: "传入",
                    text: document.incomingText,
                    isEditable: false
                )
                ConflictEditorPane(
                    title: "最终结果",
                    text: nil,
                    isEditable: true,
                    editableText: $viewModel.resultText
                )
            }

            DisclosureGroup("查看共同基准") {
                Text(document.baseText ?? "基准侧不存在")
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
    }

    private func binaryResolver(
        _ document: GitConflictDocument
    ) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 42))
                .foregroundStyle(GitMateTheme.warning)
            Text("这是二进制冲突")
                .font(.system(size: 20, weight: .bold))
            Text("二进制内容不能逐行合并，请选择保留当前或传入整文件。")
                .foregroundStyle(GitMateTheme.textSecondary)
            HStack {
                Button("保留当前整文件") {
                    pendingBinarySide = .current
                }
                Button("保留传入整文件") {
                    pendingBinarySide = .incoming
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runBinaryChoice() {
        guard let side = pendingBinarySide,
              let path = viewModel.selectedPath
        else {
            return
        }
        pendingBinarySide = nil
        let confirmation = service.wholeFileConfirmation(
            repositoryURL: repositoryURL,
            path: path,
            side: side
        )
        Task {
            await viewModel.chooseWholeFile(
                side: side,
                confirmation: confirmation
            )
        }
    }
}
