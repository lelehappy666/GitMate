import AppKit
import GitMateCore
import SwiftUI

struct SourceFilePreviewView: View {
    let document: FilePreviewDocument

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 15) {
                    Text(lineNumbers)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(GitMateTheme.textTertiary)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.disabled)
                        .fixedSize(horizontal: true, vertical: true)

                    Rectangle()
                        .fill(GitMateTheme.border)
                        .frame(width: 1)
                        .frame(minHeight: 24)

                    Text(highlightedText)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(GitMateTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)

                    Spacer(minLength: 0)
                }
                .frame(
                    minWidth: SourcePreviewLayoutPolicy
                        .minimumContentWidth(
                            viewportWidth: geometry.size.width,
                            horizontalPadding: 36
                        ),
                    minHeight: SourcePreviewLayoutPolicy
                        .minimumContentHeight(
                            viewportHeight: geometry.size.height,
                            verticalPadding: 36
                        ),
                    alignment: .topLeading
                )
                .padding(18)
            }
            .scrollIndicators(.visible)
        }
        .background(
            Color(red: 0.985, green: 0.989, blue: 0.995)
        )
        .accessibilityLabel("文件内容，只读")
    }

    private var source: String {
        document.text ?? ""
    }

    private var lineNumbers: String {
        let count = max(source.components(separatedBy: "\n").count, 1)
        return (1...count).map(String.init).joined(separator: "\n")
    }

    private var highlightedText: AttributedString {
        let storage = NSMutableAttributedString(
            string: source,
            attributes: [
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
            return AttributedString(storage)
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
        return AttributedString(storage)
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
