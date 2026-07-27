import Foundation

public struct HTTPDataResponse: Sendable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public protocol HTTPDataLoading: Sendable {
    func data(for request: URLRequest) async throws -> HTTPDataResponse
}

public enum HTTPDataLoadingError: Error {
    case invalidResponse
}

public struct URLSessionHTTPDataLoader: HTTPDataLoading {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> HTTPDataResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw HTTPDataLoadingError.invalidResponse
        }

        return HTTPDataResponse(data: data, statusCode: response.statusCode)
    }
}
