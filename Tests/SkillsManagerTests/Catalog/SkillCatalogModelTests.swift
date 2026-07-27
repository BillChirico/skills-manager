import Foundation
import SkillsCore
import Testing

@testable import SkillsManager

@MainActor
struct SkillCatalogModelTests {
    @Test("Searching publishes matching catalog skills")
    func publishesSearchResults() async {
        let skill = fixtureSkill
        let model = SkillCatalogModel(
            catalog: FixtureCatalog(results: [skill]),
            packageFetcher: FixturePackageFetcher(),
            packageInstaller: FixturePackageInstaller()
        )
        model.query = "swift"

        await model.search()

        #expect(model.results == [skill])
        #expect(model.isSearching == false)
        #expect(model.searchErrorMessage == nil)
    }

    @Test("A failed search clears stale results and exposes a readable error")
    func reportsSearchErrors() async {
        let model = SkillCatalogModel(
            catalog: FailingCatalog(),
            packageFetcher: FixturePackageFetcher(),
            packageInstaller: FixturePackageInstaller()
        )
        model.query = "swift"

        await model.search()

        #expect(model.results.isEmpty)
        #expect(model.isSearching == false)
        #expect(model.searchErrorMessage == "Catalog unavailable")
    }

    @Test("Installing publishes progress and returns the created skill directory")
    func installsSelectedSkill() async throws {
        let destination = URL(filePath: "/skills/codex/swift-testing-pro")
        let model = SkillCatalogModel(
            catalog: FixtureCatalog(results: []),
            packageFetcher: FixturePackageFetcher(),
            packageInstaller: FixturePackageInstaller(destination: destination)
        )

        let installedURL = try await model.install(
            fixtureSkill,
            into: URL(filePath: "/skills/codex")
        )

        #expect(installedURL == destination)
        #expect(model.installingSkillID == nil)
    }

    private var fixtureSkill: CatalogSkill {
        CatalogSkill(
            id: "twostraws/swift-testing-agent-skill/swift-testing-pro",
            slug: "swift-testing-pro",
            name: "Swift Testing Pro",
            source: "twostraws/swift-testing-agent-skill",
            installs: 6_900
        )
    }
}

private struct FixtureCatalog: SkillCatalogSearching {
    let results: [CatalogSkill]

    func search(query: String, limit: Int) async throws -> [CatalogSkill] {
        results
    }
}

private struct FailingCatalog: SkillCatalogSearching {
    struct CatalogError: LocalizedError {
        var errorDescription: String? {
            "Catalog unavailable"
        }
    }

    func search(query: String, limit: Int) async throws -> [CatalogSkill] {
        throw CatalogError()
    }
}

private struct FixturePackageFetcher: SkillPackageFetching {
    func fetchPackage(for skill: CatalogSkill) async throws -> SkillPackage {
        SkillPackage(
            skillID: skill.id,
            files: [
                SkillPackageFile(
                    path: "SKILL.md",
                    contents: Data("---\nname: fixture\n---\n".utf8)
                )
            ]
        )
    }
}

private struct FixturePackageInstaller: SkillPackageInstalling {
    let destination: URL

    init(destination: URL = URL(filePath: "/skills/fixture")) {
        self.destination = destination
    }

    func install(
        _ package: SkillPackage,
        directoryName: String,
        into rootDirectory: URL
    ) throws -> URL {
        destination
    }
}
