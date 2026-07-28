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
    /// Loads at most `maximumBytes` from the response body.
    ///
    /// Implementations must enforce the ceiling while receiving the body rather than
    /// buffering an unbounded response and checking its size afterward.
    func data(
        for request: URLRequest,
        maximumBytes: Int
    ) async throws -> HTTPDataResponse
}

public enum HTTPDataLoadingError: Error, Equatable {
    case invalidResponse
    case invalidByteLimit
    case responseTooLarge
}

public struct URLSessionHTTPDataLoader: HTTPDataLoading {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(
        for request: URLRequest,
        maximumBytes: Int
    ) async throws -> HTTPDataResponse {
        guard maximumBytes >= 0 else {
            throw HTTPDataLoadingError.invalidByteLimit
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw HTTPDataLoadingError.invalidResponse
        }

        if response.expectedContentLength > Int64(maximumBytes) {
            throw HTTPDataLoadingError.responseTooLarge
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(
                min(Int(response.expectedContentLength), maximumBytes)
            )
        }

        for try await byte in bytes {
            guard data.count < maximumBytes else {
                throw HTTPDataLoadingError.responseTooLarge
            }
            data.append(byte)
        }

        return HTTPDataResponse(data: data, statusCode: response.statusCode)
    }
}
