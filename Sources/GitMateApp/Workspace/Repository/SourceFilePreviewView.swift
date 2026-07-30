import AppKit
import GitMateCore
import SwiftUI

struct SourceFilePreviewView: View {
    let document: FilePreviewDocument

    var body: some View {
        SourceCodeTextView(attributedText: numberedText)
        .accessibilityLabel("文件内容，只读")
    }

    private var source: String {
        document.text ?? ""
    }

    private var highlightedText: NSAttributedString {
        let storage = NSMutableAttributedString(
            string: source,
            attributes: [
                .font: NSFont.monospacedSystemFont(
                    ofSize: 12.5,
                    weight: .regular
                ),
                .foregroundColor: NSColor(
                    red: 0.075,
                    green: 0.105,
                    blue: 0.16,
                    alpha: 1
                )
            ]
        )
        guard case let .source(language) = document.kind,
              let language
        else {
            return storage
        }

        apply(
            pattern: commentPattern(for: language),
            color: .systemGreen,
            to: storage
        )
        apply(
            pattern: #"(?m)("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')"#,
            color: .systemOrange,
            to: storage
        )
        if let keywords = keywordPattern(for: language) {
            apply(
                pattern: keywords,
                color: .systemBlue,
                to: storage
            )
        }
        return storage
    }

    private var numberedText: NSAttributedString {
        let highlightedText = highlightedText
        let output = NSMutableAttributedString()
        let lines = source.components(separatedBy: "\n")
        let numberWidth = String(max(lines.count, 1)).count
        var sourceOffset = 0

        for (index, line) in lines.enumerated() {
            let number = String(index + 1)
            let prefix =
                String(repeating: " ", count: max(numberWidth - number.count, 0))
                + number
                + "  │  "
            output.append(
                NSAttributedString(
                    string: prefix,
                    attributes: [
                        .font: NSFont.monospacedSystemFont(
                            ofSize: 12,
                            weight: .regular
                        ),
                        .foregroundColor: NSColor(
                            red: 0.42,
                            green: 0.47,
                            blue: 0.56,
                            alpha: 1
                        )
                    ]
                )
            )

            let lineLength = (line as NSString).length
            if lineLength > 0 {
                output.append(
                    highlightedText.attributedSubstring(
                        from: NSRange(
                            location: sourceOffset,
                            length: lineLength
                        )
                    )
                )
            }
            if index < lines.count - 1 {
                output.append(NSAttributedString(string: "\n"))
            }
            sourceOffset += lineLength + 1
        }
        return output
    }

    private func apply(
        pattern: String?,
        color: NSColor,
        to storage: NSMutableAttributedString
    ) {
        guard let pattern,
              let expression = try? NSRegularExpression(pattern: pattern)
        else {
            return
        }
        let range = NSRange(location: 0, length: storage.length)
        expression.enumerateMatches(
            in: storage.string,
            range: range
        ) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(
                .foregroundColor,
                value: color,
                range: match.range
            )
        }
    }

    private func commentPattern(
        for language: SourceLanguage
    ) -> String? {
        switch language {
        case .python, .ruby, .shell, .yaml:
            #"(?m)#.*$"#
        case .sql:
            #"(?m)--.*$|/\*[\s\S]*?\*/"#
        case .json, .markdown:
            nil
        default:
            #"(?m)//.*$|/\*[\s\S]*?\*/"#
        }
    }

    private func keywordPattern(
        for language: SourceLanguage
    ) -> String? {
        let keywords: String
        switch language {
        case .swift:
            keywords =
                "actor|associatedtype|async|await|case|class|deinit|"
                + "enum|extension|func|guard|if|import|init|let|"
                + "private|protocol|public|return|struct|throws|var"
        case .javascript, .typescript:
            keywords =
                "async|await|class|const|else|export|extends|function|"
                + "if|import|interface|let|new|return|throw|type|var"
        case .python:
            keywords =
                "and|async|await|class|def|elif|else|except|False|"
                + "for|from|if|import|in|None|not|or|return|True|try"
        case .ruby:
            keywords =
                "begin|class|def|do|else|elsif|end|if|module|require|"
                + "rescue|return|unless|yield"
        case .shell:
            keywords =
                "case|do|done|elif|else|esac|fi|for|function|if|in|"
                + "then|until|while"
        case .go:
            keywords =
                "break|case|chan|const|continue|defer|else|fallthrough|"
                + "for|func|go|goto|if|import|interface|map|package|"
                + "range|return|select|struct|switch|type|var"
        case .rust:
            keywords =
                "async|await|crate|enum|fn|impl|let|loop|match|mod|"
                + "move|mut|pub|ref|return|self|struct|trait|type|use"
        case .kotlin, .java:
            keywords =
                "abstract|class|else|enum|extends|final|fun|if|import|"
                + "interface|new|package|private|protected|public|"
                + "return|static|super|this|val|var|void"
        case .c, .cpp, .csharp:
            keywords =
                "auto|break|case|class|const|continue|default|else|"
                + "enum|for|if|namespace|private|public|return|static|"
                + "struct|switch|typedef|using|virtual|void|while"
        case .php:
            keywords =
                "class|echo|else|elseif|extends|function|if|include|"
                + "namespace|new|private|protected|public|require|return"
        case .lua:
            keywords =
                "and|break|do|else|elseif|end|false|for|function|if|"
                + "in|local|nil|not|or|repeat|return|then|true|until"
        case .sql:
            keywords =
                "ALTER|AND|AS|BY|CREATE|DELETE|DROP|FROM|GROUP|HAVING|"
                + "INSERT|INTO|JOIN|LIMIT|NOT|NULL|ON|OR|ORDER|SELECT|"
                + "SET|TABLE|UPDATE|VALUES|WHERE"
        case .yaml, .json, .xml, .css, .markdown:
            return nil
        }
        return #"(?i)\b("# + keywords + #")\b"#
    }
}

private struct SourceCodeTextView: NSViewRepresentable {
    let attributedText: NSAttributedString

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(
            red: 0.985,
            green: 0.989,
            blue: 0.995,
            alpha: 1
        )
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: .zero)
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        scrollView.documentView = textView

        context.coordinator.textView = textView
        updateTextView(
            textView,
            in: scrollView,
            context: context
        )
        return scrollView
    }

    func updateNSView(
        _ scrollView: NSScrollView,
        context: Context
    ) {
        guard let textView = context.coordinator.textView else {
            return
        }
        updateTextView(
            textView,
            in: scrollView,
            context: context
        )
    }

    private func updateTextView(
        _ textView: NSTextView,
        in scrollView: NSScrollView,
        context: Context
    ) {
        let contentChanged =
            context.coordinator.lastText != attributedText.string
        if contentChanged {
            context.coordinator.lastText = attributedText.string
            textView.textStorage?.setAttributedString(attributedText)
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        }

        if let textContainer = textView.textContainer,
           let layoutManager = textView.layoutManager {
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let viewportSize = scrollView.contentSize
            textView.setFrameSize(
                NSSize(
                    width: max(
                        viewportSize.width,
                        ceil(usedRect.width + 36)
                    ),
                    height: max(
                        viewportSize.height,
                        ceil(usedRect.height + 36)
                    )
                )
            )
        }

        if contentChanged {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    final class Coordinator {
        weak var textView: NSTextView?
        var lastText: String?
    }
}
