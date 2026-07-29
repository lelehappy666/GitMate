import Foundation

public struct IssueLabel: Identifiable, Equatable, Codable, Sendable {
    public let id: Int64
    public var name: String
    public var color: String
    public var description: String?
    public var isDefault: Bool
    public var openIssueCount: Int
    public var closedIssueCount: Int

    public init(
        id: Int64,
        name: String,
        color: String,
        description: String? = nil,
        isDefault: Bool = false,
        openIssueCount: Int = 0,
        closedIssueCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.description = description
        self.isDefault = isDefault
        self.openIssueCount = max(0, openIssueCount)
        self.closedIssueCount = max(0, closedIssueCount)
    }

    public var normalizedColorHex: String {
        let candidate = color
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .uppercased()

        guard candidate.allSatisfy({ $0.isHexDigit }) else {
            return "D0D7DE"
        }

        if candidate.count == 3 {
            return candidate.map { "\($0)\($0)" }.joined()
        }
        if candidate.count == 6 {
            return candidate
        }
        return "D0D7DE"
    }

    public var issueCount: Int {
        openIssueCount + closedIssueCount
    }

    public var usesDarkForeground: Bool {
        let hex = normalizedColorHex
        guard
            let red = Int(hex.prefix(2), radix: 16),
            let green = Int(hex.dropFirst(2).prefix(2), radix: 16),
            let blue = Int(hex.suffix(2), radix: 16)
        else {
            return true
        }
        let luminance = (0.299 * Double(red))
            + (0.587 * Double(green))
            + (0.114 * Double(blue))
        return luminance > 150
    }
}
