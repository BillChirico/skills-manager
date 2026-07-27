import Foundation

@testable import SkillsCore

actor FixtureHTTPDataLoader: HTTPDataLoading {
    enum FixtureError: Error {
        case missingResponse(URL)
    }

    private let responses: [URL: HTTPDataResponse]
    private(set) var requests: [URLRequest] = []

    init(responses: [URL: HTTPDataResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) throws -> HTTPDataResponse {
        requests.append(request)

        guard let url = request.url, let response = responses[url] else {
            throw FixtureError.missingResponse(request.url ?? URL(filePath: "/missing-url"))
        }

        return response
    }
}
