import AppKit
import GitMateCore
import SwiftUI

enum RepositoryWallScope {
    case local
    case cloud
}

struct RepositoryWallView: View {
    @Bindable var viewModel: RepositoryWallViewModel
    let scope: RepositoryWallScope
    let onRoute: ((WorkspaceRoute) -> Void)?
    let onRefresh: (() -> Void)?
    let onLoadNextPage: (() -> Void)?
    let onDownload:
        ((Repository, RepositorySyncMode) -> Void)?

    @State private var visibleRepositoryIDs = Set<Int64>()
    @State private var coverTask: Task<Void, Never>?
    @State private var lastColumnCount = 1

    init(
        viewModel: RepositoryWallViewModel,
        scope: RepositoryWallScope = .local,
        onRoute: ((WorkspaceRoute) -> Void)? = nil,
        onRefresh: (() -> Void)? = nil,
        onLoadNextPage: (() -> Void)? = nil,
        onDownload:
            ((Repository, RepositorySyncMode) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.scope = scope
        self.onRoute = onRoute
        self.onRefresh = onRefresh
        self.onLoadNextPage = onLoadNextPage
        self.onDownload = onDownload
    }

    var body: some View {
        let visibleItems = viewModel.visibleItems
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 16)

            toolbar(visibleItemCount: visibleItems.count)
                .padding(.horizontal, 28)
                .padding(.bottom, 16)

            Divider()

            repositoryContent(visibleItems: visibleItems)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(GitMateTheme.canvas)
        .onDisappear {
            coverTask?.cancel()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(scope == .local ? "本地仓库" : "云端仓库")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                Text(headerDescription)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }

            Spacer(minLength: 16)

            if let onRefresh {
                Button {
                    onRefresh()
                    scheduleCoverLoading(
                        columnCount: lastColumnCount
                    )
                } label: {
                    Label("刷新云端仓库", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(GitMateTheme.accent)
                .accessibilityIdentifier(
                    "workspace.repositories.cloud.refresh"
                )
            } else {
                HStack(spacing: 11) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(GitMateTheme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(readmeCoverCount) / \(viewModel.items.count)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(GitMateTheme.textPrimary)
                        Text("已缓存封面")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(GitMateTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 15)
                .frame(height: 52)
                .background(.white)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: GitMateTheme.compactCornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: GitMateTheme.compactCornerRadius,
                        style: .continuous
                    )
                    .stroke(GitMateTheme.border, lineWidth: 1)
                }
            }
        }
        .frame(maxWidth: GitMateTheme.contentMaxWidth, alignment: .leading)
    }

