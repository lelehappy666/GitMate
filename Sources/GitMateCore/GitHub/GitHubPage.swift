import Foundation

public struct GitHubPage<Element> {
    public let items: [Element]
    public let nextPageURL: URL?

    public init(items: [Element], nextPageURL: URL?) {
        self.items = items
        self.nextPageURL = nextPageURL
    }
}

public struct GitHubResponseMetadata: Equatable, Sendable {
    public let statusCode: Int
    public let url: URL?
    private let headers: [String: String]

    init(response: HTTPURLResponse) {
        statusCode = response.statusCode
        url = response.url
        headers = response.allHeaderFields.reduce(into: [:]) { result, item in
            guard let key = item.key as? String else {
                return
            }
            result[key.lowercased()] = String(describing: item.value)
        }
    }

    public func headerValue(for name: String) -> String? {
        headers[name.lowercased()]
    }
}

public struct GitHubRESTResponse<Value> {
    public let value: Value
    public let metadata: GitHubResponseMetadata

    public init(value: Value, metadata: GitHubResponseMetadata) {
        self.value = value
        self.metadata = metadata
    }
}
