import SwiftUI

enum GitMateTheme {
    static let background = Color.white
    static let canvas = Color(red: 0.965, green: 0.975, blue: 0.988)
    static let panel = Color(red: 0.975, green: 0.982, blue: 0.992)
    static let textPrimary = Color(red: 0.075, green: 0.105, blue: 0.16)
    static let textSecondary = Color(red: 0.25, green: 0.31, blue: 0.39)
    static let textTertiary = Color(red: 0.42, green: 0.47, blue: 0.54)
    static let accent = Color(red: 0.12, green: 0.45, blue: 0.82)
    static let accentSoft = Color(red: 0.90, green: 0.95, blue: 1.0)
    static let border = Color(red: 0.84, green: 0.87, blue: 0.91)
    static let success = Color(red: 0.20, green: 0.58, blue: 0.34)
    static let warning = Color(red: 0.88, green: 0.56, blue: 0.12)
    static let danger = Color(red: 0.80, green: 0.20, blue: 0.25)

    static let cornerRadius: CGFloat = 16
    static let compactCornerRadius: CGFloat = 11
    static let contentMaxWidth: CGFloat = 1_080
}

struct GitMateAvatar: View {
    let url: URL?
    var size: CGFloat = 48

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(GitMateTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(GitMateTheme.border, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
