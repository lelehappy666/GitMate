import AppKit
import GitMateCore
import SwiftUI

struct CommitDetailSheet: View {
    let detail: GitCommitDetail
    let diff: GitDiff?
    let isDiffTruncated: Bool
    let avatarURL: URL?
    let dismiss: () -> Void

    @State private var showsPatch = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    messageSection
                    metadataSection
                    statisticsSection
                    changedFilesSection
                }
                .padding(24)
            }

            Divider()
            actionBar
        }
        .frame(width: 700, height: 620)
        .background(.white)
        .accessibilityIdentifier("workspace.commitGraph.detail")
        .sheet(isPresented: $showsPatch) {
            patchSheet
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            GitMateAvatar(url: avatarURL, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(detail.commit.authorName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                Text(
                    detail.commit.authoredAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.system(size: 11.5))
                .foregroundStyle(GitMateTheme.textSecondary)
            }

            Spacer()

            signatureBadge

            Button("完成", action: dismiss)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24)
        .frame(height: 78)
    }

    private var signatureBadge: some View {
        Label(signatureText, systemImage: signatureSymbol)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(signatureColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(signatureColor.opacity(0.1))
            .clipShape(Capsule())
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.commit.subject)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(GitMateTheme.textPrimary)
                .textSelection(.enabled)

            if detail.message != detail.commit.subject {
                Text(detail.message)
                    .font(.system(size: 13))
                    .foregroundStyle(GitMateTheme.textSecondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var metadataSection: some View {
        HStack(spacing: 12) {
            metadataCard(
                title: "提交",
                value: detail.commit.fullHash
            )
            metadataCard(
                title: "父提交",
                value: detail.commit.parentHashes.isEmpty
                    ? "无"
                    : detail.commit.parentHashes.joined(separator: "\n")
            )
        }
    }

    private func metadataCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(GitMateTheme.textTertiary)
            Text(value)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(GitMateTheme.textPrimary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(GitMateTheme.panel)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
        )
    }

    private var statisticsSection: some View {
        HStack(spacing: 10) {
            statistic(
                "\(diff?.files.count ?? 0)",
                label: "文件变更",
                color: GitMateTheme.accent
            )
            statistic(
                "+\(diff?.additions ?? 0)",
                label: "新增行",
                color: GitMateTheme.success
            )
            statistic(
                "−\(diff?.deletions ?? 0)",
                label: "删除行",
                color: GitMateTheme.danger
            )
        }
    }

    private func statistic(
        _ value: String,
        label: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitMateTheme.panel)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
        )
    }

    private var changedFilesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("变更文件")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                Spacer()
                if isDiffTruncated {
                    Label("差异过大，已安全截断", systemImage: "scissors")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(GitMateTheme.warning)
                }
            }

            if let files = diff?.files, !files.isEmpty {
                VStack(spacing: 0) {
                    ForEach(files, id: \.path) { file in
                        HStack(spacing: 10) {
                            Image(systemName: file.isBinary
                                ? "doc.badge.gearshape"
                                : "doc.text")
                                .foregroundStyle(GitMateTheme.accent)
                            Text(file.path)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(GitMateTheme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text("+\(file.additions ?? 0)")
                                .foregroundStyle(GitMateTheme.success)
                            Text("−\(file.deletions ?? 0)")
                                .foregroundStyle(GitMateTheme.danger)
                        }
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 42)

                        if file.path != files.last?.path {
                            Divider()
                        }
                    }
                }
                .background(.white)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                    .stroke(GitMateTheme.border, lineWidth: 1)
                }
            } else {
                Text("此提交没有可显示的文件统计")
                    .font(.system(size: 12.5))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    detail.commit.fullHash,
                    forType: .string
                )
            } label: {
                Label("复制完整哈希", systemImage: "doc.on.doc")
            }

            Spacer()

            Button {
                showsPatch = true
            } label: {
                Label("查看完整差异", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(diff?.patch.isEmpty != false)
        }
        .padding(.horizontal, 24)
        .frame(height: 68)
    }

    private var patchSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("纯文本差异")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("完成") {
                    showsPatch = false
                }
            }
            .padding(16)
            Divider()
            ScrollView([.horizontal, .vertical]) {
                Text(diff?.patch ?? "")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(GitMateTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
            }
        }
        .frame(width: 820, height: 620)
        .background(.white)
    }

    private var signatureText: String {
        switch detail.signatureStatus {
        case .verified:
            detail.signer.map { "签名已验证 · \($0)" } ?? "签名已验证"
        case .unverified:
            "签名未验证"
        case .unknown:
            "签名未知"
        }
    }

    private var signatureSymbol: String {
        switch detail.signatureStatus {
        case .verified:
            "checkmark.shield.fill"
        case .unverified:
            "xmark.shield.fill"
        case .unknown:
            "questionmark.diamond.fill"
        }
    }

    private var signatureColor: Color {
        switch detail.signatureStatus {
        case .verified:
            GitMateTheme.success
        case .unverified:
            GitMateTheme.danger
        case .unknown:
            GitMateTheme.textSecondary
        }
    }
}
