import Foundation

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
