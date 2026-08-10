import GitMateCore
import SwiftUI

struct MilestonesCanvasView: View {
    @Bindable var viewModel: RepositoryWorkspaceViewModel
    @State private var selectedMilestone: IssueMilestone?
    @State private var editorPresentation: MilestoneEditorPresentation?
    @State private var scale: CGFloat = 0.85
    @State private var offset = CGSize(width: 60, height: 10)
    @GestureState private var dragTranslation = CGSize.zero
    @GestureState private var magnification: CGFloat = 1

    private let engine = MilestoneTimelineLayout()

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            summary
            canvas
        }
        .sheet(item: $selectedMilestone) { milestone in
            MilestoneDetailSheet(
                milestone: milestone,
                onClose: { selectedMilestone = nil },
                onEdit: {
                    selectedMilestone = nil
                    editorPresentation = MilestoneEditorPresentation(
                        milestone: milestone
                    )
                },
                onToggleState: {
                    selectedMilestone = nil
                    Task {
                        await viewModel.updateMilestone(
                            number: milestone.number,
                            input: MilestoneInput(
                                title: milestone.title,
                                description: milestone.description,
                                state: milestone.state == .open
                                    ? .closed
                                    : .open,
                                dueOn: milestone.dueOn
                            )
                        )
                    }
                },
                onDelete: {
                    selectedMilestone = nil
                    viewModel.requestDeleteMilestone(
                        number: milestone.number,
                        affectedIssues:
                            milestone.openIssues + milestone.closedIssues
                    )
                }
            )
        }
        .sheet(item: $editorPresentation) { presentation in
            MilestoneEditorSheet(
                milestone: presentation.milestone,
                onCancel: {
                    editorPresentation = nil
                },
                onSave: saveMilestone
            )
        }
    }

    @MainActor
    private func saveMilestone(_ input: MilestoneInput) async -> String? {
        guard let editorPresentation else {
            return "里程碑编辑窗口已关闭，请重新打开后再试。"
        }
        let succeeded: Bool
        if let milestone = editorPresentation.milestone {
            succeeded = await viewModel.updateMilestone(
                number: milestone.number,
                input: input
            )
        } else {
            succeeded = await viewModel.createMilestone(input)
        }
        guard succeeded else {
            return viewModel.state.errorMessage
                ?? "保存里程碑失败，请检查网络后重试。"
        }
        self.editorPresentation = nil
        return nil
    }

    private var layout: MilestoneTimelineLayoutResult {
        engine.makeLayout(milestones: viewModel.state.milestones)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(GitMateTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("版本时间线画布")
                        .font(.system(size: 12, weight: .bold))
                    Text("拖动画布 · 双指缩放 · 点击节点查看详情")
                        .font(.system(size: 9))
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
            }

            Spacer()

            Button {
                editorPresentation = MilestoneEditorPresentation(
                    milestone: nil
                )
            } label: {
                Label("新建里程碑", systemImage: "plus")
            }
            .buttonStyle(GitMateButtonStyle(role: .primary))
            .accessibilityIdentifier("workspace.milestones.create")
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .workspacePanel()
    }

    private var summary: some View {
        HStack(spacing: 0) {
            summaryItem(
                value: viewModel.state.milestones.count,
                title: "全部里程碑",
                color: GitMateTheme.textPrimary
            )
            summaryItem(
                value: viewModel.state.milestones.filter {
                    $0.state == .open
                }.count,
                title: "进行中",
                color: GitMateTheme.success
            )
            summaryItem(
                value: viewModel.state.milestones.reduce(0) {
                    $0 + $1.openIssues
                },
                title: "未完成议题",
                color: GitMateTheme.warning
            )
            summaryItem(
                value: viewModel.state.milestones.filter {
                    $0.dueOn == nil
                }.count,
                title: "尚未排期",
                color: GitMateTheme.accent
            )
        }
        .frame(height: 62)
        .workspacePanel()
    }

    private func summaryItem(
        value: Int,
        title: String,
        color: Color
    ) -> some View {
        HStack(spacing: 10) {
            Text("\(value)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(GitMateTheme.border)
                .frame(width: 1, height: 32)
        }
    }

    private var canvas: some View {
        GeometryReader { proxy in
            ZStack {
                MilestoneGrid(
                    offset: effectiveOffset,
                    scale: effectiveScale
                )

                connections

                ForEach(layout.nodes) { node in
                    if let milestone = viewModel.state.milestones.first(
                        where: { $0.id == node.milestoneID }
                    ) {
                        MilestoneNodeView(milestone: milestone) {
                            selectedMilestone = milestone
                        }
                        .frame(width: 220)
                        .position(screenPoint(node.position))
                    }
                }

                controls(size: proxy.size)
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
            .onAppear {
                fit(in: proxy.size)
            }
            .onChange(of: viewModel.state.milestones.map(\.id)) {
                _, _ in
                fit(in: proxy.size)
            }
        }
        .workspacePanel()
    }

    private var connections: some View {
        Canvas { context, _ in
            let nodes = Dictionary(
                uniqueKeysWithValues: layout.nodes.map {
                    ($0.milestoneID, screenPoint($0.position))
                }
            )
            for connection in layout.connections {
                guard
                    let start = nodes[connection.sourceMilestoneID],
                    let end = nodes[connection.targetMilestoneID]
                else {
                    continue
                }
                var path = Path()
                path.move(to: start)
                let controlDistance = (end.x - start.x) * 0.45
                path.addCurve(
                    to: end,
                    control1: CGPoint(
                        x: start.x + controlDistance,
                        y: start.y
                    ),
                    control2: CGPoint(
                        x: end.x - controlDistance,
                        y: end.y
                    )
                )
                context.stroke(
                    path,
                    with: .color(GitMateTheme.accent.opacity(0.55)),
                    style: StrokeStyle(
                        lineWidth: 2.5,
                        lineCap: .round,
                        dash: [8, 5]
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func controls(size: CGSize) -> some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 0) {
                    canvasButton("minus") {
                        scale = max(0.35, scale - 0.1)
                    }
                    Divider().frame(height: 20)
                    Text("\(Int(scale * 100))%")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 54)
                    Divider().frame(height: 20)
                    canvasButton("plus") {
                        scale = min(1.8, scale + 0.1)
                    }
                    Divider().frame(height: 20)
                    canvasButton("scope") {
                        fit(in: size)
                    }
                }
                .frame(height: 34)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(GitMateTheme.border)
                }
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
            }
            Spacer()
            HStack {
                Label(
                    "无限画布 · 共 \(layout.nodes.count) 个节点",
                    systemImage: "move.3d"
                )
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(.white.opacity(0.92))
                .clipShape(Capsule())
                Spacer()
            }
        }
        .padding(12)
        .allowsHitTesting(true)
    }

    private func canvasButton(
        _ icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 34, height: 32)
        }
        .buttonStyle(.plain)
    }

    private var effectiveOffset: CGSize {
        CGSize(
            width: offset.width + dragTranslation.width,
            height: offset.height + dragTranslation.height
        )
    }

    private var effectiveScale: CGFloat {
        min(1.8, max(0.35, scale * magnification))
    }

    private func screenPoint(_ point: MilestoneCanvasPoint) -> CGPoint {
        CGPoint(
            x: CGFloat(point.x) * effectiveScale + effectiveOffset.width,
            y: CGFloat(point.y) * effectiveScale + effectiveOffset.height
        )
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($magnification) { value, state, _ in
                state = value
            }
            .onEnded { value in
                scale = min(1.8, max(0.35, scale * value))
            }
    }

    private func fit(in size: CGSize) {
        guard !layout.nodes.isEmpty else {
            scale = 1
            offset = CGSize(width: size.width / 2, height: size.height / 2)
            return
        }
        let bounds = layout.bounds
        let fitX = max(0.35, (size.width - 80) / CGFloat(bounds.width))
        let fitY = max(0.35, (size.height - 80) / CGFloat(bounds.height))
        scale = min(1, max(0.35, min(fitX, fitY)))
        offset = CGSize(
            width: (size.width - CGFloat(bounds.width) * scale) / 2
                - CGFloat(bounds.x) * scale,
            height: (size.height - CGFloat(bounds.height) * scale) / 2
                - CGFloat(bounds.y) * scale
        )
    }
}

