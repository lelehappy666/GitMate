public struct WorkspaceRepositoryGroups: Equatable, Sendable {
    public let local: [Repository]
    public let cloud: [Repository]

    public init(local: [Repository], cloud: [Repository]) {
        self.local = local
        self.cloud = cloud
    }
}

public enum WorkspaceRepositoryClassifier {
    public static func classify(
        repositories: [Repository],
        records: [LocalRepositoryRecord],
        preferences: [RepositorySyncPreference]
    ) -> WorkspaceRepositoryGroups {
        let recordsByID = Dictionary(
            records.map { ($0.repository.id, $0) },
            uniquingKeysWith: { _, newest in newest }
        )
        let modesByID = Dictionary(
            preferences.map { ($0.repositoryID, $0.mode) },
            uniquingKeysWith: { _, newest in newest }
        )
        let local = repositories.filter { repository in
            let availability = recordsByID[repository.id]?.availability
                ?? .missing
            return availability != .missing
                || (modesByID[repository.id] ?? .never) != .never
        }
        let localIDs = Set(local.map(\.id))
        return WorkspaceRepositoryGroups(
            local: local,
            cloud: repositories.filter {
                !localIDs.contains($0.id)
            }
        )
    }
}
