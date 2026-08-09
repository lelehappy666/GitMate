import GitMateCore
import SwiftUI

struct IssueStateChip: View {
    let state: IssueState

    var body: some View {
        Label(
            state == .open ? "进行中" : "已关闭",
            systemImage: state == .open
                ? "circle.circle"
                : "checkmark.circle.fill"
        )
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(
            state == .open ? GitMateTheme.success : Color.purple
        )
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            (state == .open ? GitMateTheme.success : Color.purple)
                .opacity(0.10)
        )
        .clipShape(Capsule())
    }
}

struct IssueLabelChip: View {
    let label: IssueLabel

    var body: some View {
        Text(label.name)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(label.usesDarkForeground ? .black : .white)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Color(issueHex: label.normalizedColorHex))
            .clipShape(Capsule())
    }
}

struct IssueMarkdownView: View {
    let markdown: String

    var body: some View {
        if let attributed = try? AttributedString(markdown: markdown) {
            Text(attributed)
                .font(.system(size: 12))
                .foregroundStyle(GitMateTheme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(markdown)
                .font(.system(size: 12))
                .foregroundStyle(GitMateTheme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct IssueAvatarView: View {
    let user: IssueUser
    var size: CGFloat = 30

    var body: some View {
        GitMateAvatar(url: user.avatarURL, size: size)
            .help(user.name ?? "@\(user.login)")
    }
}

extension Color {
    init(issueHex value: String) {
        let value = value.trimmingCharacters(
            in: CharacterSet(charactersIn: "#")
        )
        let parsed = UInt64(value, radix: 16) ?? 0xD0D7DE
        self.init(
            red: Double((parsed >> 16) & 0xFF) / 255,
            green: Double((parsed >> 8) & 0xFF) / 255,
            blue: Double(parsed & 0xFF) / 255
        )
    }
}

func workspaceDate(_ date: Date) -> String {
    guard date != .distantPast else {
        return "未知时间"
    }
    return date.formatted(date: .abbreviated, time: .shortened)
}
