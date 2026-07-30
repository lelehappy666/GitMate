import GitMateCore
import SwiftUI

struct READMEView: View {
    @Bindable var viewModel: READMEViewModel
    let imageAccessToken: String

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.state.loadPhase == .loaded,
               let message = viewModel.state.nonBlockingErrorMessage
            {
                nonBlockingErrorBanner(message)
                Divider()
            }
            content
        }
        .background(GitMateTheme.canvas)
        .accessibilityIdentifier("workspace.repository.readme")
        .task {
            await viewModel.load()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: GitMateTheme.compactCornerRadius,
                    style: .continuous
                )
                .fill(GitMateTheme.accentSoft)
                Image(systemName: "text.document")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(GitMateTheme.accent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("README")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                Text("安全渲染仓库说明，不执行 HTML 或脚本")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }

            Spacer(minLength: 16)

            loadBadge
        }
        .padding(.horizontal, 26)
        .frame(height: 82)
        .background(.white)
    }

    private func nonBlockingErrorBanner(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(GitMateTheme.warning)
            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 26)
        .frame(minHeight: 42)
        .background(.white)
        .accessibilityIdentifier("workspace.repository.readme.background-error")
    }

    @ViewBuilder
    private var loadBadge: some View {
        switch viewModel.state.loadPhase {
        case .idle, .loading:
            Label("正在读取", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(GitMateTheme.textSecondary)
        case .loaded:
            Label("文档已载入", systemImage: "checkmark.circle.fill")
                .foregroundStyle(GitMateTheme.success)
        case .empty:
            Label("暂无内容", systemImage: "doc")
                .foregroundStyle(GitMateTheme.textSecondary)
        case .failed:
            Label("读取失败", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(GitMateTheme.danger)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state.loadPhase {
        case .idle, .loading:
            stateView(
                symbol: "text.document",
                title: "正在读取 README",
                message: "正在准备安全的文档内容。"
            ) {
                ProgressView()
                    .controlSize(.small)
            }
        case .empty:
            stateView(
                symbol: "doc",
                title: "这个仓库还没有 README",
                message: "添加 README 后，可在这里浏览目录、代码和图片。"
            )
        case let .failed(message):
            stateView(
                symbol: "exclamationmark.triangle.fill",
                title: "README 无法显示",
                message: message
            ) {
                retryButton
            }
        case .loaded:
            if let document = viewModel.state.document {
                documentContent(document)
            } else {
                stateView(
                    symbol: "doc",
                    title: "这个仓库还没有 README",
                    message: "当前没有可显示的文档内容。"
                )
            }
        }
    }

    private func documentContent(
        _ document: READMEDocument
    ) -> some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                outline(document.outline, proxy: proxy)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 15) {
                        ForEach(
                            Array(document.blocks.enumerated()),
                            id: \.offset
                        ) { index, block in
                            READMEBlockView(
                                block: block,
                                imageAccessToken: imageAccessToken
                            )
                                .id(
                                    blockAnchor(block)
                                        ?? "readme-block-\(index)"
                                )
                        }
                    }
                    .frame(maxWidth: 780, alignment: .topLeading)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.visible)
            }
        }
    }

    private func outline(
        _ items: READMEOutline,
        proxy: ScrollViewProxy
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("目录")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(GitMateTheme.textPrimary)
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 11)

            if items.isEmpty {
                Text("此文档没有标题")
                    .font(.system(size: 12))
                    .foregroundStyle(GitMateTheme.textTertiary)
                    .padding(.horizontal, 18)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(items, id: \.id) { item in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(item.id, anchor: .top)
                                }
                            } label: {
                                Text(item.title)
                                    .font(
                                        .system(
                                            size: 12,
                                            weight: item.level == 1
                                                ? .semibold
                                                : .medium
                                        )
                                    )
                                    .foregroundStyle(
                                        item.level == 1
                                            ? GitMateTheme.textPrimary
                                            : GitMateTheme.textSecondary
                                    )
                                    .lineLimit(2)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                                    .padding(.leading, CGFloat(item.level - 1) * 11)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("定位到对应标题")
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(width: 214)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.white)
        .accessibilityIdentifier("workspace.repository.readme.outline")
    }

    private func blockAnchor(
        _ block: READMEBlock
    ) -> String? {
        guard case let .heading(_, id, _) = block else {
            return nil
        }
        return id
    }

    private func stateView<Accessory: View>(
        symbol: String,
        title: String,
        message: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        VStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(GitMateTheme.accent)
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(GitMateTheme.textPrimary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(GitMateTheme.textSecondary)
                .multilineTextAlignment(.center)
            accessory()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stateView(
        symbol: String,
        title: String,
        message: String
    ) -> some View {
        stateView(
            symbol: symbol,
            title: title,
            message: message
        ) {
            EmptyView()
        }
    }

    @ViewBuilder
    private var retryButton: some View {
        if let action = viewModel.state.retryAction {
            Button {
                Task {
                    await viewModel.load()
                }
            } label: {
                Label(action.title, systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(GitMateTheme.accent)
            .accessibilityLabel(action.accessibilityLabel)
            .accessibilityIdentifier(action.accessibilityIdentifier)
        }
    }
}
