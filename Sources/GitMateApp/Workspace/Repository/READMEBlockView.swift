import AppKit
import GitMateCore
import SwiftUI

struct READMEBlockView: View {
    let block: READMEBlock

    var body: some View {
        switch block {
        case let .heading(level, _, text):
            inlineText(text)
                .font(headingFont(level: level))
                .foregroundStyle(GitMateTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level == 1 ? 10 : 4)
                .accessibilityAddTraits(.isHeader)

        case let .paragraph(content):
            VStack(alignment: .leading, spacing: 8) {
                inlineText(content.text)
                    .font(.system(size: 14))
                    .foregroundStyle(GitMateTheme.textPrimary)
                    .lineSpacing(5)
                    .textSelection(.enabled)

                if !content.links.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(
                            Array(content.links.enumerated()),
                            id: \.offset
                        ) { _, link in
                            externalLink(link)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case let .code(language, value):
            codeBlock(language: language, value: value)

        case let .image(url, alt):
            readmeImage(url: url, alt: alt)

        case let .table(headers, rows):
            table(headers: headers, rows: rows)

        case let .list(ordered, items):
            list(ordered: ordered, items: items)

        case let .quote(value):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(GitMateTheme.accent)
                    .frame(width: 4)
                inlineText(value)
                    .font(.system(size: 14))
                    .italic()
                    .foregroundStyle(GitMateTheme.textSecondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)

        case .divider:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            .system(size: 27, weight: .bold)
        case 2:
            .system(size: 22, weight: .bold)
        case 3:
            .system(size: 18, weight: .bold)
        default:
            .system(size: 15, weight: .semibold)
        }
    }

    private func codeBlock(
        language: String?,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(codeLanguageTitle(language))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GitMateTheme.textSecondary)
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(GitMateTheme.accent)
                .accessibilityLabel("复制代码")
            }
            .padding(.horizontal, 13)
            .frame(height: 36)

            Divider()

            ScrollView(.horizontal) {
                Text(value)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(GitMateTheme.textPrimary)
                    .textSelection(.enabled)
                    .padding(14)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .background(GitMateTheme.panel)
        .clipShape(
            RoundedRectangle(
                cornerRadius: GitMateTheme.compactCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: GitMateTheme.compactCornerRadius,
                style: .continuous
            )
            .stroke(GitMateTheme.border, lineWidth: 1)
        }
    }

    private func readmeImage(
        url: URL,
        alt: String
    ) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 760, maxHeight: 380)
                    .accessibilityLabel(
                        alt.isEmpty ? "README 图片" : alt
                    )
            case .empty:
                imagePlaceholder(
                    symbol: "photo",
                    title: alt.isEmpty ? "正在加载图片" : alt,
                    showsProgress: true
                )
            case .failure:
                imagePlaceholder(
                    symbol: "photo.badge.exclamationmark",
                    title: alt.isEmpty ? "图片加载失败" : "\(alt) · 加载失败",
                    showsProgress: false
                )
            @unknown default:
                imagePlaceholder(
                    symbol: "photo",
                    title: "无法显示图片",
                    showsProgress: false
                )
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .clipShape(
            RoundedRectangle(
                cornerRadius: GitMateTheme.compactCornerRadius,
                style: .continuous
            )
        )
    }

    private func imagePlaceholder(
        symbol: String,
        title: String,
        showsProgress: Bool
    ) -> some View {
        HStack(spacing: 10) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: symbol)
                    .foregroundStyle(GitMateTheme.textTertiary)
            }
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: 760, minHeight: 88, alignment: .leading)
        .background(GitMateTheme.panel)
        .overlay {
            RoundedRectangle(
                cornerRadius: GitMateTheme.compactCornerRadius,
                style: .continuous
            )
            .stroke(GitMateTheme.border, lineWidth: 1)
        }
    }

    private func table(
        headers: [String],
        rows: [[String]]
    ) -> some View {
        ScrollView(.horizontal) {
            Grid(
                alignment: .leading,
                horizontalSpacing: 0,
                verticalSpacing: 0
            ) {
                GridRow {
                    ForEach(
                        Array(headers.enumerated()),
                        id: \.offset
                    ) { _, header in
                        tableCell(header, isHeader: true)
                    }
                }

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider()
                    GridRow {
                        ForEach(
                            Array(row.enumerated()),
                            id: \.offset
                        ) { _, value in
                            tableCell(value, isHeader: false)
                        }
                    }
                }
            }
            .background(.white)
            .fixedSize(horizontal: true, vertical: false)
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: GitMateTheme.compactCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: GitMateTheme.compactCornerRadius,
                style: .continuous
            )
            .stroke(GitMateTheme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("README 表格")
    }

    private func tableCell(
        _ value: String,
        isHeader: Bool
    ) -> some View {
        inlineText(value)
            .font(.system(size: 12.5, weight: isHeader ? .semibold : .regular))
            .foregroundStyle(GitMateTheme.textPrimary)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .frame(minWidth: 128, minHeight: 38, alignment: .leading)
            .background(isHeader ? GitMateTheme.panel : .white)
    }

    private func list(
        ordered: Bool,
        items: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    if let task = taskItem(item) {
                        Image(
                            systemName: task.isComplete
                                ? "checkmark.square.fill"
                                : "square"
                        )
                        .foregroundStyle(
                            task.isComplete
                                ? GitMateTheme.success
                                : GitMateTheme.textTertiary
                        )
                        inlineText(task.text)
                            .textSelection(.enabled)
                    } else {
                        Text(ordered ? "\(index + 1)." : "•")
                            .fontWeight(.semibold)
                            .foregroundStyle(GitMateTheme.textSecondary)
                        inlineText(item)
                            .textSelection(.enabled)
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(GitMateTheme.textPrimary)
            }
        }
        .padding(.leading, 4)
    }

    private func taskItem(
        _ value: String
    ) -> (isComplete: Bool, text: String)? {
        let lowered = value.lowercased()
        guard lowered.hasPrefix("[ ] ")
                || lowered.hasPrefix("[x] ")
        else {
            return nil
        }
        return (
            lowered.hasPrefix("[x] "),
            String(value.dropFirst(4))
        )
    }

    private func externalLink(
        _ link: READMEExternalLink
    ) -> some View {
        Link(destination: link.url) {
            HStack(spacing: 5) {
                Text(link.title)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(GitMateTheme.accent)
        }
        .buttonStyle(.plain)
        .accessibilityHint("在浏览器中打开外部链接")
    }

    private func codeLanguageTitle(_ language: String?) -> String {
        guard let language, !language.isEmpty else {
            return "代码"
        }
        return language
    }

    private func inlineText(_ value: String) -> Text {
        guard let attributed = try? AttributedString(
            markdown: value,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) else {
            return Text(value)
        }
        return Text(attributed)
    }
}
