import AppKit
import GitMateCore
import SwiftUI

struct FileContentView: View {
    @Bindable var viewModel: FilesCommitsViewModel

    var body: some View {
        VStack(spacing: 0) {
            metadataBar
            Divider()
            content
        }
        .background(.white)
    }

    private var metadataBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(GitMateTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.state.selectedFilePath ?? "选择文件")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(fileMetadata)
                    .font(.system(size: 11.5))
                    .foregroundStyle(GitMateTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 10)
            Label("只读", systemImage: "eye")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(GitMateTheme.accent)
                .padding(.horizontal, 9)
                .frame(height: 25)
                .background(GitMateTheme.accentSoft)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 17)
        .frame(height: 58)
        .background(.white)
    }

    private var fileMetadata: String {
        var values: [String] = []
        if let file = viewModel.state.selectedFile {
            values.append(byteCount(file.byteCount))
        }
        if let commit = viewModel.state.commits.first {
            values.append("仓库最近提交 \(commit.shortHash)")
        } else {
            values.append("当前修订 HEAD")
        }
        return values.joined(separator: " · ")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state.fileDisplayState {
        case .empty:
            emptyState(
                symbol: "cursorarrow.click.2",
                title: "从文件树选择文件",
                message: "文件内容会以只读方式显示。"
            )
        case let .loading(path):
            emptyState(
                symbol: "doc.text.magnifyingglass",
                title: "正在读取 \(URL(fileURLWithPath: path).lastPathComponent)",
                message: "正在从当前修订读取文件内容。"
            ) {
                ProgressView()
                    .controlSize(.small)
            }
        case let .text(path, text, _):
            textContent(text, path: path)
        case let .binary(path, byteCount):
            emptyState(
                symbol: "doc.zipper",
                title: "二进制文件无法预览",
                message: "\(path) · \(self.byteCount(byteCount))"
            )
        case let .tooLarge(path, byteCount):
            emptyState(
                symbol: "doc.badge.ellipsis",
                title: "文件过大，未加载预览",
                message: "\(path) · \(self.byteCount(byteCount))"
            )
        case let .invalidUTF8(path, byteCount):
            emptyState(
                symbol: "text.badge.xmark",
                title: "文件不是有效 UTF-8 文本",
                message: "\(path) · \(self.byteCount(byteCount))"
            )
        case let .failed(_, message):
            emptyState(
                symbol: "exclamationmark.triangle.fill",
                title: "文件内容无法显示",
                message: message
            )
        }
    }

    private func textContent(_ text: String, path: String) -> some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 15) {
                Text(lineNumbers(for: text))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(GitMateTheme.textTertiary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.disabled)

                Rectangle()
                    .fill(GitMateTheme.border)
                    .frame(width: 1)

                Text(highlighted(text, path: path))
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(GitMateTheme.textPrimary)
                    .textSelection(.enabled)
            }
            .fixedSize(horizontal: true, vertical: true)
            .padding(18)
        }
        .scrollIndicators(.visible)
        .background(
            Color(red: 0.985, green: 0.989, blue: 0.995)
        )
        .accessibilityLabel("文件内容，只读")
    }

    private func highlighted(
        _ text: String,
        path: String
    ) -> AttributedString {
        let storage = NSMutableAttributedString(
            string: text,
            attributes: [
                .foregroundColor: NSColor(
                    red: 0.075,
                    green: 0.105,
                    blue: 0.16,
                    alpha: 1
                )
            ]
        )
        let codeExtensions = [
            "swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs"
        ]
        guard codeExtensions.contains(
            URL(fileURLWithPath: path).pathExtension.lowercased()
        ) else {
            return AttributedString(storage)
        }
        let pattern =
            #"(?m)\b(import|struct|class|enum|protocol|extension|func|let|var|if|else|guard|return|async|await|throws|public|private)\b|(\"(?:\\.|[^\"\\])*\")|(//.*)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return AttributedString(storage)
        }
        let fullRange = NSRange(location: 0, length: storage.length)
        expression.enumerateMatches(
            in: text,
            range: fullRange
        ) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(
                .foregroundColor,
                value: NSColor.systemBlue,
                range: match.range
            )
        }
        return AttributedString(storage)
    }

    private func lineNumbers(for text: String) -> String {
        let count = max(text.components(separatedBy: "\n").count, 1)
        return (1...count).map(String.init).joined(separator: "\n")
    }

    private func emptyState<Accessory: View>(
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
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(GitMateTheme.textPrimary)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(GitMateTheme.textSecondary)
                .multilineTextAlignment(.center)
            accessory()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(
        symbol: String,
        title: String,
        message: String
    ) -> some View {
        emptyState(symbol: symbol, title: title, message: message) {
            EmptyView()
        }
    }

    private func byteCount(_ value: Int) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(value),
            countStyle: .file
        )
    }
}
