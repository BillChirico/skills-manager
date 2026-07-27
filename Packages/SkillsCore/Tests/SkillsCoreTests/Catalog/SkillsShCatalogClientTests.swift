import Foundation
import Testing

@testable import SkillsCore

struct SkillsShCatalogClientTests {
    @Test("Search decodes public skills.sh results and preserves stable identities")
    func decodesSearchResults() async throws {
        let endpoint = try #require(
            URL(string: "https://example.test/api/search?q=swift%20testing&limit=5")
        )
        let payload = Data(
            """
            {
              "query": "swift testing",
              "searchType": "semantic",
              "skills": [
                {
                  "id": "twostraws/swift-testing-agent-skill/swift-testing-pro",
                  "skillId": "swift-testing-pro",
                  "name": "Swift Testing Pro",
                  "installs": 6900,
                  "source": "twostraws/swift-testing-agent-skill"
                }
              ],
              "count": 1,
              "duration_ms": 42
            }
            """.utf8
        )
        let loader = FixtureHTTPDataLoader(
            responses: [endpoint: HTTPDataResponse(data: payload, statusCode: 200)]
        )
        let client = SkillsShCatalogClient(
            baseURL: try #require(URL(string: "https://example.test")),
            dataLoader: loader
        )

        let results = try await client.search(query: "  swift testing  ", limit: 5)

        let result = try #require(results.first)
        #expect(results.count == 1)
        #expect(result.id == "twostraws/swift-testing-agent-skill/swift-testing-pro")
        #expect(result.slug == "swift-testing-pro")
        #expect(result.name == "Swift Testing Pro")
        #expect(result.source == "twostraws/swift-testing-agent-skill")
        #expect(result.installs == 6_900)
        #expect(
            result.pageURL
                == URL(
                    string:
                        "https://skills.sh/twostraws/swift-testing-agent-skill/swift-testing-pro"
                )
        )

        let request = try #require(await loader.requests.first)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("Queries shorter than two characters do not contact skills.sh")
    func ignoresShortQueries() async throws {
        let loader = FixtureHTTPDataLoader(responses: [:])
        let client = SkillsShCatalogClient(
            baseURL: try #require(URL(string: "https://example.test")),
            dataLoader: loader
        )

        let results = try await client.search(query: " s ", limit: 20)

        #expect(results.isEmpty)
        #expect(await loader.requests.isEmpty)
    }

    @Test("A skills.sh outage is reported as a service error")
    func reportsServiceErrors() async throws {
        let endpoint = try #require(URL(string: "https://example.test/api/search?q=swift&limit=20"))
        let loader = FixtureHTTPDataLoader(
            responses: [
                endpoint: HTTPDataResponse(
                    data: Data(#"{"error":"temporarily_unavailable"}"#.utf8),
                    statusCode: 503
                )
            ]
        )
        let client = SkillsShCatalogClient(
            baseURL: try #require(URL(string: "https://example.test")),
            dataLoader: loader
        )

        await #expect(throws: SkillsShCatalogError.serviceUnavailable) {
            try await client.search(query: "swift", limit: 20)
        }
    }
}
