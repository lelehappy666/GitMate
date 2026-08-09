import Foundation

public final class WorkspaceRateLimitGate: @unchecked Sendable {
    private let lock = NSLock()
    private var pausedUntil: Date?

    public init() {}

    public func check(now: Date = Date()) throws {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard let pausedUntil else {
            return
        }
        if pausedUntil <= now {
            self.pausedUntil = nil
            return
        }
        throw WorkspaceAPIError.rateLimited(resetAt: pausedUntil)
    }

    public func pause(until resetAt: Date) {
        lock.lock()
        defer {
            lock.unlock()
        }
        pausedUntil = max(pausedUntil ?? resetAt, resetAt)
    }

    public func reset() {
        lock.lock()
        pausedUntil = nil
        lock.unlock()
    }

    public var resetAt: Date? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return pausedUntil
    }
}
