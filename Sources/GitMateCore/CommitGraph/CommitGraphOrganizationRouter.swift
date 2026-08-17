import Foundation

/// 为组织树边生成稳定的直角通道，并避开无关提交卡片的净空区域。
public struct CommitGraphOrganizationRouter: Sendable {
    public let clearance: Double
    public let stubLength: Double

    public init(clearance: Double = 28, stubLength: Double = 28) {
        self.clearance = max(clearance, 0)
        self.stubLength = max(stubLength, 0)
    }

    public func route(
        sourceRect: GraphRect,
        targetRect: GraphRect,
        sourceAnchor: PortAnchor,
        targetAnchor: PortAnchor,
        obstacles: [GraphRect],
        preferredChannel: Int
    ) -> [GraphPoint] {
        let source = CommitGraphPathGeometry.anchorPoint(
            rect: sourceRect,
            anchor: sourceAnchor
        )
        let target = CommitGraphPathGeometry.anchorPoint(
            rect: targetRect,
            anchor: targetAnchor
        )
        let sourceStub = CommitGraphPathGeometry.stubPoint(
            rect: sourceRect,
            anchor: sourceAnchor,
            length: stubLength
        )
        let targetStub = CommitGraphPathGeometry.stubPoint(
            rect: targetRect,
            anchor: targetAnchor,
            length: stubLength
        )
        let blocked = obstacles.compactMap { rect -> GraphRect? in
            guard rect.x.isFinite, rect.y.isFinite,
                  rect.width.isFinite, rect.height.isFinite
            else { return nil }
            return expanded(rect, by: clearance)
        }
        let middle = routeBetweenStubs(
            sourceStub,
            targetStub,
            blocked: blocked,
            preferredChannel: max(preferredChannel, 0)
        )
        return simplified([source] + middle + [target])
    }

    private func routeBetweenStubs(
        _ start: GraphPoint,
        _ end: GraphPoint,
        blocked: [GraphRect],
        preferredChannel: Int
    ) -> [GraphPoint] {
        guard start != end else { return [start] }
        if blocked.isEmpty {
            return fallback(start: start, end: end)
        }
        var xs = [start.x, end.x]
        var ys = [start.y, end.y]
        for rect in blocked {
            xs.append(rect.minimumX - 1)
            xs.append(rect.maximumX + 1)
            ys.append(rect.minimumY - 1)
            ys.append(rect.maximumY + 1)
        }
        let allX = xs
        let allY = ys
        let channelOffset = clearance + 28 + Double(preferredChannel) * 24
        xs.append((allX.min() ?? 0) - channelOffset)
        xs.append((allX.max() ?? 0) + channelOffset)
        ys.append((allY.min() ?? 0) - channelOffset)
        ys.append((allY.max() ?? 0) + channelOffset)
        xs = uniqueSorted(xs)
        ys = uniqueSorted(ys)

        let points = xs.flatMap { x in ys.map { GraphPoint(x: x, y: $0) } }
        let usable = points.map { point in
            !blocked.contains { contains($0, point) }
        }
        guard let startIndex = points.firstIndex(of: start),
              let endIndex = points.firstIndex(of: end)
        else { return fallback(start: start, end: end) }

        struct State: Hashable {
            let point: Int
            let direction: Int
        }
        struct Entry {
            let state: State
            let cost: Double
            let sequence: Int
        }
        var queue = [Entry(state: State(point: startIndex, direction: 0), cost: 0, sequence: 0)]
        var best: [State: Double] = [queue[0].state: 0]
        var previous: [State: State] = [:]
        var sequence = 1
        var finalState: State?

        while !queue.isEmpty {
            queue.sort {
                if $0.cost != $1.cost { return $0.cost < $1.cost }
                return $0.sequence < $1.sequence
            }
            let current = queue.removeFirst()
            guard current.cost <= best[current.state, default: .infinity] else {
                continue
            }
            if current.state.point == endIndex {
                finalState = current.state
                break
            }
            for neighbor in neighbors(
                of: current.state.point,
                xs: xs,
                ys: ys,
                usable: usable,
                points: points,
                blocked: blocked
            ) {
                let first = points[current.state.point]
                let second = points[neighbor]
                let direction = first.x == second.x ? 2 : 1
                let bendPenalty = current.state.direction == 0
                    || current.state.direction == direction ? 0 : 64
                let next = State(point: neighbor, direction: direction)
                let nextCost = current.cost
                    + abs(first.x - second.x)
                    + abs(first.y - second.y)
                    + Double(bendPenalty)
                guard nextCost < best[next, default: .infinity] else { continue }
                best[next] = nextCost
                previous[next] = current.state
                queue.append(Entry(state: next, cost: nextCost, sequence: sequence))
                sequence += 1
            }
        }
        guard var cursor = finalState else { return fallback(start: start, end: end) }
        var result = [points[cursor.point]]
        while let parent = previous[cursor] {
            cursor = parent
            result.append(points[cursor.point])
        }
        return simplified(result.reversed())
    }