private struct MilestoneGrid: View {
    let offset: CGSize
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            let spacing = max(22, 40 * scale)
            let startX = offset.width.truncatingRemainder(dividingBy: spacing)
            let startY = offset.height.truncatingRemainder(dividingBy: spacing)
            var path = Path()

            stride(
                from: startX,
                through: size.width,
                by: spacing
            ).forEach {
                path.move(to: CGPoint(x: $0, y: 0))
                path.addLine(to: CGPoint(x: $0, y: size.height))
            }
            stride(
                from: startY,
                through: size.height,
                by: spacing
            ).forEach {
                path.move(to: CGPoint(x: 0, y: $0))
                path.addLine(to: CGPoint(x: size.width, y: $0))
            }
            context.stroke(
                path,
                with: .color(GitMateTheme.border.opacity(0.48)),
                lineWidth: 0.7
            )
        }
        .background(Color.white)
        .allowsHitTesting(false)
    }
}

private struct MilestoneNodeView: View {
    let milestone: IssueMilestone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(nodeColor.opacity(0.13))
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(nodeColor)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(milestone.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(GitMateTheme.textPrimary)
                            .lineLimit(1)
                        Text(
                            milestone.dueOn.map {
                                "截止 \($0.formatted(date: .abbreviated, time: .omitted))"
                            } ?? "尚未排期"
                        )
                        .font(.system(size: 9))
                        .foregroundStyle(GitMateTheme.textSecondary)
                    }
                    Spacer()
                }

                ProgressView(value: milestone.progress)
                    .tint(nodeColor)

                HStack {
                    Text("\(Int(milestone.progress * 100))%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(nodeColor)
                    Spacer()
                    Text("\(milestone.closedIssues) / \(milestone.openIssues + milestone.closedIssues)")
                        .font(.system(size: 9))
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
            }
            .padding(13)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(nodeColor.opacity(0.45), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.09), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(milestone.title)，完成 \(Int(milestone.progress * 100))%"
        )
        .accessibilityHint("打开里程碑详情")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            action()
        }
    }

    private var nodeColor: Color {
        milestone.state == .closed
            ? Color.purple
            : (milestone.progress >= 0.7
                ? GitMateTheme.success
                : GitMateTheme.accent)
    }
}

