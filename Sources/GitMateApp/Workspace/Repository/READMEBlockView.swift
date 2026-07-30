import AppKit
import GitMateCore
import SwiftUI
import WebKit

struct READMEBlockView: View {
    let block: READMEBlock
    let imageAuthorization: READMEImageAuthorization?

    init(
        block: READMEBlock,
        imageAuthorization: READMEImageAuthorization? = nil
    ) {
        self.block = block
        self.imageAuthorization = imageAuthorization
    }

    var body: some View {
        switch block {
        case let .heading(level, _, text):
            Text(verbatim: text)
                .font(headingFont(level: level))
                .foregroundStyle(GitMateTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level == 1 ? 10 : 4)
                .accessibilityAddTraits(.isHeader)

        case let .paragraph(content):
            let presentation = READMEInlinePresentation(content: content)
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: presentation.plainText)
                    .font(.system(size: 14))
                    .foregroundStyle(GitMateTheme.textPrimary)
                    .lineSpacing(5)
                    .textSelection(.enabled)

                if !presentation.externalLinks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(
                            Array(presentation.externalLinks.enumerated()),
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
                Text(verbatim: value)
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
                Text(verbatim: codeLanguageTitle(language))
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
                Text(verbatim: value)
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
        READMEImageView(
            url: url,
            alt: alt,
            authorization: imageAuthorization
        )
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
        Text(verbatim: value)
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
                        Text(verbatim: task.text)
                            .textSelection(.enabled)
                    } else {
                        Text(ordered ? "\(index + 1)." : "•")
                            .fontWeight(.semibold)
                            .foregroundStyle(GitMateTheme.textSecondary)
                        Text(verbatim: item)
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
                Text(verbatim: link.title)
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

}

private struct READMEImageView: View {
    private enum Phase {
        case loading
        case raster(NSImage)
        case vector(Data)
        case failed
    }

    let url: URL
    let alt: String
    let authorization: READMEImageAuthorization?

    @State private var phase = Phase.loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                placeholder(
                    symbol: "photo",
                    title: alt.isEmpty ? "正在加载图片" : alt,
                    showsProgress: true
                )
            case let .raster(image):
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 760, maxHeight: 380)
            case let .vector(data):
                READMEVectorImageView(data: data, baseURL: url)
                    .frame(
                        width: isCompactBadge
                            ? compactBadgeWidth
                            : nil,
                        height: isCompactBadge ? 30 : 380
                    )
                    .frame(maxWidth: 760, alignment: .leading)
            case .failed:
                placeholder(
                    symbol: "photo.badge.exclamationmark",
                    title: alt.isEmpty
                        ? "图片加载失败"
                        : "\(alt) · 加载失败",
                    showsProgress: false
                )
            }
        }
        .accessibilityLabel(alt.isEmpty ? "README 图片" : alt)
        .task(id: url) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        phase = .loading
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue(
                "GitMate/1.0",
                forHTTPHeaderField: "User-Agent"
            )
            if let authorizationHeader = authorization?
                .authorizationHeader(for: url) {
                request.setValue(
                    authorizationHeader,
                    forHTTPHeaderField: "Authorization"
                )
            }
            let (data, response) = try await URLSession.shared.data(
                for: request
            )
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  !data.isEmpty else {
                phase = .failed
                return
            }
            let mimeType = response.mimeType?.lowercased() ?? ""
            if mimeType.contains("svg")
                || url.pathExtension.lowercased() == "svg"
                || Data(data.prefix(256)).containsSVGMarkup {
                phase = .vector(data)
            } else if let image = NSImage(data: data) {
                phase = .raster(image)
            } else {
                phase = .failed
            }
        } catch is CancellationError {
            return
        } catch {
            phase = .failed
        }
    }

    private var isCompactBadge: Bool {
        url.host?.caseInsensitiveCompare("img.shields.io")
            == .orderedSame
    }

    private var compactBadgeWidth: CGFloat {
        CGFloat(min(max(110, alt.count * 9 + 46), 260))
    }

    private func placeholder(
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
}

private struct READMEVectorImageView: NSViewRepresentable {
    let data: Data
    let baseURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences
            .allowsContentJavaScript = false
        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )
        webView.underPageBackgroundColor = .clear
        return webView
    }

    func updateNSView(
        _ webView: WKWebView,
        context: Context
    ) {
        guard context.coordinator.loadedData != data else {
            return
        }
        context.coordinator.loadedData = data
        let encoded = data.base64EncodedString()
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        html, body {
          margin: 0;
          width: 100%;
          height: 100%;
          overflow: hidden;
          background: transparent;
        }
        img {
          display: block;
          width: 100%;
          height: 100%;
          object-fit: contain;
          object-position: left center;
        }
        </style>
        </head>
        <body>
        <img alt="" src="data:image/svg+xml;base64,\(encoded)">
        </body>
        </html>
        """
        webView.loadHTMLString(
            html,
            baseURL: baseURL.deletingLastPathComponent()
        )
    }

    final class Coordinator {
        var loadedData: Data?
    }
}

private extension Data {
    var containsSVGMarkup: Bool {
        guard let prefix = String(
            data: self,
            encoding: .utf8
        )?.lowercased() else {
            return false
        }
        return prefix.contains("<svg")
    }
}
