import Foundation
import Testing

@testable import SkillsCore

struct GitHubSkillPackageFetcherTests {
    private static let commitSHA = "0123456789abcdef0123456789abcdef01234567"

    @Test("Fetching a catalog skill returns only files from its matching skill directory")
    func fetchesMatchingSkillDirectory() async throws {
        let commitURL = try #require(
            URL(
                string:
                    "https://api.github.com/repos/twostraws/swift-testing-agent-skill/commits/HEAD"
            )
        )
        let treeURL = try #require(
            URL(
                string:
                    "https://api.github.com/repos/twostraws/swift-testing-agent-skill/git/trees/\(Self.commitSHA)?recursive=1"
            )
        )
        let manifestURL = try #require(
            URL(
                string:
                    "https://raw.githubusercontent.com/twostraws/swift-testing-agent-skill/\(Self.commitSHA)/skills/swift-testing-pro/SKILL.md"
            )
        )
        let referenceURL = try #require(
            URL(
                string:
                    "https://raw.githubusercontent.com/twostraws/swift-testing-agent-skill/\(Self.commitSHA)/skills/swift-testing-pro/references/core-rules.md"
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
                commitURL: commitResponse(),
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
        let commitRequest = try #require(await loader.requests.first)
        #expect(
            commitRequest.value(forHTTPHeaderField: "Accept")
                == "application/vnd.github.sha"
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
        let commitURL = try #require(
            URL(string: "https://api.github.com/repos/example/skills/commits/HEAD")
        )
        let treeURL = try #require(
            URL(
                string:
                    "https://api.github.com/repos/example/skills/git/trees/\(Self.commitSHA)?recursive=1"
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
                responses: [
                    commitURL: commitResponse(),
                    treeURL: HTTPDataResponse(data: tree, statusCode: 200),
                ]
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

    @Test("A mismatched root manifest is not used as a slug fallback")
    func rejectsMismatchedRootManifest() async throws {
        let commitURL = try #require(
            URL(string: "https://api.github.com/repos/example/skills/commits/HEAD")
        )
        let treeURL = try #require(
            URL(
                string:
                    "https://api.github.com/repos/example/skills/git/trees/\(Self.commitSHA)?recursive=1"
            )
        )
        let tree = Data(
            """
            {
              "truncated": false,
              "tree": [
                {
                  "path": "SKILL.md",
                  "mode": "100644",
                  "type": "blob"
                }
              ]
            }
            """.utf8
        )
        let loader = FixtureHTTPDataLoader(
            responses: [
                commitURL: commitResponse(),
                treeURL: HTTPDataResponse(data: tree, statusCode: 200),
            ]
        )
        let fetcher = GitHubSkillPackageFetcher(dataLoader: loader)
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
        #expect(await loader.requests.count == 2)
    }

    @Test("A sole root manifest is accepted when the repository identity matches the slug")
    func acceptsVerifiedSingleSkillRepository() async throws {
        let commitURL = try #require(
            URL(string: "https://api.github.com/repos/example/root-skill/commits/HEAD")
        )
        let treeURL = try #require(
            URL(
                string:
                    "https://api.github.com/repos/example/root-skill/git/trees/\(Self.commitSHA)?recursive=1"
            )
        )
        let manifestURL = try #require(
            URL(
                string:
                    "https://raw.githubusercontent.com/example/root-skill/\(Self.commitSHA)/SKILL.md"
            )
        )
        let tree = Data(
            """
            {
              "truncated": false,
              "tree": [
                { "path": "SKILL.md", "mode": "100644", "type": "blob" }
              ]
            }
            """.utf8
        )
        let loader = FixtureHTTPDataLoader(
            responses: [
                commitURL: commitResponse(),
                treeURL: HTTPDataResponse(data: tree, statusCode: 200),
                manifestURL: HTTPDataResponse(
                    data: Data("---\nname: root-skill\n---\n".utf8),
                    statusCode: 200
                ),
            ]
        )
        let fetcher = GitHubSkillPackageFetcher(dataLoader: loader)
        let skill = CatalogSkill(
            id: "example/root-skill/root-skill",
            slug: "root-skill",
            name: "Root Skill",
            source: "example/root-skill",
            installs: 100
        )

        let package = try await fetcher.fetchPackage(for: skill)

        #expect(package.files.map(\.path) == ["SKILL.md"])
    }

    @Test("Tree enumeration and raw files use the commit resolved from HEAD")
    func pinsAllPackageRequestsToResolvedCommit() async throws {
        let commitURL = try #require(
            URL(string: "https://api.github.com/repos/example/skills/commits/HEAD")
        )
        let treeURL = try #require(
            URL(
                string:
                    "https://api.github.com/repos/example/skills/git/trees/\(Self.commitSHA)?recursive=1"
            )
        )
        let manifestURL = try #require(
            URL(
                string:
                    "https://raw.githubusercontent.com/example/skills/\(Self.commitSHA)/skills/pinned/SKILL.md"
            )
        )
        let tree = Data(
            """
            {
              "truncated": false,
              "tree": [
                {
                  "path": "skills/pinned/SKILL.md",
                  "mode": "100644",
                  "type": "blob"
                }
              ]
            }
            """.utf8
        )
        let loader = FixtureHTTPDataLoader(
            responses: [
                commitURL: commitResponse(),
                treeURL: HTTPDataResponse(data: tree, statusCode: 200),
                manifestURL: HTTPDataResponse(
                    data: Data("---\nname: pinned\n---\n".utf8),
                    statusCode: 200
                ),
            ]
        )
        let fetcher = GitHubSkillPackageFetcher(dataLoader: loader)
        let skill = CatalogSkill(
            id: "example/skills/pinned",
            slug: "pinned",
            name: "Pinned",
            source: "example/skills",
            installs: 1
        )

        _ = try await fetcher.fetchPackage(for: skill)

        let requestURLs = await loader.requests.compactMap(\.url)
        #expect(requestURLs == [commitURL, treeURL, manifestURL])
        #expect(
            requestURLs.dropFirst().allSatisfy {
                $0.absoluteString.contains(Self.commitSHA)
            }
        )
    }

    @Test("A raw file receives only the aggregate package budget that remains")
    func enforcesRemainingPackageBudgetWhileLoading() async throws {
        let commitURL = try #require(
            URL(string: "https://api.github.com/repos/example/skills/commits/HEAD")
        )
        let treeURL = try #require(
            URL(
                string:
                    "https://api.github.com/repos/example/skills/git/trees/\(Self.commitSHA)?recursive=1"
            )
        )
        let manifestURL = try #require(
            URL(
                string:
                    "https://raw.githubusercontent.com/example/skills/\(Self.commitSHA)/skills/large/SKILL.md"
            )
        )
        let referenceURL = try #require(
            URL(
                string:
                    "https://raw.githubusercontent.com/example/skills/\(Self.commitSHA)/skills/large/reference.md"
            )
        )
        let tree = Data(
            """
            {
              "truncated": false,
              "tree": [
                { "path": "skills/large/SKILL.md", "mode": "100644", "type": "blob" },
                { "path": "skills/large/reference.md", "mode": "100644", "type": "blob" }
              ]
            }
            """.utf8
        )
        let packageLimit = 10 * 1_024 * 1_024
        let loader = FixtureHTTPDataLoader(
            responses: [
                commitURL: commitResponse(),
                treeURL: HTTPDataResponse(data: tree, statusCode: 200),
                manifestURL: HTTPDataResponse(
                    data: Data(count: packageLimit - 2),
                    statusCode: 200
                ),
                referenceURL: HTTPDataResponse(data: Data(count: 3), statusCode: 200),
            ]
        )
        let fetcher = GitHubSkillPackageFetcher(dataLoader: loader)
        let skill = CatalogSkill(
            id: "example/skills/large",
            slug: "large",
            name: "Large",
            source: "example/skills",
            installs: 1
        )

        await #expect(throws: SkillPackageFetchError.packageTooLarge) {
            try await fetcher.fetchPackage(for: skill)
        }

        #expect(
            await loader.maximumByteCounts
                == [1_024, 8 * 1_024 * 1_024, packageLimit, 2]
        )
    }

    @Test("An oversized recursive tree is refused by its streaming ceiling")
    func rejectsOversizedTreeResponse() async throws {
        let commitURL = try #require(
            URL(string: "https://api.github.com/repos/example/skills/commits/HEAD")
        )
        let treeURL = try #require(
            URL(
                string:
                    "https://api.github.com/repos/example/skills/git/trees/\(Self.commitSHA)?recursive=1"
            )
        )
        let loader = FixtureHTTPDataLoader(
            responses: [
                commitURL: commitResponse(),
                treeURL: HTTPDataResponse(
                    data: Data(count: 8 * 1_024 * 1_024 + 1),
                    statusCode: 200
                ),
            ]
        )
        let fetcher = GitHubSkillPackageFetcher(dataLoader: loader)
        let skill = CatalogSkill(
            id: "example/skills/large",
            slug: "large",
            name: "Large",
            source: "example/skills",
            installs: 1
        )

        await #expect(throws: SkillPackageFetchError.packageTooLarge) {
            try await fetcher.fetchPackage(for: skill)
        }
        #expect(await loader.maximumByteCounts == [1_024, 8 * 1_024 * 1_024])
    }

    @Test("A source that walks out of its repository path is not fetched")
    func rejectsTraversalSources() async throws {
        let fetcher = GitHubSkillPackageFetcher(
            dataLoader: FixtureHTTPDataLoader(responses: [:])
        )
        let skill = CatalogSkill(
            id: "../../evil",
            slug: "evil",
            name: "Evil",
            source: "../evil",
            installs: 1
        )

        await #expect(throws: SkillPackageFetchError.unsupportedSource) {
            try await fetcher.fetchPackage(for: skill)
        }
    }

    @Test("A tree entry with a relative path segment is never downloaded")
    func skipsUnsafeTreePaths() async throws {
        let commitURL = try #require(
            URL(string: "https://api.github.com/repos/example/skills/commits/HEAD")
        )
        let treeURL = try #require(
            URL(
                string:
                    "https://api.github.com/repos/example/skills/git/trees/\(Self.commitSHA)?recursive=1"
            )
        )
        let manifestURL = try #require(
            URL(
                string:
                    "https://raw.githubusercontent.com/example/skills/\(Self.commitSHA)/skills/safe-skill/SKILL.md"
            )
        )
        let tree = Data(
            """
            {
              "truncated": false,
              "tree": [
                {
                  "path": "skills/safe-skill/SKILL.md",
                  "mode": "100644",
                  "type": "blob"
                },
                {
                  "path": "skills/safe-skill/../../../../etc/passwd",
                  "mode": "100644",
                  "type": "blob"
                }
              ]
            }
            """.utf8
        )
        let loader = FixtureHTTPDataLoader(
            responses: [
                commitURL: commitResponse(),
                treeURL: HTTPDataResponse(data: tree, statusCode: 200),
                manifestURL: HTTPDataResponse(
                    data: Data("---\nname: safe-skill\n---\n".utf8),
                    statusCode: 200
                ),
            ]
        )
        let fetcher = GitHubSkillPackageFetcher(dataLoader: loader)
        let skill = CatalogSkill(
            id: "example/skills/safe-skill",
            slug: "safe-skill",
            name: "Safe Skill",
            source: "example/skills",
            installs: 3
        )

        let package = try await fetcher.fetchPackage(for: skill)

        #expect(package.files.map(\.path) == ["SKILL.md"])
        #expect(await loader.requests.count == 3)
    }

    private func commitResponse() -> HTTPDataResponse {
        HTTPDataResponse(
            data: Data(Self.commitSHA.utf8),
            statusCode: 200
        )
    }
}
