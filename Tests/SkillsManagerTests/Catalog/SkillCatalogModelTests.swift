import Foundation
import SkillsCore
import Testing

@testable import SkillsManager

@MainActor
struct SkillCatalogModelTests {
    @Test("Discover opens on the catalog's top downloads instead of an empty screen")
    func loadsTopDownloadsBeforeAnySearch() async {
        let model = SkillCatalogModel(
            catalog: FixtureCatalog(
                topDownloads: [
                    makeSkill(slug: "runner-up", installs: 500),
                    makeSkill(slug: "most-downloaded", installs: 9_000),
                ]
            ),
            packageFetcher: FixturePackageFetcher(),
            packageInstaller: FixturePackageInstaller()
        )

        await model.loadTopDownloads()

        #expect(model.isShowingTopDownloads)
        #expect(model.results.map(\.slug) == ["most-downloaded", "runner-up"])
        #expect(model.isLoading == false)
        #expect(model.errorMessage == nil)
    }

    @Test("Top downloads are fetched once and reused")
    func cachesTopDownloads() async {
        let catalog = FixtureCatalog(topDownloads: [makeSkill(slug: "cached", installs: 1)])
        let model = SkillCatalogModel(
            catalog: catalog,
            packageFetcher: FixturePackageFetcher(),
            packageInstaller: FixturePackageInstaller()
        )

        await model.loadTopDownloads()
        await model.loadTopDownloads()

        #expect(await catalog.topDownloadCallCount == 1)
    }

    @Test("A failed leaderboard load exposes a readable error and can be retried")
    func reportsTopDownloadErrors() async {
        let catalog = FailingCatalog()
        let model = SkillCatalogModel(
            catalog: catalog,
            packageFetcher: FixturePackageFetcher(),
            packageInstaller: FixturePackageInstaller()
        )

        await model.loadTopDownloads()

        #expect(model.results.isEmpty)
        #expect(model.errorMessage == "Catalog unavailable")

        await model.refreshTopDownloads()

        #expect(await catalog.topDownloadCallCount == 2)
    }

    @Test("Searching publishes matching catalog skills ranked by downloads")
    func publishesSearchResultsRankedByDownloads() async {
        let model = SkillCatalogModel(
            catalog: FixtureCatalog(
                searchResults: [
                    makeSkill(slug: "most-relevant", installs: 10),
                    makeSkill(slug: "most-downloaded", installs: 90_000),
                    makeSkill(slug: "middle", installs: 400),
                ]
            ),
            packageFetcher: FixturePackageFetcher(),
            packageInstaller: FixturePackageInstaller()
        )
        model.query = "swift"

        await model.search()

        #expect(model.isShowingTopDownloads == false)
        #expect(model.results.map(\.slug) == ["most-downloaded", "middle", "most-relevant"])
        #expect(model.isLoading == false)
        #expect(model.errorMessage == nil)
    }

    @Test("Clearing the search field falls back to the cached top downloads")
    func fallsBackToTopDownloads() async {
        let model = SkillCatalogModel(
            catalog: FixtureCatalog(
                searchResults: [makeSkill(slug: "match", installs: 5)],
                topDownloads: [makeSkill(slug: "leader", installs: 9_000)]
            ),
            packageFetcher: FixturePackageFetcher(),
            packageInstaller: FixturePackageInstaller()
        )

        await model.loadTopDownloads()
        model.query = "swift"
        await model.search()
        #expect(model.results.map(\.slug) == ["match"])

        model.query = " "
        await model.search()

        #expect(model.results.map(\.slug) == ["leader"])
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

        #expect(model.searchResults.isEmpty)
        #expect(model.isSearching == false)
        #expect(model.searchErrorMessage == "Catalog unavailable")
    }

