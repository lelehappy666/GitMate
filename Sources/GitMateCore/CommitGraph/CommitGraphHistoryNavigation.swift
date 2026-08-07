import Foundation

public enum CommitGraphHistoryMarkerKind: String, Sendable {
    case head
    case localBranch
    case remoteBranch
    case tag
    case group
    case region
}

public struct CommitGraphHistoryMarker:
    Equatable,
    Identifiable,
    Sendable
{
    public let id: String
    public let title: String
    public let hash: String
    public let row: Int
    public let kind: CommitGraphHistoryMarkerKind
    public let colorHex: String?

    public init(
        id: String,
        title: String,
        hash: String,
        row: Int,
        kind: CommitGraphHistoryMarkerKind,
        colorHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.hash = hash
        self.row = max(row, 0)
        self.kind = kind
        self.colorHex = colorHex
    }
}

/// 提交历史导航条的纯函数集合。生成标记只在 Git 快照或场景
/// 变化时执行，绘制阶段不会遍历全部提交。
public enum CommitGraphHistoryNavigation {
    public static func progress(row: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        let clamped = min(max(row, 0), count - 1)
        return Double(clamped) / Double(count - 1)
    }

    public static func row(progress: Double, count: Int) -> Int {
        guard count > 1 else { return 0 }
        let normalized = progress.isFinite
            ? min(max(progress, 0), 1)
            : 0
        return Int((normalized * Double(count - 1)).rounded())
    }

    public static func markers(
        traditionalLayout: CommitGraphTraditionalLayoutResult,
        canvasLayout: CommitGraphLayoutResult,
        scene: CommitGraphSceneState
    ) -> [CommitGraphHistoryMarker] {
        guard !traditionalLayout.rows.isEmpty else { return [] }
        let rowByHash = Dictionary(
            traditionalLayout.rows.map { ($0.commit.fullHash, $0.row) },
            uniquingKeysWith: { first, _ in first }
        )
        var result: [CommitGraphHistoryMarker] = []
        result.reserveCapacity(scene.groups.count + scene.regions.count + 16)

        for row in traditionalLayout.rows {
            for (index, reference) in traditionalLayout
                .references(hash: row.commit.fullHash)
                .enumerated() {
                let kind: CommitGraphHistoryMarkerKind
                switch reference.kind {
                case .head:
                    kind = .head
                case .localBranch:
                    kind = .localBranch
                case .remoteBranch:
                    kind = .remoteBranch
                case .tag:
                    kind = .tag
                }
                result.append(
                    CommitGraphHistoryMarker(
                        id: "ref:\(row.commit.fullHash):\(index):\(reference.name)",
                        title: reference.name,
                        hash: row.commit.fullHash,
                        row: row.row,
                        kind: kind
                    )
                )
            }
        }

        for group in scene.groups {
            guard let representative = group.memberHashes.compactMap({ hash in
                rowByHash[hash].map { (hash, $0) }
            }).min(by: { $0.1 < $1.1 }) else { continue }
            result.append(
                CommitGraphHistoryMarker(
                    id: "group:\(group.id.uuidString)",
                    title: group.title,
                    hash: representative.0,
                    row: representative.1,
                    kind: .group
                )
            )
        }

        if !scene.regions.isEmpty {
            let groupedPositions = Dictionary(
                scene.groups.flatMap { group in
                    group.relativePositions.map { hash, relative in
                        (
                            hash,
                            GraphPoint(
                                x: group.origin.x + relative.x,
                                y: group.origin.y + relative.y
                            )
                        )
                    }
                },
                uniquingKeysWith: { first, _ in first }
            )
            let positionedNodes = canvasLayout.nodes.map { node in
                (
                    node,
                    groupedPositions[node.hash]
                        ?? scene.nodePositions[node.hash]
                        ?? GraphPoint(x: node.x, y: node.y)
                )
            }
            for region in scene.regions {
                let candidates = positionedNodes.filter { _, position in
                    contains(region.rect, point: position)
                }
                let nearest = (candidates.isEmpty ? positionedNodes : candidates)
                    .min { lhs, rhs in
                        abs(lhs.1.y - region.rect.midpointY)
                            < abs(rhs.1.y - region.rect.midpointY)
                    }
                guard let nearest,
                      let row = rowByHash[nearest.0.hash]
                else { continue }
                result.append(
                    CommitGraphHistoryMarker(
                        id: "region:\(region.id.uuidString)",
                        title: region.title,
                        hash: nearest.0.hash,
                        row: row,
                        kind: .region,
                        colorHex: region.colorHex
                    )
                )
            }
        }

        return result.sorted {
            ($0.row, markerPriority($0.kind), $0.title, $0.id)
                < ($1.row, markerPriority($1.kind), $1.title, $1.id)
        }
    }

    private static func contains(
        _ rect: GraphRect,
        point: GraphPoint
    ) -> Bool {
        point.x >= rect.minimumX && point.x <= rect.maximumX
            && point.y >= rect.minimumY && point.y <= rect.maximumY
    }

    private static func markerPriority(
        _ kind: CommitGraphHistoryMarkerKind
    ) -> Int {
        switch kind {
        case .head: 0
        case .localBranch: 1
        case .remoteBranch: 2
        case .tag: 3
        case .group: 4
        case .region: 5
        }
    }
}
