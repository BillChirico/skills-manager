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

    @Test("The top downloads page composes identifiers the leaderboard omits")
    func decodesTopDownloads() async throws {
        let endpoint = try #require(URL(string: "https://example.test/api/skills/all-time/0"))
        let payload = Data(
            """
            {
              "skills": [
                {
                  "source": "vercel-labs/skills",
                  "skillId": "find-skills",
                  "name": "find-skills",
                  "installs": 2701028,
                  "weeklyInstalls": [112706, 118887],
                  "isOfficial": true
                },
                {
                  "source": "anthropics/skills",
                  "skillId": "frontend-design",
                  "installs": 710531
                }
              ],
              "page": 0,
              "total": 5000,
              "hasMore": true
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

        let page = try await client.topDownloads(page: 0)

        #expect(page.page == 0)
        #expect(page.hasMore)
        #expect(page.skills.count == 2)

        let first = try #require(page.skills.first)
        #expect(first.id == "vercel-labs/skills/find-skills")
        #expect(first.slug == "find-skills")
        #expect(first.installs == 2_701_028)
        #expect(first.isInstallable)

        // The leaderboard may omit `name`; the slug is the readable fallback.
        let second = try #require(page.skills.last)
        #expect(second.name == "frontend-design")
        #expect(second.id == "anthropics/skills/frontend-design")
    }

    @Test("A leaderboard entry without a source or slug is dropped")
    func dropsIncompleteLeaderboardEntries() async throws {
        let endpoint = try #require(URL(string: "https://example.test/api/skills/all-time/0"))
        let payload = Data(
            """
            {
              "skills": [
                { "source": "  ", "skillId": "orphan", "installs": 10 },
                { "source": "owner/repo", "skillId": "", "installs": 10 },
                { "source": "owner/repo", "skillId": "kept", "installs": -5 }
              ],
              "hasMore": false
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

        let page = try await client.topDownloads(page: 0)

        #expect(page.skills.map(\.slug) == ["kept"])
        #expect(page.skills.first?.installs == 0)
    }

    @Test("A negative page index never reaches the network")
    func rejectsNegativePages() async throws {
        let loader = FixtureHTTPDataLoader(responses: [:])
        let client = SkillsShCatalogClient(
            baseURL: try #require(URL(string: "https://example.test")),
            dataLoader: loader
        )

        await #expect(throws: SkillsShCatalogError.invalidEndpoint) {
            try await client.topDownloads(page: -1)
        }
        #expect(await loader.requests.isEmpty)
    }

    @Test("A leaderboard outage is reported as a service error")
    func reportsTopDownloadErrors() async throws {
        let endpoint = try #require(URL(string: "https://example.test/api/skills/all-time/0"))
        let loader = FixtureHTTPDataLoader(
            responses: [
                endpoint: HTTPDataResponse(data: Data("{}".utf8), statusCode: 429)
            ]
        )
        let client = SkillsShCatalogClient(
            baseURL: try #require(URL(string: "https://example.test")),
            dataLoader: loader
        )

        await #expect(throws: SkillsShCatalogError.rateLimited) {
            try await client.topDownloads(page: 0)
        }
    }

    @Test("A response larger than the read ceiling is refused before decoding")
    func refusesOversizedResponses() async throws {
        let endpoint = try #require(URL(string: "https://example.test/api/skills/all-time/0"))
        let loader = FixtureHTTPDataLoader(
            responses: [
                endpoint: HTTPDataResponse(
                    data: Data(count: 9 * 1_024 * 1_024),
                    statusCode: 200
                )
            ]
        )
        let client = SkillsShCatalogClient(
            baseURL: try #require(URL(string: "https://example.test")),
            dataLoader: loader
        )

        await #expect(throws: SkillsShCatalogError.responseTooLarge) {
            try await client.topDownloads(page: 0)
        }
        #expect(await loader.maximumByteCounts == [8 * 1_024 * 1_024])
    }
}
