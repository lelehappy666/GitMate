import AppKit
import GitMateCore
import PDFKit
import SwiftUI
import WebKit

struct RasterImagePreviewView: View {
    let data: Data

    @State private var manualZoom: Double?
    @State private var fitZoom = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    manualZoom = max(
                        (manualZoom ?? fitZoom) / 1.25,
                        0.1
                    )
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                Text(
                    manualZoom.map {
                        "\(Int($0 * 100))%"
                    } ?? "自适应"
                )
                    .font(
                        .system(
                            size: 11,
                            weight: .semibold,
                            design: .monospaced
                        )
                    )
                    .frame(width: 58)
                Button {
                    manualZoom = min(
                        (manualZoom ?? fitZoom) * 1.25,
                        8
                    )
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                Button("实际大小") {
                    manualZoom = 1
                }
                Button("适合窗口") {
                    manualZoom = nil
                }
                Spacer()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.white)

            Divider()

            if let image = NSImage(data: data) {
                imageCanvas(image)
            } else {
                previewUnavailable(
                    title: "图片无法解码",
                    message: "文件签名有效，但系统图片解码器无法打开该内容。"
                )
            }
        }
    }

    private func imageCanvas(_ image: NSImage) -> some View {
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width - 48, 1)
            let availableHeight = max(geometry.size.height - 48, 1)
            let nextFitZoom = min(
                availableWidth / max(image.size.width, 1),
                availableHeight / max(image.size.height, 1),
                1
            )
            let resolvedZoom = manualZoom ?? nextFitZoom

            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(
                        width: max(image.size.width * resolvedZoom, 1),
                        height: max(image.size.height * resolvedZoom, 1)
                    )
                    .frame(
                        minWidth: max(geometry.size.width, 1),
                        minHeight: max(geometry.size.height, 1),
                        alignment: .center
                    )
            }
            .background(GitMateTheme.panel)
            .onAppear {
                fitZoom = nextFitZoom
            }
            .onChange(of: geometry.size) { _, _ in
                fitZoom = nextFitZoom
            }
        }
    }
}

struct PDFFilePreviewView: View {
    let data: Data
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(GitMateTheme.textTertiary)
                TextField("搜索 PDF", text: $query)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 260)
                Spacer()
                Label("自动适配", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.white)

            Divider()

            PDFDocumentRepresentable(data: data, query: query)
        }
    }
}

private struct PDFDocumentRepresentable: NSViewRepresentable {
    let data: Data
    let query: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        update(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        update(view, coordinator: context.coordinator)
    }

    private func update(_ view: PDFView, coordinator: Coordinator) {
        let fingerprint = data.hashValue
        if coordinator.fingerprint != fingerprint {
            view.document = PDFDocument(data: data)
            view.autoScales = true
            coordinator.fingerprint = fingerprint
            coordinator.query = ""
        }
        guard coordinator.query != query else { return }
        coordinator.query = query
        let trimmed = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty,
              let selection = view.document?
                .findString(trimmed, withOptions: .caseInsensitive)
                .first
        else {
            view.setCurrentSelection(nil, animate: false)
            return
        }
        view.setCurrentSelection(selection, animate: true)
        view.scrollSelectionToVisible(nil)
    }

    final class Coordinator {
        var fingerprint: Int?
        var query = ""
    }
}

struct HTMLFilePreviewView: View {
    let document: FilePreviewDocument
    @State private var mode = Mode.preview

    private enum Mode: String, CaseIterable {
        case preview = "网页预览"
        case source = "源码"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("HTML 显示模式", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                Spacer()
                Label(
                    "脚本、网络和本地文件已禁用",
                    systemImage: "lock.shield"
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GitMateTheme.success)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.white)

            Divider()

