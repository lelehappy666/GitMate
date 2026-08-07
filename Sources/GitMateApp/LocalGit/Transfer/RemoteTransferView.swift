import GitMateCore
import SwiftUI

struct RemoteTransferView: View {
    @Bindable var viewModel: RemoteTransferViewModel
    var onShowConflicts: () -> Void = {}
    @State private var showPlanConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                controls
                    .frame(minWidth: 280, idealWidth: 340)
                activity
                    .frame(minWidth: 440)
            }
        }
        .background(.white)
        .accessibilityIdentifier("localGit.transfer")
        .onChange(of: viewModel.shouldShowConflicts) {
            guard viewModel.shouldShowConflicts else {
                return
            }
            onShowConflicts()
            viewModel.consumeConflictRoute()
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $showPlanConfirmation
        ) {
            Button(
                "确认执行",
                role: viewModel.plan?.pushMode == .forceWithLease
                    ? .destructive
                    : nil
            ) {
                viewModel.executePlan()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("获取、拉取与推送")
                    .font(.system(size: 20, weight: .bold))
                Text("实时显示 Git 传输阶段和脱敏日志")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            Spacer()
            if viewModel.isRunning {
                Button("取消") { viewModel.cancel() }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 72)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("远程", text: $viewModel.remote)
            field("分支", text: $viewModel.branch)

            Button("Fetch") {
                viewModel.fetch()
            }
            .buttonStyle(.borderedProminent)
            .tint(GitMateTheme.accent)
            .frame(maxWidth: .infinity)

            Divider()

            HStack {
                Button("预检 Pull") {
                    Task {
                        await viewModel.planPull()
                        showPlanConfirmation = viewModel.plan != nil
                    }
                }
                Picker("Push 模式", selection: $viewModel.pushMode) {
                    Text("普通").tag(PushMode.normal)
                    Text("Force with lease").tag(PushMode.forceWithLease)
                }
                .frame(maxWidth: 180)
                Button("预检 Push") {
                    Task {
                        await viewModel.planPush()
                        showPlanConfirmation = viewModel.plan != nil
                    }
                }
            }

            if let plan = viewModel.plan {
                planCard(plan)
            }

            if let error = viewModel.error {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GitMateTheme.danger)
            }

            Spacer()
        }
        .padding(20)
        .background(GitMateTheme.panel.opacity(0.45))
    }

    private var activity: some View {
        VStack(spacing: 0) {
            HStack {
                Text("实时活动")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                if let last = viewModel.events.last {
                    Text(phaseText(last.phase))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(GitMateTheme.accent)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            Divider()

            if viewModel.events.isEmpty {
                ContentUnavailableView(
                    "等待 Git 传输",
                    systemImage: "arrow.up.arrow.down.circle"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(
                            Array(viewModel.events.enumerated()),
                            id: \.offset
                        ) { _, event in
                            eventRow(event)
                        }
                    }
                }
            }
        }
        .background(.white)
    }

    private func field(
        _ title: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func planCard(_ plan: GitTransferPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("操作预检")
                .font(.system(size: 12, weight: .bold))
            HStack {
                metric("\(plan.ahead ?? 0)", "领先")
                metric("\(plan.behind ?? 0)", "落后")
                metric(
                    plan.estimatedBytes.map {
                        ByteCountFormatter.string(
                            fromByteCount: $0,
                            countStyle: .file
                        )
                    } ?? "未知",
                    "数据量"
                )
            }
            if plan.pushMode == .forceWithLease {
                Label(
                    "将使用精确 force-with-lease",
                    systemImage: "lock.shield"
                )
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(GitMateTheme.warning)
            }
        }
        .padding(13)
        .background(.white)
        .clipShape(
            RoundedRectangle(cornerRadius: GitMateTheme.compactCornerRadius)
        )
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventRow(_ event: GitTransferEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(GitMateTheme.accent)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(phaseText(event.phase))
                    .font(.system(size: 11, weight: .bold))
                if let message = event.message {
                    Text(message)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(GitMateTheme.textSecondary)
                        .textSelection(.enabled)
                }
                HStack {
                    if let current = event.currentObjects,
                       let total = event.totalObjects {
                        Text("\(current)/\(total) 个对象")
                    }
                    if let speed = event.bytesPerSecond {
                        Text(
                            "\(ByteCountFormatter.string(fromByteCount: speed, countStyle: .file))/秒"
                        )
                    }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
            }
            Spacer()
        }
        .padding(13)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var confirmationTitle: String {
        switch viewModel.plan?.operation {
        case .pull:
            return "确认按当前 Git 策略拉取并整合？"
        case .push:
            return viewModel.plan?.pushMode == .forceWithLease
                ? "确认使用精确 lease 强制推送？"
                : "确认推送这些提交？"
        case .fetch, nil:
            return "确认执行？"
        }
    }

    private func phaseText(_ phase: GitTransferPhase) -> String {
        switch phase {
        case .connecting:
            return "正在连接"
        case .negotiating:
            return "协商对象"
        case .transferring:
            return "传输对象"
        case .integrating:
            return "本地整合"
        case .conflicted:
            return "需要解决冲突"
        case .completed:
            return "已完成"
        }
    }
}
