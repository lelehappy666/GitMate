import Foundation

final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class LockedRecorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value] = []

    func append(_ value: Value) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var snapshot: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

final class StubResponseQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [String]

    init(_ bodies: [String]) {
        self.bodies = bodies
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        guard bodies.count > 1 else { return bodies[0] }
        return bodies.removeFirst()
    }
}

func makeStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return URLSession(configuration: configuration)
}

func requestBodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        data.append(buffer, count: count)
    }
    return data
}

func stubResponse(
    for request: URLRequest,
    statusCode: Int = 200,
    headers: [String: String] = [:],
    body: String
) throws -> (HTTPURLResponse, Data) {
    guard let url = request.url,
          let response = HTTPURLResponse(
              url: url,
              statusCode: statusCode,
              httpVersion: nil,
              headerFields: headers
          ) else {
        throw URLError(.badURL)
    }
    return (response, Data(body.utf8))
}
