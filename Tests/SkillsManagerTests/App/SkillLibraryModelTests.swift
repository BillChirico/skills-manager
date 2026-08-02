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

    @Test("Restoring automatically adds and scans existing standard agent folders")
    func restoreAddsExistingStandardAgentFolders() async {
        let homeDirectory = URL(
            filePath: "/Users/reviewer",
            directoryHint: .isDirectory
        )
        let claudeDirectory = URL(
            filePath: "/Users/reviewer/.claude/skills",
            directoryHint: .isDirectory
        )
        let cursorDirectory = URL(
            filePath: "/Users/reviewer/.cursor/skills",
            directoryHint: .isDirectory
        )
        let existingDirectories = Set([claudeDirectory, cursorDirectory])
        let store = MemorySourceStore()
        let model = makeModel(
            sourceStore: store,
            discoverer: FixtureDiscoverer(),
            homeDirectory: homeDirectory,
            directoryExists: { existingDirectories.contains($0.standardizedFileURL) }
        )

        await model.restoreSources()

        #expect(model.sources.map(\.agent) == [.claudeCode, .cursor])
        #expect(Set(model.sources.map(\.directoryURL)) == existingDirectories)
        #expect(model.skills.count == 2)
        #expect(model.sidebarSelection == .allSkills)
        let persistedSources = await store.loadSources()
        #expect(persistedSources == model.sources)
    }

    @Test("Restoring keeps one Global source for the shared Global and Codex folder")
    func restoreDeduplicatesSharedStandardFolder() async throws {
        let homeDirectory = URL(
            filePath: "/Users/reviewer",
            directoryHint: .isDirectory
        )
        let sharedDirectory = URL(
            filePath: "/Users/reviewer/.agents/skills",
            directoryHint: .isDirectory
        )
        let model = makeModel(
            homeDirectory: homeDirectory,
            directoryExists: {
                $0.standardizedFileURL == sharedDirectory.standardizedFileURL
            }
        )

        await model.restoreSources()

        let source = try #require(model.sources.first)
        #expect(model.sources.count == 1)
        #expect(source.agent == .global)
        #expect(source.directoryURL == sharedDirectory)
    }

    @Test("A persisted standard folder wins over automatic detection")
    func restoreDoesNotDuplicatePersistedStandardFolder() async throws {
        let homeDirectory = URL(
            filePath: "/Users/reviewer",
            directoryHint: .isDirectory
        )
        let claudeDirectory = URL(
            filePath: "/Users/reviewer/.claude/skills",
            directoryHint: .isDirectory
        )
        let persistedSource = SkillSource(
            name: "My Claude Skills",
            directoryURL: claudeDirectory,
            agent: .other
        )
        let model = makeModel(
            sourceStore: MemorySourceStore(sources: [persistedSource]),
            homeDirectory: homeDirectory,
            directoryExists: {
                $0.standardizedFileURL == claudeDirectory.standardizedFileURL
            }
        )

        await model.restoreSources()

        let source = try #require(model.sources.first)
        #expect(model.sources.count == 1)
        #expect(source == persistedSource)
    }

    @Test("Restoring coalesces persisted paths that alias one physical folder")
    func restoreCoalescesPersistedPathAliases() async throws {
        let fixture = try makeSymlinkedClaudeDirectory()
        defer { try? FileManager.default.removeItem(at: fixture.rootDirectory) }

        let selectedSource = SkillSource(
            name: "Dotfiles Claude Skills",
            directoryURL: fixture.aliasDirectory,
            agent: .claudeCode
        )
        let duplicateSource = SkillSource(
            name: "Standard Claude Skills",
            directoryURL: fixture.standardDirectory,
            agent: .claudeCode
        )
        let store = MemorySourceStore(sources: [selectedSource, duplicateSource])
        let model = makeModel(
            sourceStore: store,
            homeDirectory: fixture.homeDirectory,
            directoryExists: {
                $0.standardizedFileURL == fixture.standardDirectory.standardizedFileURL
            }
        )

        await model.restoreSources()

        #expect(model.sources == [selectedSource])
        #expect(await store.loadConfiguration().sources == [selectedSource])
    }

    @Test("A persisted folder clears a stale automatic-folder exclusion")
    func restoreReconcilesExclusionForPersistedFolder() async throws {
        let homeDirectory = URL(
            filePath: "/Users/reviewer",
            directoryHint: .isDirectory
        )
        let claudeDirectory = URL(
            filePath: "/Users/reviewer/.claude/skills",
            directoryHint: .isDirectory
        )
        let persistedSource = SkillSource(
            name: "Claude Skills",
            directoryURL: claudeDirectory,
            agent: .claudeCode
        )
        let store = MemorySourceStore(
            sources: [persistedSource],
            excludedAutomaticDirectoryURLs: [claudeDirectory]
        )
        let model = makeModel(
            sourceStore: store,
            homeDirectory: homeDirectory,
            directoryExists: {
                $0.standardizedFileURL == claudeDirectory.standardizedFileURL
            }
        )

        await model.restoreSources()

        #expect(model.sources == [persistedSource])
        #expect(
            await store.loadConfiguration()
                .excludedAutomaticDirectoryURLs.isEmpty
        )
    }

    @Test("A failed restore save keeps loaded and automatic folders in memory")
    func failedRestoreSaveKeepsRestoredFoldersInMemory() async throws {
        let homeDirectory = URL(
            filePath: "/Users/reviewer",
            directoryHint: .isDirectory
        )
        let persistedDirectory = URL(
            filePath: "/skills/team",
            directoryHint: .isDirectory
        )
        let cursorDirectory = URL(
            filePath: "/Users/reviewer/.cursor/skills",
            directoryHint: .isDirectory
        )
        let addedAfterFailure = URL(
            filePath: "/skills/added-after-failure",
            directoryHint: .isDirectory
        )
        let persistedSource = SkillSource(
            name: "Team Skills",
            directoryURL: persistedDirectory
        )
        let store = FailOnceSourceStore(sources: [persistedSource])
        let model = makeModel(
            sourceStore: store,
            homeDirectory: homeDirectory,
            directoryExists: {
                $0.standardizedFileURL == cursorDirectory.standardizedFileURL
            }
        )

        await model.restoreSources()

        #expect(
            Set(model.sources.map { $0.directoryURL.standardizedFileURL })
                == Set([persistedDirectory, cursorDirectory])
        )
        #expect(
            await store.loadConfiguration()
                == SkillSourceConfiguration(sources: [persistedSource])
        )
        #expect(model.presentedError?.title == "Unable to Save Directories")

        try await model.addSource(at: addedAfterFailure)

        #expect(
            Set(
                await store.loadConfiguration().sources.map {
                    $0.directoryURL.standardizedFileURL
                }
            ) == Set([persistedDirectory, cursorDirectory, addedAfterFailure])
        )
    }

    @Test("An unavailable account home suppresses automatic folder detection")
    func restoreWithoutHomeDoesNotAddAutomaticFolders() async {
        let store = MemorySourceStore()
        let model = makeModel(
            sourceStore: store,
            homeDirectory: nil,
            directoryExists: { _ in true }
        )

        await model.restoreSources()

        #expect(model.sources.isEmpty)
        let persistedSources = await store.loadSources()
        #expect(persistedSources.isEmpty)
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

    @Test("A rescan does not publish results after its source is removed")
    func rescanDoesNotPublishAfterSourceRemoval() async throws {
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/skills/team")
        )
        let discoverer = SuspendingDiscoverer()
        let model = SkillLibraryModel(
            sources: [source],
            sourceStore: MemorySourceStore(sources: [source]),
            discoverer: discoverer
        )

        let scan = Task { @MainActor in
            try await model.rescanSource(source.id)
        }
        await discoverer.waitUntilDiscoveryStarted()
        try await model.removeSource(source.id)
        await discoverer.resumeDiscovery()
        try await scan.value

        #expect(model.sources.isEmpty)
        #expect(model.skills.isEmpty)
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

    @Test("Removing an automatic folder keeps it removed across restoration")
    func removedAutomaticFolderStaysExcluded() async throws {
        let homeDirectory = URL(
            filePath: "/Users/reviewer",
            directoryHint: .isDirectory
        )
        let cursorDirectory = URL(
            filePath: "/Users/reviewer/.cursor/skills",
            directoryHint: .isDirectory
        )
        let store = MemorySourceStore()
        let directoryExists: @Sendable (URL) -> Bool = {
            $0.standardizedFileURL == cursorDirectory.standardizedFileURL
        }
        let firstModel = makeModel(
            sourceStore: store,
            homeDirectory: homeDirectory,
            directoryExists: directoryExists
        )
        await firstModel.restoreSources()
        let automaticSource = try #require(firstModel.sources.first)

        try await firstModel.removeSource(automaticSource.id)

        let savedAfterRemoval = await store.loadConfiguration()
        #expect(firstModel.sources.isEmpty)
        #expect(savedAfterRemoval.sources.isEmpty)
        #expect(
            savedAfterRemoval.excludedAutomaticDirectoryURLs
                == Set([cursorDirectory])
        )

        let restoredModel = makeModel(
            sourceStore: store,
            homeDirectory: homeDirectory,
            directoryExists: directoryExists
        )
        await restoredModel.restoreSources()

        #expect(restoredModel.sources.isEmpty)
    }

    @Test("Removing a path alias durably excludes its automatic folder")
    func removedPathAliasStaysExcluded() async throws {
        let fixture = try makeSymlinkedClaudeDirectory()
        defer { try? FileManager.default.removeItem(at: fixture.rootDirectory) }

        let aliasedSource = SkillSource(
            name: "Dotfiles Claude Skills",
            directoryURL: fixture.aliasDirectory,
            agent: .claudeCode
        )
        let store = MemorySourceStore(sources: [aliasedSource])
        let directoryExists: @Sendable (URL) -> Bool = {
            $0.standardizedFileURL == fixture.standardDirectory.standardizedFileURL
        }
        let firstModel = makeModel(
            sourceStore: store,
            homeDirectory: fixture.homeDirectory,
            directoryExists: directoryExists
        )

        await firstModel.restoreSources()

        #expect(firstModel.sources == [aliasedSource])
        try await firstModel.removeSource(aliasedSource.id)

        let savedAfterRemoval = await store.loadConfiguration()
        #expect(savedAfterRemoval.sources.isEmpty)
        let savedExclusion = try #require(
            savedAfterRemoval.excludedAutomaticDirectoryURLs.first
        )
        #expect(savedAfterRemoval.excludedAutomaticDirectoryURLs.count == 1)
        #expect(
            savedExclusion.pathComponents
                == fixture.aliasDirectory.pathComponents
        )

        let restoredModel = makeModel(
            sourceStore: store,
            homeDirectory: fixture.homeDirectory,
            directoryExists: directoryExists
        )
        await restoredModel.restoreSources()

        #expect(restoredModel.sources.isEmpty)
    }

    @Test("Adding a path alias clears its canonical automatic-folder exclusion")
    func manualAliasAddClearsCanonicalExclusion() async throws {
        let fixture = try makeSymlinkedClaudeDirectory()
        defer { try? FileManager.default.removeItem(at: fixture.rootDirectory) }

        let store = MemorySourceStore(
            excludedAutomaticDirectoryURLs: [fixture.standardDirectory]
        )
        let model = makeModel(
            sourceStore: store,
            homeDirectory: fixture.homeDirectory,
            directoryExists: {
                $0.standardizedFileURL == fixture.standardDirectory.standardizedFileURL
            }
        )
        await model.restoreSources()
        #expect(model.sources.isEmpty)

        try await model.addSource(
            at: fixture.aliasDirectory,
            agent: .claudeCode
        )

        let savedAfterAdd = await store.loadConfiguration()
        #expect(savedAfterAdd.sources.first?.directoryURL == fixture.aliasDirectory)
        #expect(savedAfterAdd.excludedAutomaticDirectoryURLs.isEmpty)
    }

    @Test("Manually adding an excluded standard folder opts it back in")
    func manualAddClearsAutomaticFolderExclusion() async throws {
        let homeDirectory = URL(
            filePath: "/Users/reviewer",
            directoryHint: .isDirectory
        )
        let geminiDirectory = URL(
            filePath: "/Users/reviewer/.gemini/skills",
            directoryHint: .isDirectory
        )
        let store = MemorySourceStore(
            excludedAutomaticDirectoryURLs: Set([geminiDirectory])
        )
        let model = makeModel(
            sourceStore: store,
            homeDirectory: homeDirectory,
            directoryExists: {
                $0.standardizedFileURL == geminiDirectory.standardizedFileURL
            }
        )
        await model.restoreSources()
        #expect(model.sources.isEmpty)

        try await model.addSource(at: geminiDirectory, agent: .gemini)

        let savedAfterAdd = await store.loadConfiguration()
        #expect(savedAfterAdd.sources.count == 1)
        #expect(savedAfterAdd.excludedAutomaticDirectoryURLs.isEmpty)

        let restoredModel = makeModel(
            sourceStore: store,
            homeDirectory: homeDirectory,
            directoryExists: {
                $0.standardizedFileURL == geminiDirectory.standardizedFileURL
            }
        )
        await restoredModel.restoreSources()

        let restoredSource = try #require(restoredModel.sources.first)
        #expect(restoredModel.sources.count == 1)
        #expect(restoredSource.agent == .gemini)
        #expect(
            restoredSource.directoryURL.pathComponents
                == geminiDirectory.pathComponents
        )
    }

    @Test("A failed manual re-add restores the automatic-folder exclusion")
    func failedManualAddRestoresAutomaticFolderExclusion() async throws {
        let homeDirectory = URL(
            filePath: "/Users/reviewer",
            directoryHint: .isDirectory
        )
        let geminiDirectory = URL(
            filePath: "/Users/reviewer/.gemini/skills",
            directoryHint: .isDirectory
        )
        let store = FailOnceSourceStore(
            excludedAutomaticDirectoryURLs: [geminiDirectory]
        )
        let model = makeModel(
            sourceStore: store,
            homeDirectory: homeDirectory,
            directoryExists: {
                $0.standardizedFileURL == geminiDirectory.standardizedFileURL
            }
        )
        await model.restoreSources()

        await #expect(throws: FailOnceSourceStore.SaveError.self) {
            try await model.addSource(at: geminiDirectory, agent: .gemini)
        }

        let savedConfiguration = await store.loadConfiguration()
        #expect(model.sources.isEmpty)
        #expect(
            savedConfiguration.excludedAutomaticDirectoryURLs
                == [geminiDirectory]
        )
    }

    @Test("Removing a custom folder does not create an automatic-folder exclusion")
    func removingCustomFolderDoesNotCreateExclusion() async throws {
        let customSource = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/skills/team")
        )
        let store = MemorySourceStore(sources: [customSource])
        let model = SkillLibraryModel(
            sources: [customSource],
            sourceStore: store,
            homeDirectory: URL(
                filePath: "/Users/reviewer",
                directoryHint: .isDirectory
            ),
            directoryExists: { _ in true }
        )

        try await model.removeSource(customSource.id)

        let savedAfterRemoval = await store.loadConfiguration()
        #expect(savedAfterRemoval.sources.isEmpty)
        #expect(savedAfterRemoval.excludedAutomaticDirectoryURLs.isEmpty)
    }

    @Test("A failed automatic-folder removal rolls back its pending exclusion")
    func failedAutomaticFolderRemovalRollsBackExclusion() async throws {
        let homeDirectory = URL(
            filePath: "/Users/reviewer",
            directoryHint: .isDirectory
        )
        let cursorDirectory = URL(
            filePath: "/Users/reviewer/.cursor/skills",
            directoryHint: .isDirectory
        )
        let automaticSource = SkillSource(
            name: "Cursor Skills",
            directoryURL: cursorDirectory,
            agent: .cursor
        )
        let store = FailOnceSourceStore(sources: [automaticSource])
        let model = SkillLibraryModel(
            sources: [automaticSource],
            sourceStore: store,
            bookmarker: StubBookmarker(),
            sourceAccess: StubSourceAccess(),
            homeDirectory: homeDirectory,
            directoryExists: { _ in true }
        )

        await #expect(throws: FailOnceSourceStore.SaveError.self) {
            try await model.removeSource(automaticSource.id)
        }
        try await model.addSource(at: URL(filePath: "/skills/custom"))

        let savedAfterRecovery = await store.loadConfiguration()
        #expect(model.sources.contains(automaticSource))
        #expect(savedAfterRecovery.sources.contains(automaticSource))
        #expect(savedAfterRecovery.excludedAutomaticDirectoryURLs.isEmpty)
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

    @Test("A failed source mutation cannot roll back a later mutation")
    func serializesSourceMutationsAcrossPersistence() async throws {
        let homeDirectory = URL(
            filePath: "/Users/reviewer",
            directoryHint: .isDirectory
        )
        let automaticSource = SkillSource(
            name: "Cursor Skills",
            directoryURL: URL(
                filePath: "/Users/reviewer/.cursor/skills",
                directoryHint: .isDirectory
            ),
            agent: .cursor
        )
        let customDirectory = URL(
            filePath: "/skills/custom",
            directoryHint: .isDirectory
        )
        let store = SuspendingFailOnceSourceStore(sources: [automaticSource])
        let model = SkillLibraryModel(
            sources: [automaticSource],
            sourceStore: store,
            bookmarker: StubBookmarker(),
            sourceAccess: StubSourceAccess(),
            homeDirectory: homeDirectory
        )

        let removal = Task { @MainActor in
            try await model.removeSource(automaticSource.id)
        }
        await store.waitUntilFirstSaveStarted()
        let addition = Task { @MainActor in
            try await model.addSource(at: customDirectory)
        }

        // Give an incorrectly reentrant implementation ample opportunity to
        // persist the addition before the first save is released.
        for _ in 0..<100 where await store.saveCount < 2 {
            await Task.yield()
        }
        await store.failFirstSave()

        await #expect(throws: SuspendingFailOnceSourceStore.SaveError.self) {
            try await removal.value
        }
        try await addition.value

        let expectedDirectoryURLs = Set([
            automaticSource.directoryURL,
            customDirectory,
        ])
        let savedConfiguration = await store.loadConfiguration()
        #expect(Set(model.sources.map(\.directoryURL)) == expectedDirectoryURLs)
        #expect(
            Set(savedConfiguration.sources.map(\.directoryURL))
                == expectedDirectoryURLs
        )
        #expect(savedConfiguration.excludedAutomaticDirectoryURLs.isEmpty)
    }

    @Test("A failed removal preserves unrelated changes made during its save")
    func failedRemovalRollsBackOnlyRemovedSourceState() async throws {
        let removedSource = SkillSource(
            name: "Alpha Skills",
            directoryURL: URL(filePath: "/skills/alpha")
        )
        let otherSource = SkillSource(
            name: "Beta Skills",
            directoryURL: URL(filePath: "/skills/beta")
        )
        let removedSkill = AgentSkill(
            name: "Alpha Skill",
            directoryURL: removedSource.directoryURL.appending(path: "alpha"),
            sourceID: removedSource.id
        )
        let otherSkill = AgentSkill(
            name: "Beta Skill",
            directoryURL: otherSource.directoryURL.appending(path: "beta"),
            sourceID: otherSource.id
        )
        let store = SuspendingFailOnceSourceStore(
            sources: [removedSource, otherSource]
        )
        let model = SkillLibraryModel(
            sources: [removedSource, otherSource],
            skills: [removedSkill, otherSkill],
            sourceStore: store,
            discoverer: FailingDiscoverer()
        )
        model.sidebarSelection = .source(removedSource.id)
        model.selectedSkillIDs = [removedSkill.id]

        let removal = Task { @MainActor in
            try await model.removeSource(removedSource.id)
        }
        await store.waitUntilFirstSaveStarted()

        model.sidebarSelection = .source(otherSource.id)
        model.selectedSkillIDs = [otherSkill.id]
        model.setSkillsEnabled(false, skillIDs: [otherSkill.id])
        await #expect(throws: FailingDiscoverer.ScanError.self) {
            try await model.rescanSource(otherSource.id)
        }
        await store.failFirstSave()

        await #expect(throws: SuspendingFailOnceSourceStore.SaveError.self) {
            try await removal.value
        }

        #expect(Set(model.sources.map(\.id)) == [removedSource.id, otherSource.id])
        #expect(model.skills.first { $0.id == removedSkill.id }?.isEnabled == true)
        #expect(model.skills.first { $0.id == otherSkill.id }?.isEnabled == false)
        #expect(model.sourceState(for: otherSource.id) == .unavailable)
        #expect(model.sidebarSelection == .source(otherSource.id))
        #expect(model.selectedSkillIDs == [otherSkill.id])
    }

    @Test("A failed removal does not restore selection after sidebar navigation")
    func failedRemovalPreservesSidebarNavigation() async throws {
        let removedSource = SkillSource(
            name: "Alpha Skills",
            directoryURL: URL(filePath: "/skills/alpha")
        )
        let otherSource = SkillSource(
            name: "Beta Skills",
            directoryURL: URL(filePath: "/skills/beta")
        )
        let removedSkill = AgentSkill(
            name: "Alpha Skill",
            directoryURL: removedSource.directoryURL.appending(path: "alpha"),
            sourceID: removedSource.id
        )
        let store = SuspendingFailOnceSourceStore(
            sources: [removedSource, otherSource]
        )
        let model = SkillLibraryModel(
            sources: [removedSource, otherSource],
            skills: [removedSkill],
            sourceStore: store
        )
        model.sidebarSelection = .source(removedSource.id)
        model.selectedSkillIDs = [removedSkill.id]

        let removal = Task { @MainActor in
            try await model.removeSource(removedSource.id)
        }
        await store.waitUntilFirstSaveStarted()
        model.sidebarSelection = .source(otherSource.id)
        await store.failFirstSave()

        await #expect(throws: SuspendingFailOnceSourceStore.SaveError.self) {
            try await removal.value
        }

        #expect(model.sidebarSelection == .source(otherSource.id))
        #expect(model.selectedSkillIDs.isEmpty)
    }

    @Test("A failed removal does not restore an invalidated scanning state")
    func failedRemovalNormalizesInvalidatedScanState() async throws {
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/skills/team")
        )
        let store = SuspendingFailOnceSourceStore(sources: [source])
        let discoverer = SuspendingDiscoverer()
        let model = SkillLibraryModel(
            sources: [source],
            sourceStore: store,
            discoverer: discoverer
        )

        let scan = Task { @MainActor in
            try await model.rescanSource(source.id)
        }
        await discoverer.waitUntilDiscoveryStarted()
        let removal = Task { @MainActor in
            try await model.removeSource(source.id)
        }
        await store.waitUntilFirstSaveStarted()

        await discoverer.resumeDiscovery()
        try await scan.value
        await store.failFirstSave()
        await #expect(throws: SuspendingFailOnceSourceStore.SaveError.self) {
            try await removal.value
        }

        #expect(model.sources == [source])
        #expect(model.sourceState(for: source.id) == .available)
    }

    @Test("A failed relocation does not restore an invalidated scanning state")
    func failedRelocationNormalizesInvalidatedScanState() async throws {
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/skills/team")
        )
        let store = SuspendingFailOnceSourceStore(sources: [source])
        let discoverer = SuspendingDiscoverer()
        let model = SkillLibraryModel(
            sources: [source],
            sourceStore: store,
            discoverer: discoverer,
            bookmarker: StubBookmarker(),
            sourceAccess: StubSourceAccess()
        )

        let scan = Task { @MainActor in
            try await model.rescanSource(source.id)
        }
        await discoverer.waitUntilDiscoveryStarted()
        let relocation = Task { @MainActor in
            try await model.relocateSource(
                source.id,
                to: URL(filePath: "/skills/relocated")
            )
        }
        await store.waitUntilFirstSaveStarted()

        await discoverer.resumeDiscovery()
        try await scan.value
        await store.failFirstSave()
        await #expect(throws: SuspendingFailOnceSourceStore.SaveError.self) {
            try await relocation.value
        }

        #expect(model.sources == [source])
        #expect(model.sourceState(for: source.id) == .available)
    }

    @Test("Updating a skill runs the CLI and rescans configured directories")
    func updateRunsLifecycleAndRescans() async throws {
        let primarySource = SkillSource(
            name: "Alpha",
            directoryURL: URL(filePath: "/skills/alpha"),
            agent: .claudeCode
        )
        let secondarySource = SkillSource(
            name: "Beta",
            directoryURL: URL(filePath: "/skills/beta"),
            agent: .cursor
        )
        let skill = makeLifecycleSkill(
            named: "Primary",
            identifier: "primary",
            installedVersion: "1.0.0",
            availableVersion: "2.0.0",
            source: primarySource
        )
        let secondarySkill = makeLifecycleSkill(
            named: "Secondary",
            identifier: "secondary",
            installedVersion: "1.0.0",
            availableVersion: "1.0.0",
            source: secondarySource
        )
        let refreshedSkill = makeLifecycleSkill(
            named: "Primary",
            identifier: "primary",
            installedVersion: "2.0.0",
            availableVersion: nil,
            source: primarySource
        )
        let discoverer = RecordingLifecycleDiscoverer(
            skillsBySource: [
                primarySource.id: [refreshedSkill],
                secondarySource.id: [secondarySkill],
            ]
        )
        let skillManager = RecordingLifecycleManager()
        let model = SkillLibraryModel(
            sources: [primarySource, secondarySource],
            skills: [skill, secondarySkill],
            discoverer: discoverer,
            skillManager: skillManager
        )

        await model.updateSkills([skill.id])

        #expect(await skillManager.updatedSkillIDs == [skill.id])
        #expect(Set(await discoverer.scannedSourceIDs) == [primarySource.id, secondarySource.id])
        #expect(model.skills.first { $0.id == skill.id }?.installedVersion == "2.0.0")
        #expect(model.skills.first { $0.id == skill.id }?.availableVersion == "2.0.0")
        #expect(model.mutatingSkillIDs.isEmpty)
        #expect(model.presentedError == nil)
    }

    @Test("A lifecycle operation exposes busy state until its process completes")
    func lifecycleBusyState() async throws {
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/skills/team"),
            agent: .claudeCode
        )
        let skill = makeLifecycleSkill(
            named: "Primary",
            identifier: "primary",
            installedVersion: "1.0.0",
            availableVersion: "2.0.0",
            source: source
        )
        let refreshedSkill = makeLifecycleSkill(
            named: "Primary",
            identifier: "primary",
            installedVersion: "2.0.0",
            availableVersion: nil,
            source: source
        )
        let skillManager = SuspendingLifecycleManager()
        let model = SkillLibraryModel(
            sources: [source],
            skills: [skill],
            discoverer: RecordingLifecycleDiscoverer(
                skillsBySource: [source.id: [refreshedSkill]]
            ),
            skillManager: skillManager
        )

        let update = Task { await model.updateSkills([skill.id]) }
        await skillManager.waitUntilUpdateStarted()

        #expect(model.isMutating(skill.id))

        await skillManager.resumeUpdate()
        await update.value

        #expect(model.isMutating(skill.id) == false)
    }

    @Test("A failed removal stays visible while successful removals disappear")
    func removalReportsPartialFailure() async throws {
        let successfulSource = SkillSource(
            name: "Alpha",
            directoryURL: URL(filePath: "/skills/alpha"),
            agent: .claudeCode
        )
        let failingSource = SkillSource(
            name: "Beta",
            directoryURL: URL(filePath: "/skills/beta"),
            agent: .cursor
        )
        let successfulSkill = makeLifecycleSkill(
            named: "Successful",
            identifier: "successful",
            source: successfulSource
        )
        let failingSkill = makeLifecycleSkill(
            named: "Failing",
            identifier: "failing",
            source: failingSource
        )
        let skillManager = RecordingLifecycleManager(failingSkillIDs: [failingSkill.id])
        let model = SkillLibraryModel(
            sources: [successfulSource, failingSource],
            skills: [successfulSkill, failingSkill],
            discoverer: RecordingLifecycleDiscoverer(skillsBySource: [:]),
            skillManager: skillManager
        )
        model.selectedSkillIDs = [successfulSkill.id, failingSkill.id]

        await model.removeSkills(model.selectedSkillIDs)

        #expect(Set(await skillManager.removedSkillIDs) == [successfulSkill.id, failingSkill.id])
        #expect(model.skills.map(\.id) == [failingSkill.id])
        #expect(model.selectedSkillIDs == [failingSkill.id])
        #expect(model.presentedError?.title == "Unable to Remove Failing")
        #expect(model.presentedError?.message.contains("Permission denied") == true)
        #expect(model.mutatingSkillIDs.isEmpty)
    }

    private func makeLifecycleSkill(
        named name: String,
        identifier: String,
        installedVersion: String? = nil,
        availableVersion: String? = nil,
        source: SkillSource
    ) -> AgentSkill {
        AgentSkill(
            name: name,
            summary: "Lifecycle fixture.",
            installedVersion: installedVersion,
            availableVersion: availableVersion,
            directoryURL: source.directoryURL.appending(path: identifier),
            sourceID: source.id,
            relativePath: identifier
        )
    }

    private func makeSymlinkedClaudeDirectory() throws -> (
        rootDirectory: URL,
        homeDirectory: URL,
        standardDirectory: URL,
        aliasDirectory: URL
    ) {
        let rootDirectory = URL.temporaryDirectory.appending(
            path: "SkillLibraryModelTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let homeDirectory = rootDirectory.appending(
            path: "home",
            directoryHint: .isDirectory
        )
        let dotfilesDirectory = rootDirectory.appending(
            path: "dotfiles",
            directoryHint: .isDirectory
        )
        let aliasDirectory = dotfilesDirectory.appending(
            path: "skills",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: homeDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: aliasDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: homeDirectory.appending(
                path: ".claude",
                directoryHint: .isDirectory
            ),
            withDestinationURL: dotfilesDirectory
        )
        let standardDirectory = homeDirectory.appending(
            path: ".claude/skills",
            directoryHint: .isDirectory
        )

        return (
            rootDirectory: rootDirectory,
            homeDirectory: homeDirectory,
            standardDirectory: standardDirectory,
            aliasDirectory: aliasDirectory
        )
    }

    private func makeModel(
        sourceStore: any SkillSourceStore = MemorySourceStore(),
        discoverer: any SkillDiscovering = EmptyDiscoverer(),
        homeDirectory: URL? = nil,
        directoryExists: @escaping @Sendable (URL) -> Bool = { _ in false }
    ) -> SkillLibraryModel {
        SkillLibraryModel(
            sourceStore: sourceStore,
            discoverer: discoverer,
            bookmarker: StubBookmarker(),
            sourceAccess: StubSourceAccess(),
            homeDirectory: homeDirectory,
            directoryExists: directoryExists
        )
    }
}

