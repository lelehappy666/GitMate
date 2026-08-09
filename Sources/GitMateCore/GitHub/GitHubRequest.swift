import Foundation

public enum HTTPMethod: String, Codable, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

public struct GitHubRequest: Sendable {
    public let method: HTTPMethod
    public let path: String?
    public let absoluteURL: URL?
    public let queryItems: [URLQueryItem]
    public let body: Data?
    public let additionalAccept: String?

    public init(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        additionalAccept: String? = nil
    ) {
        self.method = method
        self.path = path
        self.absoluteURL = nil
        self.queryItems = queryItems
        self.body = body
        self.additionalAccept = additionalAccept
    }

    public init<Body: Encodable>(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        encodableBody: Body,
        additionalAccept: String? = nil
    ) throws {
        self.method = method
        self.path = path
        self.absoluteURL = nil
        self.queryItems = queryItems
        self.body = try JSONEncoder().encode(encodableBody)
        self.additionalAccept = additionalAccept
    }

    public init(
        method: HTTPMethod = .get,
        absoluteURL: URL,
        additionalAccept: String? = nil
    ) {
        self.method = method
        self.path = nil
        self.absoluteURL = absoluteURL
        self.queryItems = []
        self.body = nil
        self.additionalAccept = additionalAccept
    }

    public static func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
            ?? value
    }
}