    private func toolbar(visibleItemCount: Int) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(GitMateTheme.textTertiary)
                    TextField(
                        "搜索仓库或所有者",
                        text: $viewModel.searchText
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GitMateTheme.textPrimary)
                }
                .padding(.horizontal, 13)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(.white)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: GitMateTheme.compactCornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: GitMateTheme.compactCornerRadius,
                        style: .continuous
                    )
                    .stroke(GitMateTheme.border, lineWidth: 1)
                }
                .accessibilityIdentifier("workspace.repositories.search")

                filterPicker(
                    title: "排序",
                    selection: $viewModel.sort,
                    options: RepositoryWallSort.allCases,
                    label: sortTitle,
                    defaultValue: .recentlyUpdated
                )
                .frame(width: 142)
            }

            HStack(spacing: 10) {
                filterPicker(
                    title: "可见性",
                    selection: $viewModel.visibility,
                    options: RepositoryVisibilityFilter.allCases,
                    label: visibilityFilterTitle,
                    defaultValue: .all
                )

                languagePicker

                if scope == .local {
                    filterPicker(
                        title: "同步状态",
                        selection: $viewModel.syncState,
                        options: RepositorySyncStateFilter.allCases,
                        label: syncFilterTitle,
                        defaultValue: .all
                    )
                }

                Spacer(minLength: 0)

                Text("显示 \(visibleItemCount) 个仓库")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            .accessibilityIdentifier("workspace.repositories.filter")
        }
        .frame(maxWidth: GitMateTheme.contentMaxWidth, alignment: .leading)
    }

    private func filterPicker<Value: Hashable & Equatable>(
        title: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String,
        defaultValue: Value
    ) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    if selection.wrappedValue == option {
                        Label(label(option), systemImage: "checkmark")
                    } else {
                        Text(label(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(label(selection.wrappedValue))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(
                selection.wrappedValue == defaultValue
                    ? GitMateTheme.textSecondary
                    : GitMateTheme.accent
            )
            .padding(.horizontal, 12)
            .frame(minWidth: 118, minHeight: 34)
            .background(
                selection.wrappedValue == defaultValue
                    ? Color.white
                    : GitMateTheme.accent.opacity(0.11)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: GitMateTheme.compactCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: GitMateTheme.compactCornerRadius,
                    style: .continuous
                )
                .stroke(
                    selection.wrappedValue == defaultValue
                        ? GitMateTheme.border
                        : GitMateTheme.accent.opacity(0.38),
                    lineWidth: 1
                )
            }
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(title)
    }

    private var languagePicker: some View {
        Menu {
            Button {
                viewModel.language = nil
            } label: {
                if viewModel.language == nil {
                    Label("全部语言", systemImage: "checkmark")
                } else {
                    Text("全部语言")
                }
            }
            ForEach(viewModel.availableLanguages, id: \.self) { language in
                Button {
                    viewModel.language = language
                } label: {
                    if viewModel.language == language {
                        Label(language, systemImage: "checkmark")
                    } else {
                        Text(language)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(viewModel.language ?? "全部语言")
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(
                viewModel.language == nil
                    ? GitMateTheme.textSecondary
                    : GitMateTheme.accent
            )
            .padding(.horizontal, 12)
            .frame(minWidth: 118, minHeight: 34)
            .background(
                viewModel.language == nil
                    ? Color.white
                    : GitMateTheme.accent.opacity(0.11)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: GitMateTheme.compactCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: GitMateTheme.compactCornerRadius,
                    style: .continuous
                )
                .stroke(
                    viewModel.language == nil
                        ? GitMateTheme.border
                        : GitMateTheme.accent.opacity(0.38),
                    lineWidth: 1
                )
            }
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("语言")
    }

    @ViewBuilder
    private func repositoryContent(
        visibleItems: [RepositoryPosterItem]
    ) -> some View {
        if viewModel.items.isEmpty {
            emptyState(
                symbol: "square.stack.3d.up.slash",
                title: "还没有仓库",
                message: "完成同步或添加本地仓库后，仓库会出现在这里。"
            )
        } else if visibleItems.isEmpty {
            emptyState(
                symbol: "line.3.horizontal.decrease.circle",
                title: "没有符合条件的仓库",
                message: "尝试清除搜索内容或调整筛选条件。"
            )
        } else {
            GeometryReader { geometry in
                let columnCount = max(
                    Int((geometry.size.width - 38) / 208),
                    1
                )
                let columns = Array(
                    repeating: GridItem(
                        .flexible(minimum: 170, maximum: 220),
                        spacing: 18,
                        alignment: .top
                    ),
                    count: columnCount
                )
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(visibleItems) { item in
                            ZStack(alignment: .bottomTrailing) {
                                RepositoryPosterCard(item: item)

                                if let onDownload {
                                    downloadMenu(
                                        repository: item.repository,
                                        action: onDownload
                                    )
                                    .padding(12)
                                }
                            }
                            .frame(maxWidth: 220)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onRoute?(item.destination)
                            }
                            .onAppear {
                                visibleRepositoryIDs.insert(item.id)
                                scheduleCoverLoading(
                                    columnCount: columnCount
                                )
                            }
                            .onDisappear {
                                visibleRepositoryIDs.remove(item.id)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(repositoryAccessibilityLabel(item))
                            .accessibilityHint(
                                scope == .local
                                    ? "打开仓库总览"
                                    : "可选择下载到本地"
                            )
                            .accessibilityIdentifier(
                                item.accessibilityIdentifier
                            )
                        }
                        if let onLoadNextPage {
                            Color.clear
                                .frame(height: 1)
                                .onAppear(perform: onLoadNextPage)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .topLeading
                    )
                }
                .scrollIndicators(.visible)
                .onAppear {
                    lastColumnCount = columnCount
                }
                .onChange(of: columnCount) { _, columnCount in
                    lastColumnCount = columnCount
                    scheduleCoverLoading(
                        columnCount: columnCount
                    )
                }
            }
        }
    }

    private func scheduleCoverLoading(columnCount: Int) {
        coverTask?.cancel()
        let visibleRepositoryIDs = self.visibleRepositoryIDs
        coverTask = Task {
            try? await Task.sleep(for: .milliseconds(45))
            guard !Task.isCancelled else {
                return
            }
            await viewModel.updateVisibleCovers(
                visibleRepositoryIDs: visibleRepositoryIDs,
                columnCount: columnCount
            )
        }
    }

    private func downloadMenu(
        repository: Repository,
        action:
            @escaping (Repository, RepositorySyncMode) -> Void
    ) -> some View {
        Menu {
            Button("手动同步") {
                action(repository, .manual)
            }
            Button("自动同步") {
                action(repository, .automatic)
            }
        } label: {
            Label("下载", systemImage: "arrow.down.to.line")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(GitMateTheme.accent)
                .clipShape(Capsule())
                .shadow(
                    color: GitMateTheme.accent.opacity(0.25),
                    radius: 8,
                    y: 3
                )
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("下载 \(repository.fullName)")
    }

    private func emptyState(
        symbol: String,
        title: String,
        message: String
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(GitMateTheme.accent)
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(GitMateTheme.textPrimary)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerDescription: String {
        if scope == .cloud {
            return "\(viewModel.items.count) 个云端仓库 · 滚动时按需加载封面"
        }
        return "\(viewModel.items.count) 个本地仓库 · 优先使用本地缓存封面"
    }

    private var readmeCoverCount: Int {
        viewModel.items.filter(\.cover.usesREADMEImage).count
    }

    private func repositoryAccessibilityLabel(
        _ item: RepositoryPosterItem
    ) -> String {
        [
            item.repository.fullName,
            item.repository.isPrivate ? "私有仓库" : "公开仓库",
            item.language ?? "未知语言",
            syncStateTitle(item.syncState)
        ].joined(separator: "，")
    }

    private func sortTitle(_ sort: RepositoryWallSort) -> String {
        switch sort {
        case .recentlyUpdated:
            "最近更新"
        case .name:
            "名称"
        case .size:
            "大小"
        }
    }

    private func visibilityFilterTitle(
        _ filter: RepositoryVisibilityFilter
    ) -> String {
        switch filter {
        case .all:
            "全部可见性"
        case .publicOnly:
            "仅公开"
        case .privateOnly:
            "仅私有"
        }
    }

    private func syncFilterTitle(
        _ filter: RepositorySyncStateFilter
    ) -> String {
        switch filter {
        case .all:
            "全部同步状态"
        case .synchronized:
            "已同步"
        case .needsAttention:
            "需要处理"
        case .notSynchronized:
            "尚未同步"
        case .unavailable:
            "同步异常"
        }
    }

    private func syncStateTitle(_ state: RepositorySyncState) -> String {
        switch state {
        case .synchronized:
            "已同步"
        case .needsAttention:
            "需要处理"
        case .notSynchronized:
            "尚未同步"
        case .unavailable:
            "同步异常"
        }
    }
}

private struct RepositoryPosterCard: View {
    let item: RepositoryPosterItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                cover

                HStack {
                    Label(
                        item.cover.usesREADMEImage ? "README" : "自动生成",
                        systemImage: item.cover.usesREADMEImage
                            ? "photo"
                            : "sparkles"
                    )
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Color.white.opacity(0.94))
                    .clipShape(Capsule())

                    Spacer(minLength: 4)

                    Text(item.repository.isPrivate ? "私有" : "公开")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(GitMateTheme.textPrimary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Color.white.opacity(0.94))
                        .clipShape(Capsule())
                }
                .padding(10)
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipped()

            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.repository.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(GitMateTheme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        GitMateAvatar(
                            url: item.repository.ownerAvatarURL,
                            size: 18
                        )
                        Text(item.owner)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(GitMateTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 7) {
                    metadataChip(
                        symbol: "circle.fill",
                        text: item.language ?? "未知语言",
                        symbolColor: languageColor(item.language)
                    )
                    metadataChip(
                        symbol: "internaldrive",
                        text: formattedSize,
                        symbolColor: GitMateTheme.textTertiary
                    )
                }

                Divider()

                HStack(spacing: 7) {
                    Circle()
                        .fill(syncStateColor)
                        .frame(width: 7, height: 7)
                    Text(syncStateTitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GitMateTheme.textPrimary)
                    Spacer(minLength: 4)
                    Text(syncModeTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
            }
            .padding(13)
        }
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
        .shadow(color: Color.black.opacity(0.055), radius: 14, y: 7)
        .contentShape(
            RoundedRectangle(
                cornerRadius: GitMateTheme.cornerRadius,
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private var cover: some View {
        switch item.cover {
        case let .cached(data, _, fallback):
            if let image = NSImage(data: data) {
                posterImage(Image(nsImage: image))
            } else {
                RepositoryFallbackCover(cover: fallback)
            }
        case let .remote(_, fallback):
            ZStack {
                RepositoryFallbackCover(cover: fallback)
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        case let .fallback(fallback):
            RepositoryFallbackCover(cover: fallback)
        }
    }

    private func posterImage(_ image: Image) -> some View {
        GeometryReader { geometry in
            image
                .resizable()
                .scaledToFill()
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .clipped()
        }
    }

    private func metadataChip(
        symbol: String,
        text: String,
        symbolColor: Color
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(symbolColor)
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(GitMateTheme.textSecondary)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(GitMateTheme.panel)
        .clipShape(Capsule())
    }

    private var formattedSize: String {
        let size = Int64(max(item.repository.sizeInKilobytes, 0))
        let (bytes, overflow) = size.multipliedReportingOverflow(by: 1_024)
        return ByteCountFormatter.string(
            fromByteCount: overflow ? Int64.max : bytes,
            countStyle: .file
        )
    }

    private var syncStateTitle: String {
        switch item.syncState {
        case .synchronized:
            "已同步"
        case .needsAttention:
            "需要处理"
        case .notSynchronized:
            "尚未同步"
        case .unavailable:
            "同步异常"
        }
    }

    private var syncStateColor: Color {
        switch item.syncState {
        case .synchronized:
            GitMateTheme.success
        case .needsAttention:
            GitMateTheme.warning
        case .notSynchronized:
            GitMateTheme.textTertiary
        case .unavailable:
            GitMateTheme.danger
        }
    }

    private var syncModeTitle: String {
        switch item.syncMode {
        case .automatic:
            "自动同步"
        case .manual:
            "手动同步"
        case .never:
            "不同步"
        }
    }

    private func languageColor(_ language: String?) -> Color {
        switch language?.lowercased() {
        case "swift":
            Color(red: 0.78, green: 0.22, blue: 0.10)
        case "typescript":
            Color(red: 0.08, green: 0.37, blue: 0.68)
        case "javascript":
            Color(red: 0.60, green: 0.48, blue: 0.03)
        case "python":
            Color(red: 0.10, green: 0.36, blue: 0.58)
        case "rust":
            Color(red: 0.45, green: 0.20, blue: 0.10)
        default:
            GitMateTheme.textTertiary
        }
    }
}

private struct RepositoryFallbackCover: View {
    let cover: FallbackRepositoryCover

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 150, height: 150)
                .offset(x: 55, y: -80)

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 20)
                .frame(width: 170, height: 170)
                .rotationEffect(.degrees(24))
                .offset(x: -80, y: 105)

            VStack(spacing: 9) {
                Text(cover.initials)
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.62)
                    .lineLimit(1)
                Capsule()
                    .fill(Color.white.opacity(0.68))
                    .frame(width: 42, height: 3)
            }
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var colors: [Color] {
        let palette = RepositoryFallbackPaletteResolver.resolve(cover)
        let baseHues = [0.58, 0.52, 0.38, 0.03, 0.74, 0.92]
        let hue = baseHues[palette.family % baseHues.count]
            + Double(palette.variant) * 0.012
        return [
            Color(
                hue: hue.truncatingRemainder(dividingBy: 1),
                saturation: 0.78,
                brightness: 0.46
            ),
            Color(
                hue: (hue + 0.055).truncatingRemainder(dividingBy: 1),
                saturation: 0.68,
                brightness: 0.70
            )
        ]
    }
}
