import Foundation

public enum GitOutputRedactor {
    private static let replacements: [(NSRegularExpression, String)] = [
        (
            expression(#"(?i)authorization\s*:\s*(?:basic|bearer)\s+\S+"#),
            "Authorization: [已脱敏]"
        ),
        (
            expression(#"(?i)(https?://)[^/@\s]+@"#),
            "$1***@"
        ),
        (
            expression(#"(?i)\bgithub_pat_[A-Za-z0-9_]{10,}\b"#),
            "[已脱敏]"
        ),
        (
            expression(#"(?i)\bgh[pousr]_[A-Za-z0-9_]{10,}\b"#),
            "[已脱敏]"
        )
    ]

    public static func redact(_ value: String) -> String {
        replacements.reduce(value) { partial, replacement in
            let range = NSRange(
                partial.startIndex..<partial.endIndex,
                in: partial
            )
            return replacement.0.stringByReplacingMatches(
                in: partial,
                range: range,
                withTemplate: replacement.1
            )
        }
    }

    private static func expression(
        _ pattern: String
    ) -> NSRegularExpression {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            preconditionFailure("Git 日志脱敏表达式无效")
        }
        return expression
    }
}
