import GitMateCore
import SwiftUI

struct WelcomeView: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        ZStack {
            ProductPreviewArtwork()
                .offset(x: 245, y: 4)
                .opacity(0.72)

            HStack {
                VStack(alignment: .leading, spacing: 22) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(GitMateTheme.accent)
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 64, height: 64)

                    Text("GitMate")
                        .font(.system(size: 38, weight: .bold, design: .rounded))

                    VStack(spacing: 12) {
                        Button {
                            Task { await viewModel.startGitHubLogin() }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                Text("登录 GitHub")
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                        }
                        .buttonStyle(
                            GitMateButtonStyle(role: .primary, fillsWidth: true)
                        )
                        .accessibilityIdentifier("onboarding.login")

                        Button {
                            viewModel.showEnterpriseConnection()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "building.2")
                                Text("GitHub Enterprise")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                        }
                        .buttonStyle(
                            GitMateButtonStyle(role: .secondary, fillsWidth: true)
                        )
                        .accessibilityIdentifier("onboarding.enterprise")
                    }
                    .frame(width: 300)
                }
                .padding(36)
                .background(.white.opacity(0.97))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(GitMateTheme.border, lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.10), radius: 30, y: 16)

                Spacer()
            }
            .padding(.leading, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProductPreviewArtwork: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(Color.red.opacity(0.75)).frame(width: 8, height: 8)
                Circle().fill(Color.orange.opacity(0.75)).frame(width: 8, height: 8)
                Circle().fill(Color.green.opacity(0.75)).frame(width: 8, height: 8)
                Spacer()
                Capsule().fill(GitMateTheme.border).frame(width: 110, height: 8)
            }
            .padding(16)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(0..<7, id: \.self) { index in
                        HStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(index == 1 ? GitMateTheme.accent : GitMateTheme.border)
                                .frame(width: 18, height: 18)
                            Capsule()
                                .fill(index == 1 ? GitMateTheme.accentSoft : GitMateTheme.border)
                                .frame(width: CGFloat(55 + index * 6), height: 8)
                        }
                    }
                    Spacer()
                }
                .padding(18)
                .frame(width: 180)
                .background(GitMateTheme.panel)

                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        previewMetric("18", width: 110)
                        previewMetric("7", width: 110)
                        previewMetric("2.4 GB", width: 150)
                    }
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white)
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 15) {
                                Capsule().fill(GitMateTheme.textPrimary.opacity(0.8))
                                    .frame(width: 130, height: 10)
                                ForEach(0..<5, id: \.self) { index in
                                    HStack {
                                        Circle()
                                            .fill(index == 2 ? GitMateTheme.warning : GitMateTheme.success)
                                            .frame(width: 18, height: 18)
                                        Capsule()
                                            .fill(GitMateTheme.border)
                                            .frame(width: CGFloat(180 + index * 18), height: 8)
                                    }
                                }
                            }
                            .padding(20)
                        }
                    RoundedRectangle(cornerRadius: 5)
                        .fill(GitMateTheme.accent)
                        .frame(height: 7)
                }
                .padding(16)
            }
        }
        .frame(width: 650, height: 430)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(GitMateTheme.border, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.11), radius: 30, y: 18)
        .rotation3DEffect(.degrees(-5), axis: (x: 0, y: 1, z: 0))
        .blur(radius: 0.15)
        .accessibilityHidden(true)
    }

    private func previewMetric(_ value: String, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
            Capsule()
                .fill(GitMateTheme.border)
                .frame(width: width * 0.55, height: 6)
        }
        .padding(14)
        .frame(width: width, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