            switch mode {
            case .preview:
                SafeHTMLPreviewView(
                    text: document.text ?? "",
                    treatsContentAsSVG: document.kind == .vectorImage
                )
            case .source:
                SourceFilePreviewView(
                    document: FilePreviewDocument(
                        path: document.path,
                        data: document.data,
                        text: document.text,
                        kind: .source(
                            document.kind == .vectorImage ? .xml : nil
                        ),
                        byteCount: document.byteCount
                    )
                )
            }
        }
    }
}

struct MarkdownFilePreviewView: View {
    let document: FilePreviewDocument

    private var markdownDocument: READMEDocument {
        READMEBlockParser().parse(document.text ?? "")
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(
                    Array(markdownDocument.blocks.enumerated()),
                    id: \.offset
                ) { _, block in
                    READMEBlockView(block: block)
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(.white)
        .accessibilityLabel("Markdown 文档预览")
    }
}

private struct SafeHTMLPreviewView: NSViewRepresentable {
    let text: String
    let treatsContentAsSVG: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let html = securedHTML
        let fingerprint = html.hashValue
        guard context.coordinator.fingerprint != fingerprint else {
            return
        }
        context.coordinator.fingerprint = fingerprint
        view.loadHTMLString(html, baseURL: nil)
    }

    private var securedHTML: String {
        let policy =
            "default-src 'none'; "
            + "style-src 'unsafe-inline' https: data:; "
            + "img-src data: blob: https:; "
            + "font-src data: https:; "
            + "media-src data: https:; "
            + "connect-src 'none'; "
            + "frame-src 'none'; "
            + "object-src 'none'; "
            + "script-src 'none';"
        let injectedHead = """
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="\(policy)">
        """

        if treatsContentAsSVG {
            return """
            <!doctype html>
            <html>
            <head>
            \(injectedHead)
            <style>
            html, body {
              margin: 0;
              width: 100%;
              height: 100%;
              overflow: auto;
              background: #fff;
            }
            main {
              display: grid;
              width: 100%;
              min-height: 100%;
              place-items: center;
            }
            svg { max-width: 100%; max-height: 100vh; }
            </style>
            </head>
            <body><main aria-label="SVG 预览">\(text)</main></body>
            </html>
            """
        }

        if let closingHead = text.range(
            of: "</head>",
            options: .caseInsensitive
        ) {
            var completeDocument = text
            completeDocument.insert(
                contentsOf: injectedHead,
                at: closingHead.lowerBound
            )
            return completeDocument
        }

        if let openingHTML = text.range(
            of: #"<html(?:\s[^>]*)?>"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            var completeDocument = text
            completeDocument.insert(
                contentsOf: "<head>\(injectedHead)</head>",
                at: openingHTML.upperBound
            )
            return completeDocument
        }

        return """
        <!doctype html>
        <html>
        <head>
        \(injectedHead)
        <style>
        html, body { margin: 0; min-height: 100%; background: #fff; }
        body {
          box-sizing: border-box;
          padding: 24px;
          color: #132033;
          font: 14px -apple-system, BlinkMacSystemFont, sans-serif;
        }
        img, svg { max-width: 100%; height: auto; }
        </style>
        </head>
        <body>\(text)</body>
        </html>
        """
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var fingerprint: Int?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (
                WKNavigationActionPolicy
            ) -> Void
        ) {
            decisionHandler(
                HTMLPreviewSecurityPolicy.allowsNavigation(
                    to: navigationAction.request.url
                ) ? .allow : .cancel
            )
        }
    }
}

@ViewBuilder
private func previewUnavailable(
    title: String,
    message: String
) -> some View {
    VStack(spacing: 10) {
        Image(systemName: "doc.badge.exclamationmark")
            .font(.system(size: 32))
            .foregroundStyle(GitMateTheme.accent)
        Text(title)
            .font(.system(size: 17, weight: .bold))
        Text(message)
            .font(.system(size: 12.5))
            .foregroundStyle(GitMateTheme.textSecondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(GitMateTheme.panel)
}
