import Foundation

public enum CommitGraphPathGeometry {
    private static let comparisonTolerance = 0.001

    public static func anchorPoint(
        rect: GraphRect,
        anchor: PortAnchor
    ) -> GraphPoint {
        switch anchor.side {
        case .top:
            GraphPoint(
                x: rect.minimumX + rect.width * anchor.offset,
                y: rect.minimumY
            )
        case .right:
            GraphPoint(
                x: rect.maximumX,
                y: rect.minimumY + rect.height * anchor.offset
            )
        case .bottom:
            GraphPoint(
                x: rect.minimumX + rect.width * anchor.offset,
                y: rect.maximumY
            )
        case .left:
            GraphPoint(
                x: rect.minimumX,
                y: rect.minimumY + rect.height * anchor.offset
            )
        }
    }

    public static func stubPoint(
        rect: GraphRect,
        anchor: PortAnchor,
        length: Double = 28
    ) -> GraphPoint {
        let point = anchorPoint(rect: rect, anchor: anchor)
        let direction = direction(for: anchor.side)
        let safeLength = length.isFinite ? max(length, 0) : 0
        return GraphPoint(
            x: point.x + direction.x * safeLength,
            y: point.y + direction.y * safeLength
        )
    }

    public static func curve(
        startRect: GraphRect,
        startAnchor: PortAnchor,
        endRect: GraphRect,
        endAnchor: PortAnchor
    ) -> CommitGraphGeneratedPath {
        let start = anchorPoint(rect: startRect, anchor: startAnchor)
        let end = anchorPoint(rect: endRect, anchor: endAnchor)
        let startDirection = direction(for: startAnchor.side)
        let endDirection = direction(for: endAnchor.side)
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let distance = hypot(deltaX, deltaY)
        let controlLength = max(56, min(distance * 0.35, 180))

        return .curve(
            start: start,
            control1: GraphPoint(
                x: start.x + startDirection.x * controlLength,
                y: start.y + startDirection.y * controlLength
            ),
            control2: GraphPoint(
                x: end.x + endDirection.x * controlLength,
                y: end.y + endDirection.y * controlLength
            ),
            end: end
        )
    }

    public static func orthogonal(
        startRect: GraphRect,
        startAnchor: PortAnchor,
        endRect: GraphRect,
        endAnchor: PortAnchor,
        stubLength: Double = 28
    ) -> CommitGraphGeneratedPath {
        let start = anchorPoint(rect: startRect, anchor: startAnchor)
        let end = anchorPoint(rect: endRect, anchor: endAnchor)
        let startStub = stubPoint(
            rect: startRect,
            anchor: startAnchor,
            length: stubLength
        )
        let endStub = stubPoint(
            rect: endRect,
            anchor: endAnchor,
            length: stubLength
        )
        let points: [GraphPoint]

        switch startAnchor.side {
        case .left, .right:
            let middleX = (startStub.x + endStub.x) / 2
            points = [
                start,
                startStub,
                GraphPoint(x: middleX, y: startStub.y),
                GraphPoint(x: middleX, y: endStub.y),
                endStub,
                end
            ]
        case .top, .bottom:
            let middleY = (startStub.y + endStub.y) / 2
            points = [
                start,
                startStub,
                GraphPoint(x: startStub.x, y: middleY),
                GraphPoint(x: endStub.x, y: middleY),
                endStub,
                end
            ]
        }

        return .polyline(points: simplified(points))
    }

    public static func areCollinear(
        _ first: GraphPoint,
        _ second: GraphPoint,
        _ third: GraphPoint
    ) -> Bool {
        let crossProduct = (second.x - first.x) * (third.y - second.y)
            - (second.y - first.y) * (third.x - second.x)
        return abs(crossProduct) <= comparisonTolerance
    }

    public static func labelPoint(
        for path: CommitGraphGeneratedPath
    ) -> GraphPoint {
        switch path {
        case let .curve(start, control1, control2, end):
            return cubicPoint(
                start: start,
                control1: control1,
                control2: control2,
                end: end,
                t: 0.5
            )
        case let .polyline(points):
            return polylineMidpoint(points)
        }
    }

    private static func direction(
        for side: CommitGraphPortSide
    ) -> GraphPoint {
        switch side {
        case .top:
            GraphPoint(x: 0, y: -1)
        case .right:
            GraphPoint(x: 1, y: 0)
        case .bottom:
            GraphPoint(x: 0, y: 1)
        case .left:
            GraphPoint(x: -1, y: 0)
        }
    }

    private static func simplified(
        _ points: [GraphPoint]
    ) -> [GraphPoint] {
        var unique: [GraphPoint] = []
        for point in points {
            if let last = unique.last,
               distance(last, point) <= comparisonTolerance {
                continue
            }
            unique.append(point)
        }

        var result: [GraphPoint] = []
        for point in unique {
            while result.count >= 2,
                  areCollinear(
                    result[result.count - 2],
                    result[result.count - 1],
                    point
                  ) {
                result.removeLast()
            }
            result.append(point)
        }
        return result
    }

    private static func cubicPoint(
        start: GraphPoint,
        control1: GraphPoint,
        control2: GraphPoint,
        end: GraphPoint,
        t: Double
    ) -> GraphPoint {
        let inverse = 1 - t
        let startWeight = inverse * inverse * inverse
        let firstWeight = 3 * inverse * inverse * t
        let secondWeight = 3 * inverse * t * t
        let endWeight = t * t * t
        return GraphPoint(
            x: start.x * startWeight
                + control1.x * firstWeight
                + control2.x * secondWeight
                + end.x * endWeight,
            y: start.y * startWeight
                + control1.y * firstWeight
                + control2.y * secondWeight
                + end.y * endWeight
        )
    }

    private static func polylineMidpoint(
        _ points: [GraphPoint]
    ) -> GraphPoint {
        guard let first = points.first else { return .zero }
        guard points.count > 1 else { return first }

        let lengths = zip(points, points.dropFirst()).map(distance)
        let totalLength = lengths.reduce(0, +)
        guard totalLength > comparisonTolerance else { return first }
        let target = totalLength / 2
        var travelled = 0.0

        for index in lengths.indices {
            let length = lengths[index]
            if travelled + length >= target {
                let ratio = (target - travelled) / length
                let start = points[index]
                let end = points[index + 1]
                return GraphPoint(
                    x: start.x + (end.x - start.x) * ratio,
                    y: start.y + (end.y - start.y) * ratio
                )
            }
            travelled += length
        }
        return points.last ?? first
    }

    private static func distance(
        _ first: GraphPoint,
        _ second: GraphPoint
    ) -> Double {
        hypot(second.x - first.x, second.y - first.y)
    }
}