enum SourceRestoreFailure: CaseIterable, Sendable {
    case bookmarkResolution
    case securityScopeAccess
}

private actor MemorySourceStore: SkillSourceStore {
    private var configuration: SkillSourceConfiguration

    init(
        sources: [SkillSource] = [],
        excludedAutomaticDirectoryURLs: Set<URL> = []
    ) {
        self.configuration = SkillSourceConfiguration(
            sources: sources,
            excludedAutomaticDirectoryURLs: excludedAutomaticDirectoryURLs
        )
    }

    func loadSources() -> [SkillSource] {
        configuration.sources
    }

    func save(_ sources: [SkillSource]) {
        configuration.sources = sources
    }

    func loadConfiguration() async -> SkillSourceConfiguration {
        configuration
    }

    func save(_ configuration: SkillSourceConfiguration) async {
        self.configuration = configuration
    }
}

private actor FailOnceSourceStore: SkillSourceStore {
    struct SaveError: Error {}

    private var configuration: SkillSourceConfiguration
    private var shouldFailNextSave = true

    init(
        sources: [SkillSource] = [],
        excludedAutomaticDirectoryURLs: Set<URL> = []
    ) {
        self.configuration = SkillSourceConfiguration(
            sources: sources,
            excludedAutomaticDirectoryURLs: excludedAutomaticDirectoryURLs
        )
    }

    func loadSources() -> [SkillSource] {
        configuration.sources
    }

    func save(_ sources: [SkillSource]) throws {
        try saveConfiguration(
            SkillSourceConfiguration(
                sources: sources,
                excludedAutomaticDirectoryURLs:
                    configuration.excludedAutomaticDirectoryURLs
            )
        )
    }

    func loadConfiguration() async -> SkillSourceConfiguration {
        configuration
    }

    func save(_ configuration: SkillSourceConfiguration) async throws {
        try saveConfiguration(configuration)
    }

    private func saveConfiguration(
        _ configuration: SkillSourceConfiguration
    ) throws {
        if shouldFailNextSave {
            shouldFailNextSave = false
            throw SaveError()
        }

        self.configuration = configuration
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

private actor SuspendingFailOnceSourceStore: SkillSourceStore {
    struct SaveError: Error {}

    private var configuration: SkillSourceConfiguration
    private var firstSaveContinuation: CheckedContinuation<Void, Never>?
    private var firstSaveStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var shouldReleaseFirstSave = false
    private(set) var saveCount = 0

    init(sources: [SkillSource] = []) {
        self.configuration = SkillSourceConfiguration(sources: sources)
    }

    func loadSources() -> [SkillSource] {
        configuration.sources
    }

    func save(_ sources: [SkillSource]) async throws {
        try await save(
            SkillSourceConfiguration(
                sources: sources,
                excludedAutomaticDirectoryURLs:
                    configuration.excludedAutomaticDirectoryURLs
            )
        )
    }

    func loadConfiguration() async -> SkillSourceConfiguration {
        configuration
    }

    func save(_ configuration: SkillSourceConfiguration) async throws {
        saveCount += 1
        guard saveCount == 1 else {
            self.configuration = configuration
            return
        }

        let waiters = firstSaveStartWaiters
        firstSaveStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            if shouldReleaseFirstSave {
                continuation.resume()
            } else {
                firstSaveContinuation = continuation
            }
        }
        throw SaveError()
    }

    func waitUntilFirstSaveStarted() async {
        guard saveCount == 0 else {
            return
        }

        await withCheckedContinuation { continuation in
            firstSaveStartWaiters.append(continuation)
        }
    }

    func failFirstSave() {
        guard let firstSaveContinuation else {
            shouldReleaseFirstSave = true
            return
        }

        self.firstSaveContinuation = nil
        firstSaveContinuation.resume()
    }
}

private struct EmptyDiscoverer: SkillDiscovering {
    func discoverSkills(in source: SkillSource) async throws -> [AgentSkill] {
        []
    }
}

private actor SuspendingDiscoverer: SkillDiscovering {
    private var discoveryContinuation: CheckedContinuation<Void, Never>?

    func discoverSkills(in source: SkillSource) async throws -> [AgentSkill] {
        await withCheckedContinuation { continuation in
            discoveryContinuation = continuation
        }
        return [
            AgentSkill(
                name: "Late Skill",
                summary: "Late Skill summary",
                directoryURL: source.directoryURL.appending(path: "late"),
                sourceID: source.id
            )
        ]
    }

    func waitUntilDiscoveryStarted() async {
        while discoveryContinuation == nil {
            await Task.yield()
        }
    }

    func resumeDiscovery() {
        discoveryContinuation?.resume()
        discoveryContinuation = nil
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

private actor RecordingLifecycleDiscoverer: SkillDiscovering {
    private let skillsBySource: [SkillSource.ID: [AgentSkill]]
    private(set) var scannedSourceIDs: [SkillSource.ID] = []

    init(skillsBySource: [SkillSource.ID: [AgentSkill]]) {
        self.skillsBySource = skillsBySource
    }

    func discoverSkills(in source: SkillSource) async throws -> [AgentSkill] {
        scannedSourceIDs.append(source.id)
        return skillsBySource[source.id] ?? []
    }
}

private actor RecordingLifecycleManager: SkillManaging {
    struct ManagerError: LocalizedError {
        var errorDescription: String? { "Permission denied" }
    }

    private let failingSkillIDs: Set<AgentSkill.ID>
    private(set) var updatedSkillIDs: [AgentSkill.ID] = []
    private(set) var removedSkillIDs: [AgentSkill.ID] = []

    init(failingSkillIDs: Set<AgentSkill.ID> = []) {
        self.failingSkillIDs = failingSkillIDs
    }

    func install(_ skill: CatalogSkill, into source: SkillSource) async throws -> URL {
        source.directoryURL.appending(path: skill.slug, directoryHint: .isDirectory)
    }

    func update(_ skill: AgentSkill, in source: SkillSource) async throws {
        updatedSkillIDs.append(skill.id)
        if failingSkillIDs.contains(skill.id) {
            throw ManagerError()
        }
    }

    func remove(_ skill: AgentSkill, from source: SkillSource) async throws {
        removedSkillIDs.append(skill.id)
        if failingSkillIDs.contains(skill.id) {
            throw ManagerError()
        }
    }
}

private actor SuspendingLifecycleManager: SkillManaging {
    private var updateContinuation: CheckedContinuation<Void, Never>?

    func install(_ skill: CatalogSkill, into source: SkillSource) async throws -> URL {
        source.directoryURL.appending(path: skill.slug, directoryHint: .isDirectory)
    }

    func update(_ skill: AgentSkill, in source: SkillSource) async throws {
        await withCheckedContinuation { continuation in
            updateContinuation = continuation
        }
    }

    func remove(_ skill: AgentSkill, from source: SkillSource) async throws {}

    func waitUntilUpdateStarted() async {
        while updateContinuation == nil {
            await Task.yield()
        }
    }

    func resumeUpdate() {
        updateContinuation?.resume()
        updateContinuation = nil
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
