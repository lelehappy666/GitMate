import Foundation

struct TestCase: Sendable {
    let name: String
    let body: @Sendable () async throws -> Void

    init(_ name: String, body: @escaping @Sendable () async throws -> Void) {
        self.name = name
        self.body = body
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else {
        throw TestFailure(description: message)
    }
}

func expectEqual<T: Equatable>(
    _ actual: @autoclosure () -> T,
    _ expected: T,
    _ message: String
) throws {
    let value = actual()
    guard value == expected else {
        throw TestFailure(
            description: "\(message)，实际值：\(value)，预期值：\(expected)"
        )
    }
}
