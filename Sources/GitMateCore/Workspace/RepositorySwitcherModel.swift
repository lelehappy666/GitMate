import Foundation

public struct RepositorySwitchState: Equatable, Sendable {
    public let selectedRepositoryID: Int64?
    public let route: WorkspaceRoute

    public init(
        selectedRepositoryID: Int64?,
        route: WorkspaceRoute
    ) {
        self.selectedRepositoryID = selectedRepositoryID
        self.route = route
    }
}

public final class RepositorySelectionGate {
    private var repositoryIDs: Set<Int64>

    public init(repositories: [Repository]) {
        repositoryIDs = Set(repositories.map(\.id))
    }

    public func replaceRepositories(_ repositories: [Repository]) {
        repositoryIDs = Set(repositories.map(\.id))
    }

    public func selectionState(
        for repositoryID: Int64,
        from route: WorkspaceRoute
    ) -> RepositorySwitchState {
        guard repositoryIDs.contains(repositoryID) else {
            return unavailableSelectionState(from: route)
        }
        return RepositorySwitchState(
            selectedRepositoryID: repositoryID,
            route: route.replacingRepositoryID(repositoryID)
        )
    }

    public func validatedSelectionState(
        selectedRepositoryID: Int64?,
        route: WorkspaceRoute
    ) -> RepositorySwitchState {
        guard let selectedRepositoryID else {
            return RepositorySwitchState(
                selectedRepositoryID: nil,
                route: route
            )
        }
        return selectionState(for: selectedRepositoryID, from: route)
    }

    private func unavailableSelectionState(
        from route: WorkspaceRoute
    ) -> RepositorySwitchState {
        RepositorySwitchState(
            selectedRepositoryID: nil,
            route: route.fallbackAfterCurrentRepositoryRemoval()
        )
    }
}

public enum RepositorySwitcherModel {
    public static func filteredRepositories(
        _ repositories: [Repository],
        query: String
    ) -> [Repository] {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else {
            return repositories
        }

        return repositories.filter { repository in
            normalized(repository.name).contains(normalizedQuery)
                || normalized(repository.fullName).contains(normalizedQuery)
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }
}
