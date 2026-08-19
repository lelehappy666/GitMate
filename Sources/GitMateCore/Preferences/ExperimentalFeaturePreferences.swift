import Foundation
import Observation

public protocol ExperimentalFeaturePreferenceStoring: Sendable {
    func repositoryManagementEnabled() -> Bool
    func setRepositoryManagementEnabled(_ enabled: Bool)
    func commitGraphCanvasEnabled() -> Bool
    func setCommitGraphCanvasEnabled(_ enabled: Bool)
}

public final class UserDefaultsExperimentalFeaturePreferenceStore:
    ExperimentalFeaturePreferenceStoring,
    @unchecked Sendable
{
    private let defaults: UserDefaults
    private let lock = NSLock()
    private let repositoryManagementKey =
        "GitMate.ExperimentalFeatures.RepositoryManagementEnabled"
    private let commitGraphCanvasKey =
        "GitMate.ExperimentalFeatures.CommitGraphCanvasEnabled"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func repositoryManagementEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return defaults.bool(forKey: repositoryManagementKey)
    }

    public func setRepositoryManagementEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        defaults.set(enabled, forKey: repositoryManagementKey)
    }

    public func commitGraphCanvasEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return defaults.bool(forKey: commitGraphCanvasKey)
    }

    public func setCommitGraphCanvasEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        defaults.set(enabled, forKey: commitGraphCanvasKey)
    }
}

public final class InMemoryExperimentalFeaturePreferenceStore:
    ExperimentalFeaturePreferenceStoring,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var repositoryManagementValue: Bool
    private var commitGraphCanvasValue: Bool

    public init(
        repositoryManagementEnabled: Bool = false,
        commitGraphCanvasEnabled: Bool = false
    ) {
        repositoryManagementValue = repositoryManagementEnabled
        commitGraphCanvasValue = commitGraphCanvasEnabled
    }

    public func repositoryManagementEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return repositoryManagementValue
    }

    public func setRepositoryManagementEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        repositoryManagementValue = enabled
    }

    public func commitGraphCanvasEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return commitGraphCanvasValue
    }

    public func setCommitGraphCanvasEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        commitGraphCanvasValue = enabled
    }
}

@MainActor
@Observable
public final class ExperimentalFeaturePreferences {
    public private(set) var repositoryManagementEnabled: Bool
    public private(set) var commitGraphCanvasEnabled: Bool
    @ObservationIgnored private let store: any ExperimentalFeaturePreferenceStoring

    public init(store: any ExperimentalFeaturePreferenceStoring) {
        self.store = store
        repositoryManagementEnabled = store.repositoryManagementEnabled()
        commitGraphCanvasEnabled = store.commitGraphCanvasEnabled()
    }

    public func setRepositoryManagementEnabled(_ enabled: Bool) {
        guard repositoryManagementEnabled != enabled else { return }
        store.setRepositoryManagementEnabled(enabled)
        repositoryManagementEnabled = enabled
    }

    public func setCommitGraphCanvasEnabled(_ enabled: Bool) {
        guard commitGraphCanvasEnabled != enabled else { return }
        store.setCommitGraphCanvasEnabled(enabled)
        commitGraphCanvasEnabled = enabled
    }
}

public struct RepositoryManagementAccessPolicy: Equatable, Sendable {
    public let isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    public var canOpenWorkspace: Bool { isEnabled }

    public func shouldDismissWorkspace(isPresented: Bool) -> Bool {
        isPresented && !isEnabled
    }
}

public struct CommitGraphCanvasAccessPolicy: Equatable, Sendable {
    public let isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    public var showsLayoutPicker: Bool { isEnabled }

    public func resolve(_ requestedMode: CommitGraphViewMode) ->
        CommitGraphViewMode
    {
        isEnabled ? requestedMode : .traditional
    }
}
