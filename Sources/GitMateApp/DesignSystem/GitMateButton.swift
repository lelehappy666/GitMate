import SwiftUI

enum GitMateButtonRole {
    case primary
    case secondary
    case quiet
    case destructive
}

struct GitMateButtonStyle: ButtonStyle {
    let role: GitMateButtonRole
    var fillsWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(background.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                if role == .secondary || role == .quiet || role == .destructive {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(border, lineWidth: 1)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch role {
        case .primary:
            .white
        case .secondary, .quiet:
            GitMateTheme.textPrimary
        case .destructive:
            GitMateTheme.danger
        }
    }

    private var background: Color {
        switch role {
        case .primary:
            GitMateTheme.accent
        case .secondary:
            .white
        case .quiet:
            GitMateTheme.panel
        case .destructive:
            Color(red: 1, green: 0.96, blue: 0.965)
        }
    }

    private var border: Color {
        role == .destructive
            ? GitMateTheme.danger.opacity(0.35)
            : GitMateTheme.border
    }
}