    private func neighbors(
        of index: Int,
        xs: [Double],
        ys: [Double],
        usable: [Bool],
        points: [GraphPoint],
        blocked: [GraphRect]
    ) -> [Int] {
        let rowCount = ys.count
        let xIndex = index / rowCount
        let yIndex = index % rowCount
        let candidates = [
            xIndex > 0 ? index - rowCount : nil,
            xIndex + 1 < xs.count ? index + rowCount : nil,
            yIndex > 0 ? index - 1 : nil,
            yIndex + 1 < ys.count ? index + 1 : nil
        ].compactMap { $0 }
        return candidates.filter { candidate in
            usable[candidate]
                && !blocked.contains {
                    segmentIntersects(points[index], points[candidate], $0)
                }
        }
    }

    private func fallback(start: GraphPoint, end: GraphPoint) -> [GraphPoint] {
        let middleY = (start.y + end.y) / 2
        return simplified([
            start,
            GraphPoint(x: start.x, y: middleY),
            GraphPoint(x: end.x, y: middleY),
            end
        ])
    }

    private func expanded(_ rect: GraphRect, by padding: Double) -> GraphRect {
        GraphRect(
            x: rect.x - padding,
            y: rect.y - padding,
            width: rect.width + padding * 2,
            height: rect.height + padding * 2
        )
    }

    private func contains(_ rect: GraphRect, _ point: GraphPoint) -> Bool {
        point.x >= rect.minimumX && point.x <= rect.maximumX
            && point.y >= rect.minimumY && point.y <= rect.maximumY
    }

    private func segmentIntersects(
        _ start: GraphPoint,
        _ end: GraphPoint,
        _ rect: GraphRect
    ) -> Bool {
        if start.x == end.x {
            return start.x >= rect.minimumX && start.x <= rect.maximumX
                && max(start.y, end.y) >= rect.minimumY
                && min(start.y, end.y) <= rect.maximumY
        }
        if start.y == end.y {
            return start.y >= rect.minimumY && start.y <= rect.maximumY
                && max(start.x, end.x) >= rect.minimumX
                && min(start.x, end.x) <= rect.maximumX
        }
        return true
    }

    private func uniqueSorted(_ values: [Double]) -> [Double] {
        Array(Set(values.filter(\.isFinite))).sorted()
    }

    private func simplified<S: Sequence>(_ points: S) -> [GraphPoint]
    where S.Element == GraphPoint {
        var result: [GraphPoint] = []
        for point in points {
            if result.last == point { continue }
            while result.count >= 2,
                  CommitGraphPathGeometry.areCollinear(
                    result[result.count - 2], result[result.count - 1], point
                  ) {
                result.removeLast()
            }
            result.append(point)
        }
        return result
    }
}
