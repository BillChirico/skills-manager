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

    @Test(
        "Adding a selected directory opens its security scope before bookmarking",
        .bug(id: 8)
    )
    func opensSecurityScopeBeforeBookmarking() async throws {
        let accessState = ScopedDirectoryAccessState()
        let sourceAccess = AccessTrackingSourceAccess(state: accessState)
        let bookmarker = AccessRequiringBookmarker(state: accessState)
        let store = MemorySourceStore()
        let model = SkillLibraryModel(
            sourceStore: store,
            discoverer: EmptyDiscoverer(),
            bookmarker: bookmarker,
            sourceAccess: sourceAccess
        )
        let directoryURL = URL(filePath: "/skills/codex", directoryHint: .isDirectory)

        try await model.addSource(at: directoryURL, agent: .codex)

        let source = try #require(model.sources.first)
        #expect(source.bookmarkData == Data(directoryURL.path.utf8))
        #expect(model.sourceState(for: source.id) == .available)
        #expect(accessState.isAccessing(directoryURL))
        #expect(await store.loadSources() == [source])
    }

    @Test("A bookmark failure releases access and does not add the directory")
    func bookmarkFailureRollsBackAccess() async {
        let accessState = ScopedDirectoryAccessState()
        let model = SkillLibraryModel(
            sourceStore: MemorySourceStore(),
            bookmarker: AccessRequiringBookmarker(
                state: accessState,
                failure: .intentionalFailure
            ),
            sourceAccess: AccessTrackingSourceAccess(state: accessState)
        )
        let directoryURL = URL(filePath: "/skills/failing", directoryHint: .isDirectory)

        await #expect(
            throws: AccessRequiringBookmarker.BookmarkError.intentionalFailure
        ) {
            try await model.addSource(at: directoryURL)
        }

        #expect(model.sources.isEmpty)
        #expect(accessState.isAccessing(directoryURL) == false)
    }

    @Test("Relocating opens the replacement security scope before bookmarking")
    func opensReplacementScopeBeforeBookmarking() async throws {
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/skills/old", directoryHint: .isDirectory)
        )
        let accessState = ScopedDirectoryAccessState()
        let model = SkillLibraryModel(
            sources: [source],
            sourceStore: MemorySourceStore(sources: [source]),
            bookmarker: AccessRequiringBookmarker(state: accessState),
            sourceAccess: AccessTrackingSourceAccess(state: accessState)
        )
        let replacementURL = URL(
            filePath: "/skills/replacement",
            directoryHint: .isDirectory
        )

        try await model.relocateSource(source.id, to: replacementURL)

        let relocatedSource = try #require(model.sources.first)
        #expect(relocatedSource.directoryURL == replacementURL)
        #expect(relocatedSource.bookmarkData == Data(replacementURL.path.utf8))
        #expect(accessState.isAccessing(replacementURL))
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

    @Test(
        "Relocating an unavailable directory preserves source and skill identity",
        arguments: SourceRestoreFailure.allCases
    )
    func relocatingUnavailableSourceRecoversInPlace(
        after restoreFailure: SourceRestoreFailure
    ) async throws {
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/skills/old-team"),
            bookmarkData: Data("expired-bookmark".utf8)
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
        let store = MemorySourceStore(sources: [source])
        let sourceAccess: RecordingSourceAccess
        let bookmarker: any SkillSourceBookmarking

        switch restoreFailure {
        case .bookmarkResolution:
            sourceAccess = RecordingSourceAccess()
            bookmarker = FailingResolveBookmarker()
        case .securityScopeAccess:
            sourceAccess = RecordingSourceAccess(accessResults: [false, true])
            bookmarker = RecoveryBookmarker(resolvedURL: source.directoryURL)
        }

        let model = SkillLibraryModel(
            sources: [source],
            skills: [existingSkill],
            sourceStore: store,
            discoverer: UpdatedFixtureDiscoverer(),
            bookmarker: bookmarker,
            sourceAccess: sourceAccess
        )
        model.sidebarSelection = .source(source.id)
        model.selectedSkillIDs = [existingSkill.id]

        await model.restoreSources()

        #expect(model.sourceState(for: source.id) == .unavailable)

        let relocatedURL = URL(filePath: "/skills/relocated/team")
        try await model.relocateSource(source.id, to: relocatedURL)

        let relocatedSource = try #require(model.sources.first)
        let relocatedSkill = try #require(model.skills.first)
        let persistedSources = await store.loadSources()
        #expect(model.sources.count == 1)
        #expect(relocatedSource.id == source.id)
        #expect(relocatedSource.name == source.name)
        #expect(relocatedSource.directoryURL == relocatedURL)
        #expect(relocatedSource.bookmarkData == Data("/skills/relocated/team".utf8))
        #expect(sourceAccess.activeURL(for: source.id) == relocatedURL)
        #expect(persistedSources == [relocatedSource])
        #expect(model.sourceState(for: source.id) == .available)
        #expect(relocatedSkill.id == existingSkill.id)
        #expect(relocatedSkill.directoryURL == relocatedURL.appending(path: "discovered"))
        #expect(relocatedSkill.summary == "Updated summary.")
        #expect(relocatedSkill.availableVersion == "2.0.0")
        #expect(relocatedSkill.isEnabled == false)
        #expect(model.selectedSkillIDs == [existingSkill.id])
    }

    @Test("Denied directory recovery leaves the source and its skills unchanged")
    func deniedSourceRecoveryIsNonDestructive() async throws {
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/skills/team"),
            bookmarkData: Data("expired-bookmark".utf8)
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
        let store = MemorySourceStore(sources: [source])
        let sourceAccess = RecordingSourceAccess(accessResults: [false, false])
        let model = SkillLibraryModel(
            sources: [source],
            skills: [existingSkill],
            sourceStore: store,
            discoverer: UpdatedFixtureDiscoverer(),
            bookmarker: RecoveryBookmarker(resolvedURL: source.directoryURL),
            sourceAccess: sourceAccess
        )

        await model.restoreSources()

        await #expect(throws: SkillLibraryModel.SourceAccessError.accessDenied) {
            try await model.relocateSource(
                source.id,
                to: URL(filePath: "/skills/relocated/team")
            )
        }

        #expect(model.sources == [source])
        #expect(model.skills == [existingSkill])
        #expect(await store.loadSources() == [source])
        #expect(model.sourceState(for: source.id) == .unavailable)
        #expect(sourceAccess.activeURL(for: source.id) == nil)
    }

    @Test("Re-adding an unavailable directory recovers it without changing identity")
    func readdingUnavailableSourceRecoversInPlace() async throws {
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/skills/team"),
            bookmarkData: Data("expired-bookmark".utf8)
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
        let store = MemorySourceStore(sources: [source])
        let sourceAccess = RecordingSourceAccess(accessResults: [false, true])
        let model = SkillLibraryModel(
            sources: [source],
            skills: [existingSkill],
            sourceStore: store,
            discoverer: UpdatedFixtureDiscoverer(),
            bookmarker: RecoveryBookmarker(resolvedURL: source.directoryURL),
            sourceAccess: sourceAccess
        )
        model.sidebarSelection = .source(source.id)
        model.selectedSkillIDs = [existingSkill.id]

        await model.restoreSources()

        #expect(model.sourceState(for: source.id) == .unavailable)

        try await model.addSource(at: URL(filePath: "/skills/other/../team"))

        let recoveredSource = try #require(model.sources.first)
        let recoveredSkill = try #require(model.skills.first)
        let persistedSources = await store.loadSources()
        #expect(model.sources.count == 1)
        #expect(recoveredSource.id == source.id)
        #expect(recoveredSource.bookmarkData == Data("/skills/team".utf8))
        #expect(sourceAccess.activeURL(for: source.id) == source.directoryURL)
        #expect(persistedSources == [recoveredSource])
        #expect(model.sourceState(for: source.id) == .available)
        #expect(recoveredSkill.id == existingSkill.id)
        #expect(recoveredSkill.summary == "Updated summary.")
        #expect(recoveredSkill.availableVersion == "2.0.0")
        #expect(recoveredSkill.isEnabled == false)
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

    @Test("A failed pause restores the folder it targeted")
    func rollsBackFailedPause() async throws {
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/skills/team")
        )
        let model = SkillLibraryModel(
            sources: [source],
            sourceStore: FailingSaveSourceStore()
        )

        await #expect(throws: FailingSaveSourceStore.SaveError.self) {
            try await model.setSourceEnabled(false, sourceID: source.id)
        }

        #expect(model.sources.first?.isEnabled == true)
    }

    @Test("A failed pause rolls back after the folder list is reordered")
    func rollsBackFailedPauseAfterConcurrentRemoval() async throws {
        let firstSource = SkillSource(
            name: "Alpha Skills",
            directoryURL: URL(filePath: "/skills/alpha")
        )
        let pausedSource = SkillSource(
            name: "Beta Skills",
            directoryURL: URL(filePath: "/skills/beta")
        )
        let store = InterruptingSourceStore(sources: [firstSource, pausedSource])
        let model = SkillLibraryModel(
            sources: [firstSource, pausedSource],
            sourceStore: store,
            bookmarker: StubBookmarker(),
            sourceAccess: StubSourceAccess()
        )

        #expect(model.sources.map(\.displayName) == ["Alpha Skills", "Beta Skills"])

        // The removal lands while the pause is suspended on its failing save, so
        // the index the pause captured no longer addresses the folder it targeted.
        await store.interruptFirstSave {
            try await model.removeSource(firstSource.id)
        }

        await #expect(throws: InterruptingSourceStore.SaveError.self) {
            try await model.setSourceEnabled(false, sourceID: pausedSource.id)
        }

        #expect(model.sources.map(\.id) == [pausedSource.id])
        #expect(model.sources.first?.isEnabled == true)
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

