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

    @Test("A reopened Discover view joins a leaderboard request whose first caller cancelled")
    func reopenedDiscoverJoinsCancelledCallersRequest() async {
        let catalog = SuspendingTopDownloadsCatalog(
            page: CatalogPage(
                skills: [makeSkill(slug: "leader", installs: 9_000)],
                page: 0,
                hasMore: false
            )
        )
        let model = SkillCatalogModel(
            catalog: catalog,
            packageFetcher: FixturePackageFetcher(),
            packageInstaller: FixturePackageInstaller()
        )

        let firstLoad = Task { await model.loadTopDownloads() }
        await catalog.waitUntilRequested()
        firstLoad.cancel()
        let reopenedLoad = Task { await model.loadTopDownloads() }
        await Task.yield()

        #expect(await catalog.topDownloadCallCount == 1)

        await catalog.resumeFirstRequest()
        await firstLoad.value
        await reopenedLoad.value

        #expect(await catalog.topDownloadCallCount == 1)
        #expect(model.topDownloads.map(\.slug) == ["leader"])
        #expect(model.isLoadingTopDownloads == false)
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

    @Test("Only the newest overlapping search can publish state")
    func newestOverlappingSearchOwnsState() async {
        let catalog = ControlledSearchCatalog()
        let model = SkillCatalogModel(
            catalog: catalog,
            packageFetcher: FixturePackageFetcher(),
            packageInstaller: FixturePackageInstaller()
        )

        model.query = "first"
        let firstSearch = Task { await model.search() }
        await catalog.waitForSearch(query: "first")

        model.query = "second"
        let secondSearch = Task { await model.search() }
        await catalog.waitForSearch(query: "second")

        await catalog.resolve(
            query: "first",
            with: [makeSkill(slug: "stale", installs: 100)]
        )
        await firstSearch.value

        #expect(model.isSearching)
        #expect(model.searchResults.isEmpty)

        await catalog.resolve(
            query: "second",
            with: [makeSkill(slug: "current", installs: 200)]
        )
        await secondSearch.value

        #expect(model.searchResults.map(\.slug) == ["current"])
        #expect(model.isSearching == false)
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

    @Test("The install boundary rejects an unsafe catalog entry before downloading")
    func rejectsUnsafeCatalogEntry() async {
        let fetcher = FixturePackageFetcher()
        let model = SkillCatalogModel(
            catalog: FixtureCatalog(),
            packageFetcher: fetcher,
            packageInstaller: FixturePackageInstaller()
        )
        let destination = makeSource(name: "Codex", path: "/skills/codex")

        let outcomes = await model.install(
            makeSkill(slug: ".hidden"),
            into: [destination]
        )

        #expect(outcomes.count == 1)
        #expect(outcomes[0].didSucceed == false)
        #expect(
            outcomes[0].errorMessage
                == "This skill's catalog data cannot be installed safely."
        )
        #expect(await fetcher.fetchCount == 0)
        #expect(model.installingSkillID == nil)
    }

    @Test("A second install is rejected while the first install owns the busy state")
    func rejectsOverlappingInstalls() async {
        let fetcher = SuspendingPackageFetcher()
        let model = SkillCatalogModel(
            catalog: FixtureCatalog(),
            packageFetcher: fetcher,
            packageInstaller: FixturePackageInstaller()
        )
        let skill = makeSkill()
        let destination = makeSource(name: "Codex", path: "/skills/codex")

        let firstInstall = Task {
            await model.install(skill, into: [destination])
        }
        await fetcher.waitUntilStarted()

        let secondOutcomes = await model.install(skill, into: [destination])

        #expect(await fetcher.fetchCount == 1)
        #expect(model.installingSkillID == skill.id)
        #expect(secondOutcomes.count == 1)
        #expect(secondOutcomes[0].didSucceed == false)
        #expect(
            secondOutcomes[0].errorMessage
                == "Another skill installation is already in progress."
        )

        await fetcher.resume()
        let firstOutcomes = await firstInstall.value

        #expect(firstOutcomes.count == 1)
        #expect(firstOutcomes[0].didSucceed)
        #expect(model.installingSkillID == nil)
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

private actor ControlledSearchCatalog: SkillCatalogSearching {
    private var continuations: [String: CheckedContinuation<[CatalogSkill], any Error>] = [:]

    func search(query: String, limit: Int) async throws -> [CatalogSkill] {
        try await withCheckedThrowingContinuation { continuation in
            continuations[query] = continuation
        }
    }

    func topDownloads(page: Int) async throws -> CatalogPage {
        CatalogPage(skills: [], page: page, hasMore: false)
    }

    func waitForSearch(query: String) async {
        while continuations[query] == nil {
            await Task.yield()
        }
    }

    func resolve(query: String, with skills: [CatalogSkill]) {
        continuations.removeValue(forKey: query)?.resume(returning: skills)
    }
}

private actor SuspendingTopDownloadsCatalog: SkillCatalogSearching {
    private let page: CatalogPage
    private var firstContinuation: CheckedContinuation<CatalogPage, Never>?
    private(set) var topDownloadCallCount = 0

    init(page: CatalogPage) {
        self.page = page
    }

    func search(query: String, limit: Int) async throws -> [CatalogSkill] {
        []
    }

    func topDownloads(page: Int) async throws -> CatalogPage {
        topDownloadCallCount += 1
        guard topDownloadCallCount == 1 else {
            return self.page
        }

        return await withCheckedContinuation { continuation in
            firstContinuation = continuation
        }
    }

    func waitUntilRequested() async {
        while firstContinuation == nil {
            await Task.yield()
        }
    }

    func resumeFirstRequest() {
        firstContinuation?.resume(returning: page)
        firstContinuation = nil
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

private actor SuspendingPackageFetcher: SkillPackageFetching {
    private var continuation: CheckedContinuation<SkillPackage, Never>?
    private(set) var fetchCount = 0

    func fetchPackage(for skill: CatalogSkill) async throws -> SkillPackage {
        fetchCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume(
            returning: SkillPackage(
                skillID: "fixture",
                files: [
                    SkillPackageFile(
                        path: "SKILL.md",
                        contents: Data("---\nname: fixture\n---\n".utf8)
                    )
                ]
            )
        )
        continuation = nil
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
