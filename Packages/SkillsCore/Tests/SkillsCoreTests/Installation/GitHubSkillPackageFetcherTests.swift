import Foundation
import Testing

@testable import SkillsCore

struct GitHubSkillPackageFetcherTests {
    @Test("Fetching a catalog skill returns only files from its matching skill directory")
    func fetchesMatchingSkillDirectory() async throws {
        let treeURL = try #require(
            URL(
                string:
                    "https://api.github.com/repos/twostraws/swift-testing-agent-skill/git/trees/HEAD?recursive=1"
            )
        )
        let manifestURL = try #require(
            URL(
                string:
                    "https://raw.githubusercontent.com/twostraws/swift-testing-agent-skill/HEAD/skills/swift-testing-pro/SKILL.md"
            )
        )
        let referenceURL = try #require(
            URL(
                string:
                    "https://raw.githubusercontent.com/twostraws/swift-testing-agent-skill/HEAD/skills/swift-testing-pro/references/core-rules.md"
            )
        )
        let tree = Data(
            """
            {
              "truncated": false,
              "tree": [
                {
                  "path": "skills/swift-testing-pro/SKILL.md",
                  "mode": "100644",
                  "type": "blob"
                },
                {
                  "path": "skills/swift-testing-pro/references/core-rules.md",
                  "mode": "100644",
                  "type": "blob"
                },
                {
                  "path": "skills/other-skill/SKILL.md",
                  "mode": "100644",
                  "type": "blob"
                }
              ]
            }
            """.utf8
        )
        let loader = FixtureHTTPDataLoader(
            responses: [
                treeURL: HTTPDataResponse(data: tree, statusCode: 200),
                manifestURL: HTTPDataResponse(
                    data: Data("---\nname: swift-testing-pro\n---\n".utf8),
                    statusCode: 200
                ),
                referenceURL: HTTPDataResponse(
                    data: Data("# Core rules\n".utf8),
                    statusCode: 200
                ),
            ]
        )
        let fetcher = GitHubSkillPackageFetcher(dataLoader: loader)
        let skill = CatalogSkill(
            id: "twostraws/swift-testing-agent-skill/swift-testing-pro",
            slug: "swift-testing-pro",
            name: "Swift Testing Pro",
            source: "twostraws/swift-testing-agent-skill",
            installs: 6_900
        )

        let package = try await fetcher.fetchPackage(for: skill)

        #expect(package.skillID == skill.id)
        #expect(package.files.map(\.path) == ["SKILL.md", "references/core-rules.md"])
        #expect(
            String(decoding: package.files[1].contents, as: UTF8.self)
                == "# Core rules\n"
        )
    }

    @Test("A source without a GitHub owner and repository cannot be installed")
    func rejectsNonGitHubSources() async throws {
        let fetcher = GitHubSkillPackageFetcher(
            dataLoader: FixtureHTTPDataLoader(responses: [:])
        )
        let skill = CatalogSkill(
            id: "example.com/custom-skill",
            slug: "custom-skill",
            name: "Custom Skill",
            source: "example.com",
            installs: 12
        )

        await #expect(throws: SkillPackageFetchError.unsupportedSource) {
            try await fetcher.fetchPackage(for: skill)
        }
    }

    @Test("A repository without the selected skill manifest reports a focused error")
    func reportsMissingSkillDirectory() async throws {
        let treeURL = try #require(
            URL(
                string:
                    "https://api.github.com/repos/example/skills/git/trees/HEAD?recursive=1"
            )
        )
        let tree = Data(
            """
            {
              "truncated": false,
              "tree": [
                {
                  "path": "skills/a-different-skill/SKILL.md",
                  "mode": "100644",
                  "type": "blob"
                }
              ]
            }
            """.utf8
        )
        let fetcher = GitHubSkillPackageFetcher(
            dataLoader: FixtureHTTPDataLoader(
                responses: [treeURL: HTTPDataResponse(data: tree, statusCode: 200)]
            )
        )
        let skill = CatalogSkill(
            id: "example/skills/requested-skill",
            slug: "requested-skill",
            name: "Requested Skill",
            source: "example/skills",
            installs: 100
        )

        await #expect(throws: SkillPackageFetchError.skillNotFound) {
            try await fetcher.fetchPackage(for: skill)
        }
    }
}
