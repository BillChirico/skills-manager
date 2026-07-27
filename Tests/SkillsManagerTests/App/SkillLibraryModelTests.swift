import Foundation
import SkillsCore
import Testing

@testable import SkillsManager

@MainActor
struct SkillLibraryModelTests {
    @Test("Adding a directory persists and selects a new source")
    func addsAndSelectsSource() async throws {
        let store = MemorySourceStore()
        let model = makeModel(sourceStore: store)

        try await model.addSource(at: URL(filePath: "/tmp/team-skills"))

        let source = try #require(model.sources.first)
        let persistedSources = await store.loadSources()
        #expect(model.sources.map(\.displayName) == ["team-skills"])
        #expect(model.sidebarSelection == .source(source.id))
        #expect(persistedSources == model.sources)
    }

    @Test("Adding the same normalized directory does not create a duplicate")
    func deduplicatesSources() async throws {
        let model = makeModel()

        try await model.addSource(at: URL(filePath: "/tmp/team-skills"))
        try await model.addSource(at: URL(filePath: "/tmp/other/../team-skills"))

        #expect(model.sources.count == 1)
    }

    @Test("Smart groups expose consistent counts and filtering")
    func smartGroupCounts() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/skills")
        )
        let skills = [
            AgentSkill(
                name: "Web Research",
                summary: "Search the web.",
                installedVersion: "2.1.0",
                availableVersion: "2.2.0",
                directoryURL: URL(filePath: "/skills/web-research"),
                sourceID: source.id,
                addedAt: now
            ),
            AgentSkill(
                name: "PDF Export",
                summary: "Render PDF files.",
                directoryURL: URL(filePath: "/skills/pdf-export"),
                sourceID: source.id,
                isEnabled: false,
                addedAt: now
            ),
            AgentSkill(
                name: "Code Review",
                summary: "Review changes.",
                directoryURL: URL(filePath: "/skills/code-review"),
                sourceID: source.id,
                addedAt: now.addingTimeInterval(-15 * 24 * 60 * 60)
            ),
        ]
        let model = SkillLibraryModel(sources: [source], skills: skills, now: { now })

        #expect(model.allSkillsCount == 3)
        #expect(model.updatesAvailableCount == 1)
        #expect(model.disabledCount == 1)
        #expect(model.recentlyAddedCount == 2)

        model.sidebarSelection = .updatesAvailable

        #expect(model.visibleSkills.map(\.name) == ["Web Research"])
        #expect(model.searchPrompt == "Search Updates Available")
    }

    @Test("A scoped search can expand to all skills without losing its query")
    func expandsScopedSearch() {
        let selectedSource = SkillSource(
            name: "Selected",
            directoryURL: URL(filePath: "/skills/selected")
        )
        let otherSource = SkillSource(
            name: "Other",
            directoryURL: URL(filePath: "/skills/other")
        )
        let diagram = AgentSkill(
            name: "Diagram",
            summary: "Draw diagrams.",
            directoryURL: URL(filePath: "/skills/other/diagram"),
            sourceID: otherSource.id
        )
        let model = SkillLibraryModel(
            sources: [selectedSource, otherSource],
            skills: [diagram]
        )
        model.sidebarSelection = .source(selectedSource.id)
        model.searchText = "diagram"

        #expect(model.visibleSkills.isEmpty)
        #expect(model.canSearchAllSkills)

        model.searchAllSkills()

        #expect(model.sidebarSelection == .allSkills)
        #expect(model.searchText == "diagram")
        #expect(model.visibleSkills.map(\.name) == ["Diagram"])
    }

    @Test("Restoring sources resolves bookmarks and discovers their skills")
    func restoresAndScansSources() async {
        let persistedSource = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/stale/path"),
            bookmarkData: Data("/skills/team".utf8)
        )
        let model = makeModel(
            sourceStore: MemorySourceStore(sources: [persistedSource]),
            discoverer: FixtureDiscoverer()
        )

        await model.restoreSources()

        #expect(model.sources.first?.directoryURL == URL(filePath: "/skills/team"))
        #expect(model.skills.map(\.name) == ["Discovered Skill"])
        #expect(model.sourceState(for: persistedSource.id) == .available)
    }

    @Test("A scan failure keeps a newly added directory available for recovery")
    func keepsAddedSourceWhenInitialScanFails() async throws {
        let store = MemorySourceStore()
        let model = makeModel(
            sourceStore: store,
            discoverer: FailingDiscoverer()
        )

        try await model.addSource(at: URL(filePath: "/skills/unreadable"))

        let source = try #require(model.sources.first)
        let persistedSources = await store.loadSources()
        #expect(persistedSources == [source])
        #expect(model.sourceState(for: source.id) == .unavailable)
        #expect(model.presentedError?.title == "Unable to Scan unreadable")
    }

    @Test("Rescanning preserves stable selection and local management state")
    func rescanPreservesSelectionAndManagementState() async throws {
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/skills/team")
        )
        let existingSkill = AgentSkill(
            name: "Discovered Skill",
            summary: "Old summary.",
            installedVersion: "1.0.0",
            availableVersion: "2.0.0",
            directoryURL: source.directoryURL.appending(path: "discovered"),
            sourceID: source.id,
            relativePath: "discovered",
            isEnabled: false
        )
        let model = SkillLibraryModel(
            sources: [source],
            skills: [existingSkill],
            discoverer: UpdatedFixtureDiscoverer()
        )
        model.selectedSkillIDs = [existingSkill.id]

        try await model.rescanSource(source.id)

        let rescannedSkill = try #require(model.skills.first)
        #expect(rescannedSkill.id == existingSkill.id)
        #expect(rescannedSkill.summary == "Updated summary.")
        #expect(rescannedSkill.availableVersion == "2.0.0")
        #expect(rescannedSkill.isEnabled == false)
        #expect(model.selectedSkillIDs == [existingSkill.id])
    }

    @Test("An unavailable directory can recover on a later rescan")
    func retriesUnavailableSource() async throws {
        let discoverer = FailOnceDiscoverer()
        let model = makeModel(discoverer: discoverer)

        try await model.addSource(at: URL(filePath: "/skills/retry"))
        let source = try #require(model.sources.first)
        #expect(model.sourceState(for: source.id) == .unavailable)

        try await model.rescanSource(source.id)

        #expect(model.sourceState(for: source.id) == .available)
        #expect(model.skills.map(\.name) == ["Recovered Skill"])
    }

    @Test("Duplicate persisted identities are coalesced during initialization")
    func coalescesDuplicateIdentities() {
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/skills/team")
        )
        let skill = AgentSkill(
            name: "Duplicate",
            summary: "One logical skill.",
            directoryURL: source.directoryURL.appending(path: "duplicate"),
            sourceID: source.id
        )

        let model = SkillLibraryModel(
            sources: [source, source],
            skills: [skill, skill]
        )

        #expect(model.sources == [source])
        #expect(model.skills == [skill])
    }

    @Test("A failed directory removal restores the prior UI state")
    func rollsBackFailedSourceRemoval() async {
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/skills/team")
        )
        let model = SkillLibraryModel(
            sources: [source],
            sourceStore: FailingSaveSourceStore()
        )
        model.sidebarSelection = .source(source.id)

        await #expect(throws: FailingSaveSourceStore.SaveError.self) {
            try await model.removeSource(source.id)
        }

        #expect(model.sources == [source])
        #expect(model.sidebarSelection == .source(source.id))
        #expect(model.sourceState(for: source.id) == .available)
    }

    private func makeModel(
        sourceStore: any SkillSourceStore = MemorySourceStore(),
        discoverer: any SkillDiscovering = EmptyDiscoverer()
    ) -> SkillLibraryModel {
        SkillLibraryModel(
            sourceStore: sourceStore,
            discoverer: discoverer,
            bookmarker: StubBookmarker(),
            sourceAccess: StubSourceAccess()
        )
    }
}