private struct MilestoneDetailSheet: View {
    let milestone: IssueMilestone
    let onClose: () -> Void
    let onEdit: () -> Void
    let onToggleState: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(GitMateTheme.accent)
                    Image(systemName: "diamond.fill")
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 5) {
                    Text(milestone.title)
                        .font(.system(size: 19, weight: .bold))
                    HStack(spacing: 8) {
                        WorkspaceStatusChip(
                            text: milestone.state == .open ? "进行中" : "已关闭",
                            color: milestone.state == .open
                                ? GitMateTheme.success
                                : .purple
                        )
                        Text("#\(milestone.number)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(GitMateTheme.textSecondary)
                    }
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    metric(
                        "\(milestone.openIssues)",
                        title: "进行中议题",
                        color: GitMateTheme.warning
                    )
                    metric(
                        "\(milestone.closedIssues)",
                        title: "已完成议题",
                        color: GitMateTheme.success
                    )
                    metric(
                        "\(Int(milestone.progress * 100))%",
                        title: "整体进度",
                        color: GitMateTheme.accent
                    )
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("完成进度")
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                        Text("\(Int(milestone.progress * 100))%")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(GitMateTheme.success)
                    }
                    ProgressView(value: milestone.progress)
                        .tint(GitMateTheme.success)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("里程碑说明", systemImage: "text.alignleft")
                        .font(.system(size: 12, weight: .bold))
                    Text(milestone.description ?? "没有说明。")
                        .font(.system(size: 11))
                        .foregroundStyle(GitMateTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("截止时间", systemImage: "calendar")
                        .font(.system(size: 12, weight: .bold))
                    Text(
                        milestone.dueOn?.formatted(
                            date: .long,
                            time: .omitted
                        ) ?? "尚未排期"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(GitMateTheme.textSecondary)
                }
            }
            .padding(20)

            Divider()

            HStack(spacing: 10) {
                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(
                    milestone.state == .open ? "关闭里程碑" : "重新打开",
                    action: onToggleState
                )
                .buttonStyle(.bordered)
                Button("编辑", action: onEdit)
                    .buttonStyle(GitMateButtonStyle(role: .primary))
            }
            .padding(16)
        }
        .frame(width: 560)
        .background(.white)
    }

    private func metric(
        _ value: String,
        title: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitMateTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

private struct MilestoneEditorPresentation: Identifiable {
    let id = UUID()
    let milestone: IssueMilestone?
}

private struct MilestoneEditorSheet: View {
    let milestone: IssueMilestone?
    let onCancel: () -> Void
    let onSave: @MainActor (MilestoneInput) async -> String?
    @State private var title: String
    @State private var description: String
    @State private var state: IssueState
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        milestone: IssueMilestone?,
        onCancel: @escaping () -> Void,
        onSave: @escaping @MainActor (MilestoneInput) async -> String?
    ) {
        self.milestone = milestone
        self.onCancel = onCancel
        self.onSave = onSave
        _title = State(initialValue: milestone?.title ?? "")
        _description = State(initialValue: milestone?.description ?? "")
        _state = State(initialValue: milestone?.state ?? .open)
        _hasDueDate = State(initialValue: milestone?.dueOn != nil)
        _dueDate = State(
            initialValue: milestone?.dueOn
                ?? Calendar.current.date(
                    byAdding: .month,
                    value: 1,
                    to: .now
                )
                ?? .now
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(milestone == nil ? "新建里程碑" : "编辑里程碑")
                .font(.system(size: 19, weight: .bold))
            TextField("里程碑名称", text: $title)
                .textFieldStyle(.roundedBorder)
                .disabled(isSaving)
            TextEditor(text: $description)
                .font(.system(size: 12))
                .padding(8)
                .frame(height: 130)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(GitMateTheme.border)
                }
                .disabled(isSaving)
            HStack {
                Text("状态")
                    .font(.system(size: 11, weight: .semibold))
                Picker("", selection: $state) {
                    Text("进行中").tag(IssueState.open)
                    Text("已关闭").tag(IssueState.closed)
                }
                .labelsHidden()
                .disabled(isSaving)
                Spacer()
            }
            Toggle("设置截止日期", isOn: $hasDueDate)
                .disabled(isSaving)
            if hasDueDate {
                DatePicker(
                    "截止日期",
                    selection: $dueDate,
                    displayedComponents: .date
                )
                .disabled(isSaving)
            }
            if let errorMessage {
                Label(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(GitMateTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(
                    "workspace.milestones.editor.error"
                )
            }
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
                Button {
                    Task {
                        await submit()
                    }
                } label: {
                    if isSaving {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在保存…")
                        }
                    } else {
                        Text("保存")
                    }
                }
                .buttonStyle(GitMateButtonStyle(role: .primary))
                .disabled(
                    title.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                        || isSaving
                )
                .accessibilityIdentifier(
                    "workspace.milestones.editor.save"
                )
            }
        }
        .padding(22)
        .frame(width: 520)
        .interactiveDismissDisabled(isSaving)
    }

    @MainActor
    private func submit() async {
        guard !isSaving else {
            return
        }
        isSaving = true
        errorMessage = nil
        let trimmedTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let trimmedDescription = description.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let error = await onSave(
            MilestoneInput(
                title: trimmedTitle,
                description: trimmedDescription.isEmpty
                    ? nil
                    : trimmedDescription,
                state: state,
                dueOn: hasDueDate ? dueDate : nil
            )
        )
        if let error {
            errorMessage = error
        }
        isSaving = false
    }
}
