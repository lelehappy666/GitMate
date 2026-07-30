import AppKit
import GitMateCore
import PDFKit
import SwiftUI
import WebKit

struct RasterImagePreviewView: View {
    let data: Data

    @State private var zoom = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    zoom = max(zoom / 1.25, 0.1)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                Text("\(Int(zoom * 100))%")
                    .font(
                        .system(
                            size: 11,
                            weight: .semibold,
                            design: .monospaced
                        )
                    )
                    .frame(width: 48)
                Button {
                    zoom = min(zoom * 1.25, 8)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                Button("实际大小") {
                    zoom = 1
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
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(
                            width: max(image.size.width * zoom, 1),
                            height: max(image.size.height * zoom, 1)
                        )
                        .padding(24)
                }
                .background(GitMateTheme.panel)
            } else {
                previewUnavailable(
                    title: "图片无法解码",
                    message: "文件签名有效，但系统图片解码器无法打开该内容。"
                )
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
        case preview = "预览"
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
            + "style-src 'unsafe-inline'; "
            + "img-src data:; "
            + "font-src data:; "
            + "media-src 'none'; "
            + "connect-src 'none'; "
            + "frame-src 'none'; "
            + "script-src 'none';"
        let style = """
        <style>
        :root { color-scheme: light; }
        html, body { margin: 0; min-height: 100%; background: #fff; }
        body {
          box-sizing: border-box;
          padding: 24px;
          color: #132033;
          font: 14px -apple-system, BlinkMacSystemFont, sans-serif;
          overflow: auto;
        }
        img, svg { max-width: 100%; height: auto; }
        pre, code { white-space: pre-wrap; overflow-wrap: anywhere; }
        </style>
        """
        let content = treatsContentAsSVG
            ? "<main aria-label='SVG 预览'>\(text)</main>"
            : text
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(policy)">
        \(style)
        </head>
        <body>\(content)</body>
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
