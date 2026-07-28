@preconcurrency import Foundation
@preconcurrency import Network

public enum NetworkStatus: Equatable, Sendable {
    case connected
    case disconnected
}

public protocol NetworkMonitoring: Sendable {
    func statusUpdates() -> AsyncStream<NetworkStatus>
}

public final class NWPathNetworkMonitor: NetworkMonitoring, @unchecked Sendable {
    public init() {}

    public func statusUpdates() -> AsyncStream<NetworkStatus> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            let box = NetworkMonitorBox(monitor)
            let queue = DispatchQueue(
                label: "com.gitmate.network-monitor",
                qos: .utility
            )

            monitor.pathUpdateHandler = { path in
                continuation.yield(
                    path.status == .satisfied ? .connected : .disconnected
                )
            }
            monitor.start(queue: queue)

            continuation.onTermination = { _ in
                box.cancel()
            }
        }
    }
}

private final class NetworkMonitorBox: @unchecked Sendable {
    private let monitor: NWPathMonitor

    init(_ monitor: NWPathMonitor) {
        self.monitor = monitor
    }

    func cancel() {
        monitor.cancel()
    }
}
