import Foundation
import Observation

public protocol ExperimentalFeaturePreferenceStoring: Sendable {
    func repositoryManagementEnabled() -> Bool
    func setRepositoryManagementEnabled(_ enabled: Bool)
}

public final class UserDefaultsExperimentalFeaturePreferenceStore:
    ExperimentalFeaturePreferenceStoring,
    @unchecked Sendable
{
    private let defaults: UserDefaults
    private let lock = NSLock()
    private let key = "GitMate.ExperimentalFeatures.RepositoryManagementEnabled"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func repositoryManagementEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return defaults.bool(forKey: key)
    }

    public func setRepositoryManagementEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        defaults.set(enabled, forKey: key)
    }
}

public final class InMemoryExperimentalFeaturePreferenceStore:
    ExperimentalFeaturePreferenceStoring,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var enabled: Bool

    public init(repositoryManagementEnabled: Bool = false) {
        enabled = repositoryManagementEnabled
    }

    public func repositoryManagementEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }

    public func setRepositoryManagementEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.enabled = enabled
    }
}

@MainActor
@Observable
public final class ExperimentalFeaturePreferences {
    public private(set) var repositoryManagementEnabled: Bool
    @ObservationIgnored private let store: any ExperimentalFeaturePreferenceStoring

    public init(store: any ExperimentalFeaturePreferenceStoring) {
        self.store = store
        repositoryManagementEnabled = store.repositoryManagementEnabled()
    }

    public func setRepositoryManagementEnabled(_ enabled: Bool) {
        guard repositoryManagementEnabled != enabled else { return }
        store.setRepositoryManagementEnabled(enabled)
        repositoryManagementEnabled = enabled
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
