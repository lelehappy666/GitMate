import GitMateCore
import SwiftUI

struct WorkspaceSidebar: View {
    @Binding var selection: WorkspaceSelection
    let repositories: [Repository]
    let selectionGate: RepositorySelectionGate
    let account: GitHubAccount
    let onCommitGraphRequested: (Int64) -> Void
    @State private var currentRepositoryID: Int64?

    init(
        selection: Binding<WorkspaceSelection>,
        repositories: [Repository],
        selectionGate: RepositorySelectionGate,
        account: GitHubAccount,
        onCommitGraphRequested: @escaping (Int64) -> Void
    ) {
        _selection = selection
        self.repositories = repositories
        self.selectionGate = selectionGate
        self.account = account
        self.onCommitGraphRequested = onCommitGraphRequested
        _currentRepositoryID = State(
            initialValue: selection.wrappedValue.route.repositoryID
                ?? repositories.first?.id
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            appIdentity
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 4) {
                routeButton(
                    title: "全局工作台",
                    symbol: "square.grid.2x2",
                    route: .dashboard
                )
                routeButton(
                    title: "全部仓库",
                    symbol: "square.stack.3d.up",
                    route: .repositories
                )
            }
            .padding(.horizontal, 10)

            Divider()
                .padding(.vertical, 18)
                .padding(.horizontal, 16)

            Text("当前仓库")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GitMateTheme.textTertiary)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            if !repositories.isEmpty || currentRepositoryID != nil {
                RepositorySwitcherView(
                    repositories: repositories,
                    selectedRepositoryID: currentRepositoryID,
                    onSelect: selectRepository,
                    onRepositoriesChanged: validateCurrentRepository
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
            }

            VStack(alignment: .leading, spacing: 4) {
                routeButton(
                    title: "总览",
                    symbol: "rectangle.grid.1x2",
                    route: repositoryRoute { .repositoryOverview(repositoryID: $0) }
                )
                routeButton(
                    title: "README",
                    symbol: "text.document",
                    route: repositoryRoute { .readme(repositoryID: $0) }
                )
                routeButton(
                    title: "文件与提交",
                    symbol: "folder",
                    route: repositoryRoute { .filesAndCommits(repositoryID: $0) }
                )
                routeButton(
                    title: "提交图",
                    symbol: "point.3.connected.trianglepath.dotted",
                    route: repositoryRoute { .commitGraph(repositoryID: $0) },
                    onSelect: {
                        guard let currentRepositoryID else { return }
                        onCommitGraphRequested(currentRepositoryID)
                    }
                )
            }
            .padding(.horizontal, 10)
            .opacity(currentRepositoryID == nil ? 0.45 : 1)
            .disabled(currentRepositoryID == nil)

            Spacer(minLength: 16)

            Divider()
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            Label("设置", systemImage: "gearshape")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
                .padding(.horizontal, 18)
                .padding(.bottom, 16)

            accountIdentity
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(minWidth: 232, idealWidth: 248, maxWidth: 260, maxHeight: .infinity)
        .background(.white)
        .onAppear {
            _ = validateCurrentRepository()
        }
        .onChange(of: selection.route) { _, route in
            if let repositoryID = route.repositoryID {
                apply(
                    selectionGate.validatedSelectionState(
                        selectedRepositoryID: repositoryID,
                        route: route
                    )
                )
            }
        }
    }

    private var appIdentity: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(GitMateTheme.accent)
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)

            Text("GitMate")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(GitMateTheme.textPrimary)
        }
    }

    private var accountIdentity: some View {
        HStack(spacing: 9) {
            GitMateAvatar(url: account.avatarURL, size: 28)
            Text(account.login)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GitMateTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func repositoryRoute(
        _ makeRoute: (Int64) -> WorkspaceRoute
    ) -> WorkspaceRoute {
        guard let repositoryID = currentRepositoryID else {
            return .repositories
        }
        return makeRoute(repositoryID)
    }

    private func selectRepository(_ repository: Repository) {
        apply(
            selectionGate.selectionState(
                for: repository.id,
                from: selection.route
            )
        )
    }

    private func validateCurrentRepository() -> Bool {
        let state = selectionGate.validatedSelectionState(
            selectedRepositoryID: currentRepositoryID,
            route: selection.route
        )
        let didInvalidateSelection = currentRepositoryID != nil
            && state.selectedRepositoryID == nil
        apply(state)
        return didInvalidateSelection
    }

    private func apply(_ state: RepositorySwitchState) {
        if selection.route != state.route {
            selection.route = state.route
        }
        if currentRepositoryID != state.selectedRepositoryID {
            currentRepositoryID = state.selectedRepositoryID
        }
    }

    private func routeButton(
        title: String,
        symbol: String,
        route: WorkspaceRoute,
        onSelect: (() -> Void)? = nil
    ) -> some View {
        Button {
            selection.route = route
            onSelect?()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 17)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: 14, weight: selection.route == route ? .semibold : .medium))
            .foregroundStyle(
                selection.route == route
                    ? GitMateTheme.accent
                    : GitMateTheme.textSecondary
            )
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                selection.route == route
                    ? GitMateTheme.accentSoft
                    : .clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
