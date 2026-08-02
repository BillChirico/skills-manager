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
            skillManager: FixtureSkillManager()
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
            skillManager: FixtureSkillManager()
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
            skillManager: FixtureSkillManager()
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
            skillManager: FixtureSkillManager()
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
            skillManager: FixtureSkillManager()
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
            skillManager: FixtureSkillManager()
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
            skillManager: FixtureSkillManager()
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
            skillManager: FixtureSkillManager()
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

    @Test("Installing into several directories invokes the lifecycle manager for each")
    func installsIntoEverySelectedDirectory() async {
        let skillManager = FixtureSkillManager()
        let model = SkillCatalogModel(
            catalog: FixtureCatalog(),
            skillManager: skillManager
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
        #expect(await skillManager.installedSourceIDs == [codex.id, claude.id])
        #expect(model.installingSkillID == nil)
    }

    @Test("One directory's failure does not stop the others")
    func reportsPartialInstallFailures() async {
        let codex = makeSource(name: "Codex", path: "/skills/codex")
        let claude = makeSource(name: "Claude", path: "/skills/claude")
        let model = SkillCatalogModel(
            catalog: FixtureCatalog(),
            skillManager: FixtureSkillManager(failingRootPaths: ["/skills/codex"])
        )

        let outcomes = await model.install(makeSkill(), into: [codex, claude])

        #expect(outcomes.count == 2)
        #expect(outcomes[0].didSucceed == false)
        #expect(outcomes[0].sourceName == "Codex")
        #expect(outcomes[0].errorMessage != nil)
        #expect(outcomes[1].didSucceed)
    }

    @Test("A CLI failure in every directory reports an outcome for each")
    func reportsLifecycleFailurePerDestination() async {
        let model = SkillCatalogModel(
            catalog: FixtureCatalog(),
            skillManager: FixtureSkillManager(
                failingRootPaths: ["/skills/codex", "/skills/claude"]
            )
        )
        let destinations = [
            makeSource(name: "Codex", path: "/skills/codex"),
            makeSource(name: "Claude", path: "/skills/claude"),
        ]

        let outcomes = await model.install(makeSkill(), into: destinations)

        #expect(outcomes.count == 2)
        #expect(outcomes.filter(\.didSucceed).isEmpty)
        #expect(outcomes.compactMap(\.errorMessage) == ["CLI unavailable", "CLI unavailable"])
        #expect(model.installingSkillID == nil)
    }

    @Test("Installing with no selected directory does no work")
    func ignoresEmptyDestinations() async {
        let skillManager = FixtureSkillManager()
        let model = SkillCatalogModel(
            catalog: FixtureCatalog(),
            skillManager: skillManager
        )

        let outcomes = await model.install(makeSkill(), into: [])

        #expect(outcomes.isEmpty)
        #expect(await skillManager.installedSourceIDs.isEmpty)
    }

    @Test("The install boundary rejects an unsafe catalog entry before launching the CLI")
    func rejectsUnsafeCatalogEntry() async {
        let skillManager = FixtureSkillManager()
        let model = SkillCatalogModel(
            catalog: FixtureCatalog(),
            skillManager: skillManager
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
        #expect(await skillManager.installedSourceIDs.isEmpty)
        #expect(model.installingSkillID == nil)
    }

    @Test("A second install is rejected while the first install owns the busy state")
    func rejectsOverlappingInstalls() async {
        let skillManager = SuspendingSkillManager()
        let model = SkillCatalogModel(
            catalog: FixtureCatalog(),
            skillManager: skillManager
        )
        let skill = makeSkill()
        let destination = makeSource(name: "Codex", path: "/skills/codex")

        let firstInstall = Task {
            await model.install(skill, into: [destination])
        }
        await skillManager.waitUntilStarted()

        let secondOutcomes = await model.install(skill, into: [destination])

        #expect(await skillManager.installCount == 1)
        #expect(model.installingSkillID == skill.id)
        #expect(secondOutcomes.count == 1)
        #expect(secondOutcomes[0].didSucceed == false)
        #expect(
            secondOutcomes[0].errorMessage
                == "Another skill installation is already in progress."
        )

        await skillManager.resume()
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

private actor FixtureSkillManager: SkillManaging {
    struct ManagerError: LocalizedError {
        var errorDescription: String? { "CLI unavailable" }
    }

    private let failingRootPaths: Set<String>
    private(set) var installedSourceIDs: [SkillSource.ID] = []

    init(failingRootPaths: Set<String> = []) {
        self.failingRootPaths = failingRootPaths
    }

    func install(_ skill: CatalogSkill, into source: SkillSource) async throws -> URL {
        installedSourceIDs.append(source.id)
        guard failingRootPaths.contains(source.directoryURL.path(percentEncoded: false)) == false
        else {
            throw ManagerError()
        }

        return source.directoryURL.appending(path: skill.slug, directoryHint: .isDirectory)
    }

    func update(_ skill: AgentSkill, in source: SkillSource) async throws {}

    func remove(_ skill: AgentSkill, from source: SkillSource) async throws {}
}

private actor SuspendingSkillManager: SkillManaging {
    private var continuation: CheckedContinuation<URL, Never>?
    private var installedURL: URL?
    private(set) var installCount = 0

    func install(_ skill: CatalogSkill, into source: SkillSource) async throws -> URL {
        installCount += 1
        installedURL = source.directoryURL.appending(
            path: skill.slug,
            directoryHint: .isDirectory
        )
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
        guard let installedURL else {
            return
        }

        continuation?.resume(returning: installedURL)
        continuation = nil
        self.installedURL = nil
    }

    func update(_ skill: AgentSkill, in source: SkillSource) async throws {}

    func remove(_ skill: AgentSkill, from source: SkillSource) async throws {}
}
