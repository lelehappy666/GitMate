public struct SyncProgress: Equatable, Sendable {
    public var completed: Int
    public var total: Int
    public var currentRepository: String?
    public var currentFile: String?

    public init(
        completed: Int = 0,
        total: Int = 0,
        currentRepository: String? = nil,
        currentFile: String? = nil
    ) {
        self.completed = completed
        self.total = total
        self.currentRepository = currentRepository
        self.currentFile = currentFile
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }
}