private actor MemorySourceStore: SkillSourceStore {
    private var sources: [SkillSource]

    init(sources: [SkillSource] = []) {
        self.sources = sources
    }

    func loadSources() -> [SkillSource] {
        sources
    }

    func save(_ sources: [SkillSource]) {
        self.sources = sources
    }
}

private actor FailingSaveSourceStore: SkillSourceStore {
    struct SaveError: Error {}

    func loadSources() -> [SkillSource] {
        []
    }

    func save(_ sources: [SkillSource]) throws {
        throw SaveError()
    }
}

private struct EmptyDiscoverer: SkillDiscovering {
    func discoverSkills(in source: SkillSource) async throws -> [AgentSkill] {
        []
    }
}

private struct FixtureDiscoverer: SkillDiscovering {
    func discoverSkills(in source: SkillSource) async throws -> [AgentSkill] {
        [
            AgentSkill(
                name: "Discovered Skill",
                summary: "Loaded from disk.",
                directoryURL: source.directoryURL.appending(path: "discovered"),
                sourceID: source.id
            )
        ]
    }
}

private struct UpdatedFixtureDiscoverer: SkillDiscovering {
    func discoverSkills(in source: SkillSource) async throws -> [AgentSkill] {
        [
            AgentSkill(
                name: "Discovered Skill",
                summary: "Updated summary.",
                installedVersion: "1.1.0",
                directoryURL: source.directoryURL.appending(path: "discovered"),
                sourceID: source.id,
                relativePath: "discovered"
            )
        ]
    }
}

private struct FailingDiscoverer: SkillDiscovering {
    struct ScanError: LocalizedError {
        var errorDescription: String? {
            "The directory could not be scanned."
        }
    }

    func discoverSkills(in source: SkillSource) async throws -> [AgentSkill] {
        throw ScanError()
    }
}

private actor FailOnceDiscoverer: SkillDiscovering {
    private var hasFailed = false

    func discoverSkills(in source: SkillSource) async throws -> [AgentSkill] {
        if hasFailed == false {
            hasFailed = true
            throw FailingDiscoverer.ScanError()
        }

        return [
            AgentSkill(
                name: "Recovered Skill",
                summary: "Loaded on retry.",
                directoryURL: source.directoryURL.appending(path: "recovered"),
                sourceID: source.id
            )
        ]
    }
}

private struct StubBookmarker: SkillSourceBookmarking {
    func makeBookmark(for url: URL) throws -> Data {
        Data(url.path.utf8)
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedSkillSourceBookmark {
        ResolvedSkillSourceBookmark(
            url: URL(filePath: String(decoding: data, as: UTF8.self)),
            isStale: false
        )
    }
}

@MainActor
private final class StubSourceAccess: SkillSourceAccessing {
    func beginAccessing(_ url: URL, for sourceID: SkillSource.ID) -> Bool {
        true
    }

    func stopAccessing(sourceID: SkillSource.ID) {}
}
