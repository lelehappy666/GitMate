import SwiftUI

struct GitMateCard: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.white)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: GitMateTheme.cornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: GitMateTheme.cornerRadius,
                    style: .continuous
                )
                .stroke(GitMateTheme.border, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.045), radius: 18, y: 8)
    }
}

extension View {
    func gitMateCard(padding: CGFloat = 20) -> some View {
        modifier(GitMateCard(padding: padding))
    }
}
