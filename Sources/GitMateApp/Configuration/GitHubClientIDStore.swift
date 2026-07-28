import Foundation

final class GitHubClientIDStore: @unchecked Sendable {
    private static let defaultsKey = "GitMateGitHubClientID"

    private let lock = NSLock()
    private var clientID: String

    init(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo,
        defaults: UserDefaults = .standard
    ) {
        let savedClientID = defaults.string(forKey: Self.defaultsKey)
        let environmentClientID = processInfo.environment[
            "GITMATE_GITHUB_CLIENT_ID"
        ]
        let bundledClientID = bundle.object(
            forInfoDictionaryKey: "GitMateGitHubClientID"
        ) as? String

        clientID = [
            savedClientID,
            environmentClientID,
            bundledClientID
        ]
        .compactMap { value in
            let normalized = value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized?.isEmpty == false ? normalized : nil
        }
        .first ?? ""
    }

    func current() -> String {
        lock.lock()
        defer { lock.unlock() }
        return clientID
    }

    func save(_ value: String) {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        clientID = normalized
        lock.unlock()
        UserDefaults.standard.set(normalized, forKey: Self.defaultsKey)
    }
}
