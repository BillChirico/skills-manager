import Foundation
import Testing

@testable import SkillsCore

struct URLSessionHTTPDataLoaderTests {
    @Test("An unknown-length response stops as streamed bytes cross the ceiling")
    func stopsOversizedStream() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChunkedResponseURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
        }
        let loader = URLSessionHTTPDataLoader(session: session)
        let request = URLRequest(
            url: try #require(URL(string: "https://stream.test/payload"))
        )

        await #expect(throws: HTTPDataLoadingError.responseTooLarge) {
            try await loader.data(for: request, maximumBytes: 5)
        }
    }

    @Test("A response exactly at the byte ceiling is returned")
    func acceptsExactLimit() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChunkedResponseURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
        }
        let loader = URLSessionHTTPDataLoader(session: session)
        let request = URLRequest(
            url: try #require(URL(string: "https://stream.test/payload"))
        )

        let response = try await loader.data(for: request, maximumBytes: 6)

        #expect(response.statusCode == 200)
        #expect(response.data == Data([0, 1, 2, 3, 4, 5]))
    }
}

private final class ChunkedResponseURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "stream.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )
        else {
            client?.urlProtocol(
                self,
                didFailWithError: HTTPDataLoadingError.invalidResponse
            )
            return
        }

        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: Data([0, 1, 2]))
        client?.urlProtocol(self, didLoad: Data([3, 4, 5]))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