enum SourceRestoreFailure: CaseIterable, Sendable {
    case bookmarkResolution
    case securityScopeAccess
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

/// Runs one interruption inside the next `save`, then fails that save. Later
/// saves succeed, so the interruption can mutate the library while the
/// interrupted caller is still suspended.
private actor InterruptingSourceStore: SkillSourceStore {
    struct SaveError: Error {}

    private var sources: [SkillSource]
    private var interruption: (@MainActor @Sendable () async throws -> Void)?

    init(sources: [SkillSource] = []) {
        self.sources = sources
    }

    func interruptFirstSave(
        with interruption: @escaping @MainActor @Sendable () async throws -> Void
    ) {
        self.interruption = interruption
    }

    func loadSources() -> [SkillSource] {
        sources
    }

    func save(_ sources: [SkillSource]) async throws {
        guard let interruption else {
            self.sources = sources
            return
        }

        self.interruption = nil
        try await interruption()
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

@MainActor
private final class RecordingSourceAccess: SkillSourceAccessing {
    private var accessResults: [Bool]
    private var activeURLs: [SkillSource.ID: URL] = [:]

    init(accessResults: [Bool] = []) {
        self.accessResults = accessResults
    }

    func beginAccessing(_ url: URL, for sourceID: SkillSource.ID) -> Bool {
        activeURLs[sourceID] = nil
        let accessGranted = accessResults.isEmpty ? true : accessResults.removeFirst()

        guard accessGranted else {
            return false
        }

        activeURLs[sourceID] = url
        return true
    }

    func stopAccessing(sourceID: SkillSource.ID) {
        activeURLs[sourceID] = nil
    }

    func activeURL(for sourceID: SkillSource.ID) -> URL? {
        activeURLs[sourceID]
    }
}

private struct FailingResolveBookmarker: SkillSourceBookmarking {
    struct ResolutionError: Error {}

    func makeBookmark(for url: URL) throws -> Data {
        Data(url.path.utf8)
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedSkillSourceBookmark {
        throw ResolutionError()
    }
}

private struct RecoveryBookmarker: SkillSourceBookmarking {
    let resolvedURL: URL

    func makeBookmark(for url: URL) throws -> Data {
        Data(url.path.utf8)
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedSkillSourceBookmark {
        ResolvedSkillSourceBookmark(url: resolvedURL, isStale: false)
    }
}

private final class ScopedDirectoryAccessState: @unchecked Sendable {
    private let lock = NSLock()
    private var activeURLs: Set<URL> = []

    func beginAccessing(_ url: URL) {
        lock.withLock {
            activeURLs.insert(url.standardizedFileURL)
        }
    }

    func stopAccessing(_ url: URL) {
        lock.withLock {
            activeURLs.remove(url.standardizedFileURL)
        }
    }

    func isAccessing(_ url: URL) -> Bool {
        lock.withLock {
            activeURLs.contains(url.standardizedFileURL)
        }
    }
}

@MainActor
private final class AccessTrackingSourceAccess: SkillSourceAccessing {
    private let state: ScopedDirectoryAccessState
    private var activeURLs: [SkillSource.ID: URL] = [:]

    init(state: ScopedDirectoryAccessState) {
        self.state = state
    }

    func beginAccessing(_ url: URL, for sourceID: SkillSource.ID) -> Bool {
        stopAccessing(sourceID: sourceID)
        activeURLs[sourceID] = url
        state.beginAccessing(url)
        return true
    }

    func stopAccessing(sourceID: SkillSource.ID) {
        guard let url = activeURLs.removeValue(forKey: sourceID) else {
            return
        }

        state.stopAccessing(url)
    }
}

private struct AccessRequiringBookmarker: SkillSourceBookmarking {
    enum BookmarkError: Error {
        case accessRequired
        case intentionalFailure
    }

    let state: ScopedDirectoryAccessState
    let failure: BookmarkError?

    init(
        state: ScopedDirectoryAccessState,
        failure: BookmarkError? = nil
    ) {
        self.state = state
        self.failure = failure
    }

    func makeBookmark(for url: URL) throws -> Data {
        guard state.isAccessing(url) else {
            throw BookmarkError.accessRequired
        }
        if let failure {
            throw failure
        }

        return Data(url.path.utf8)
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedSkillSourceBookmark {
        ResolvedSkillSourceBookmark(
            url: URL(filePath: String(decoding: data, as: UTF8.self)),
            isStale: false
        )
    }
}