    @Test("Installing into several directories downloads the package once")
    func installsIntoEverySelectedDirectory() async {
        let fetcher = FixturePackageFetcher()
        let installer = FixturePackageInstaller()
        let model = SkillCatalogModel(
            catalog: FixtureCatalog(),
            packageFetcher: fetcher,
            packageInstaller: installer
        )
        let codex = makeSource(name: "Codex", path: "/skills/codex")
        let claude = makeSource(name: "Claude", path: "/skills/claude")

        let outcomes = await model.install(makeSkill(), into: [codex, claude])

        #expect(outcomes.count == 2)
        #expect(outcomes.filter(\.didSucceed).count == 2)
        #expect(outcomes.map(\.sourceID) == [codex.id, claude.id])
        #expect(
            outcomes.compactMap(\.installedURL).map(\.standardizedFileURL.path) == [
                "/skills/codex/swift-testing-pro",
                "/skills/claude/swift-testing-pro",
            ]
        )
        #expect(await fetcher.fetchCount == 1)
        #expect(model.installingSkillID == nil)
    }

    @Test("One directory's failure does not stop the others")
    func reportsPartialInstallFailures() async {
        let codex = makeSource(name: "Codex", path: "/skills/codex")
        let claude = makeSource(name: "Claude", path: "/skills/claude")
        let model = SkillCatalogModel(
            catalog: FixtureCatalog(),
            packageFetcher: FixturePackageFetcher(),
            packageInstaller: FixturePackageInstaller(failingRootPaths: ["/skills/codex"])
        )

        let outcomes = await model.install(makeSkill(), into: [codex, claude])

        #expect(outcomes.count == 2)
        #expect(outcomes[0].didSucceed == false)
        #expect(outcomes[0].sourceName == "Codex")
        #expect(outcomes[0].errorMessage != nil)
        #expect(outcomes[1].didSucceed)
    }

    @Test("A failed download reports the same error for every selected directory")
    func reportsFetchFailurePerDestination() async {
        let model = SkillCatalogModel(
            catalog: FixtureCatalog(),
            packageFetcher: FailingPackageFetcher(),
            packageInstaller: FixturePackageInstaller()
        )
        let destinations = [
            makeSource(name: "Codex", path: "/skills/codex"),
            makeSource(name: "Claude", path: "/skills/claude"),
        ]

        let outcomes = await model.install(makeSkill(), into: destinations)

        #expect(outcomes.count == 2)
        #expect(outcomes.filter(\.didSucceed).isEmpty)
        #expect(outcomes.compactMap(\.errorMessage) == ["Repository unavailable", "Repository unavailable"])
        #expect(model.installingSkillID == nil)
    }

    @Test("Installing with no selected directory does no work")
    func ignoresEmptyDestinations() async {
        let fetcher = FixturePackageFetcher()
        let model = SkillCatalogModel(
            catalog: FixtureCatalog(),
            packageFetcher: fetcher,
            packageInstaller: FixturePackageInstaller()
        )

        let outcomes = await model.install(makeSkill(), into: [])

        #expect(outcomes.isEmpty)
        #expect(await fetcher.fetchCount == 0)
    }

    private func makeSkill(
        slug: String = "swift-testing-pro",
        installs: Int = 6_900
    ) -> CatalogSkill {
        CatalogSkill(
            id: "twostraws/swift-testing-agent-skill/\(slug)",
            slug: slug,
            name: slug,
            source: "twostraws/swift-testing-agent-skill",
            installs: installs
        )
    }

    private func makeSource(name: String, path: String) -> SkillSource {
        SkillSource(name: name, directoryURL: URL(filePath: path), agent: .codex)
    }
}

private actor FixtureCatalog: SkillCatalogSearching {
    private let searchResults: [CatalogSkill]
    private let topDownloadResults: [CatalogSkill]
    private(set) var topDownloadCallCount = 0

    init(searchResults: [CatalogSkill] = [], topDownloads: [CatalogSkill] = []) {
        self.searchResults = searchResults
        self.topDownloadResults = topDownloads
    }

    func search(query: String, limit: Int) async throws -> [CatalogSkill] {
        searchResults
    }

    func topDownloads(page: Int) async throws -> CatalogPage {
        topDownloadCallCount += 1
        return CatalogPage(skills: topDownloadResults, page: page, hasMore: false)
    }
}

private actor FailingCatalog: SkillCatalogSearching {
    struct CatalogError: LocalizedError {
        var errorDescription: String? {
            "Catalog unavailable"
        }
    }

    private(set) var topDownloadCallCount = 0

    func search(query: String, limit: Int) async throws -> [CatalogSkill] {
        throw CatalogError()
    }

    func topDownloads(page: Int) async throws -> CatalogPage {
        topDownloadCallCount += 1
        throw CatalogError()
    }
}

private actor FixturePackageFetcher: SkillPackageFetching {
    private(set) var fetchCount = 0

    func fetchPackage(for skill: CatalogSkill) async throws -> SkillPackage {
        fetchCount += 1
        return SkillPackage(
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

private struct FailingPackageFetcher: SkillPackageFetching {
    struct FetchError: LocalizedError {
        var errorDescription: String? {
            "Repository unavailable"
        }
    }

    func fetchPackage(for skill: CatalogSkill) async throws -> SkillPackage {
        throw FetchError()
    }
}

private struct FixturePackageInstaller: SkillPackageInstalling {
    struct InstallError: LocalizedError {
        var errorDescription: String? {
            "The directory is not writable."
        }
    }

    let failingRootPaths: Set<String>

    init(failingRootPaths: Set<String> = []) {
        self.failingRootPaths = failingRootPaths
    }

    func install(
        _ package: SkillPackage,
        directoryName: String,
        into rootDirectory: URL
    ) throws -> URL {
        guard failingRootPaths.contains(rootDirectory.path(percentEncoded: false)) == false else {
            throw InstallError()
        }

        return rootDirectory.appending(path: directoryName, directoryHint: .isDirectory)
    }
}
