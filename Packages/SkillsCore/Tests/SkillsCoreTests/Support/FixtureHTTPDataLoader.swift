import Foundation

@testable import SkillsCore

actor FixtureHTTPDataLoader: HTTPDataLoading {
    enum FixtureError: Error {
        case missingResponse(URL)
    }

    private let responses: [URL: HTTPDataResponse]
    private(set) var requests: [URLRequest] = []
    private(set) var maximumByteCounts: [Int] = []

    init(responses: [URL: HTTPDataResponse]) {
        self.responses = responses
    }

    func data(
        for request: URLRequest,
        maximumBytes: Int
    ) throws -> HTTPDataResponse {
        requests.append(request)
        maximumByteCounts.append(maximumBytes)

        guard let url = request.url, let response = responses[url] else {
            throw FixtureError.missingResponse(request.url ?? URL(filePath: "/missing-url"))
        }

        guard response.data.count <= maximumBytes else {
            throw HTTPDataLoadingError.responseTooLarge
        }

        return response
    }
}
