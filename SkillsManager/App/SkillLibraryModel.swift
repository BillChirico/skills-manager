import Foundation
import Observation
import SkillsCore

@MainActor
@Observable
final class SkillLibraryModel {
    enum SourceState: Hashable {
        case available
        case scanning
        case unavailable
    }

    struct PresentedError: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    enum SourceAccessError: LocalizedError, Equatable {
        case accessDenied

        var errorDescription: String? {
            "Skills Manager could not access the selected directory."
        }
    }

    private enum LifecycleError: LocalizedError {
        case unavailable
        case sourceMissing

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "Skill lifecycle operations are unavailable."
            case .sourceMissing:
                "The skill's configured directory could not be found."
            }
        }
    }

    private struct LifecycleFailure {
        let name: String
        let message: String
    }

    private(set) var sources: [SkillSource]
    private(set) var skills: [AgentSkill]
    private(set) var sourceStates: [SkillSource.ID: SourceState]
    var sidebarSelection: SkillLibraryScope {
        didSet {
            if sidebarSelection != oldValue {
                selectedSkillIDs.removeAll()
            }
        }
    }
    var selectedSkillIDs: Set<AgentSkill.ID>
    var searchText = ""
    var sortOrder: SkillSortOrder
    var presentedError: PresentedError?
    private(set) var mutatingSkillIDs: Set<AgentSkill.ID> = []

    @ObservationIgnored private let sourceStore: (any SkillSourceStore)?
    @ObservationIgnored private let discoverer: (any SkillDiscovering)?
    @ObservationIgnored private let bookmarker: (any SkillSourceBookmarking)?
    @ObservationIgnored private let sourceAccess: (any SkillSourceAccessing)?
    @ObservationIgnored private let skillManager: (any SkillManaging)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var hasRestoredSources = false

    init(
        sources: [SkillSource] = [],
        skills: [AgentSkill] = [],
        sourceStore: (any SkillSourceStore)? = nil,
        discoverer: (any SkillDiscovering)? = nil,
        bookmarker: (any SkillSourceBookmarking)? = nil,
        sourceAccess: (any SkillSourceAccessing)? = nil,
        skillManager: (any SkillManaging)? = nil,
        sortOrder: SkillSortOrder = .name,
        now: @escaping () -> Date = { .now }
    ) {
        let sortedSources = Self.sortedSources(sources)
        self.sources = sortedSources
        self.skills = Self.sortedSkills(skills)
        self.sourceStore = sourceStore
        self.discoverer = discoverer
        self.bookmarker = bookmarker
        self.sourceAccess = sourceAccess
        self.skillManager = skillManager
        self.now = now
        self.sourceStates = Dictionary(
            uniqueKeysWithValues: sortedSources.map { ($0.id, .available) }
        )
        self.sidebarSelection = .allSkills
        self.selectedSkillIDs = []
        self.sortOrder = sortOrder
    }

    var visibleSkills: [AgentSkill] {
        filteredSkills(in: sidebarSelection, query: searchText)
    }

    var selectedSkills: [AgentSkill] {
        Self.sortedSkills(skills.filter { selectedSkillIDs.contains($0.id) })
    }

    var selectedSkill: AgentSkill? {
        guard selectedSkills.count == 1 else {
            return nil
        }

        return selectedSkills.first
    }

    var allSkillsCount: Int {
        filteredSkills(in: .allSkills, query: "").count
    }

    var updatesAvailableCount: Int {
        filteredSkills(in: .updatesAvailable, query: "").count
    }

    var disabledCount: Int {
        filteredSkills(in: .disabled, query: "").count
    }

    var recentlyAddedCount: Int {
        filteredSkills(in: .recentlyAdded, query: "").count
    }

    var searchPrompt: String {
        switch sidebarSelection {
        case .allSkills:
            "Search All Skills"
        case .updatesAvailable:
            "Search Updates Available"
        case .disabled:
            "Search Disabled Skills"
        case .recentlyAdded:
            "Search Recently Added"
        case .source(let sourceID):
            "Search \(source(for: sourceID)?.displayName ?? "Directory")"
        }
    }

    /// The window title, which names what the content column is currently showing.
    var scopeTitle: String {
        switch sidebarSelection {
        case .allSkills:
            "All Skills"
        case .updatesAvailable:
            "Updates Available"
        case .disabled:
            "Disabled"
        case .recentlyAdded:
            "Recently Added"
        case .source(let sourceID):
            source(for: sourceID)?.displayName ?? "Skills Manager"
        }
    }

    /// The window subtitle, which counts what is in view and narrows to matches while searching.
    var scopeSubtitle: String {
        let visibleCount = visibleSkills.count

        guard isSearching else {
            return visibleCount == 0 ? "No skills" : "\(visibleCount) \(skillNoun(visibleCount))"
        }

        let scopeCount = filteredSkills(in: sidebarSelection, query: "").count
        return "\(visibleCount) of \(scopeCount) \(skillNoun(scopeCount))"
    }

    private var isSearching: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func skillNoun(_ count: Int) -> String {
        count == 1 ? "skill" : "skills"
    }

    var canSearchAllSkills: Bool {
        isSearching
            && sidebarSelection != .allSkills
            && visibleSkills.isEmpty
            && filteredSkills(in: .allSkills, query: searchText).isEmpty == false
    }

    func source(for sourceID: SkillSource.ID) -> SkillSource? {
        sources.first { $0.id == sourceID }
    }

    func sourceName(for skill: AgentSkill) -> String {
        source(for: skill.sourceID)?.displayName ?? "Unknown Directory"
    }

    func agentName(for skill: AgentSkill) -> String {
        source(for: skill.sourceID)?.agent.displayName ?? SkillAgent.other.displayName
    }

    func sourceState(for sourceID: SkillSource.ID) -> SourceState {
        sourceStates[sourceID] ?? .available
    }

    func skillCount(for sourceID: SkillSource.ID) -> Int {
        filteredSkills(in: .source(sourceID), query: "").count
    }

    func searchAllSkills() {
        sidebarSelection = .allSkills
    }

    func restoreSources() async {
        guard hasRestoredSources == false else {
            return
        }
        hasRestoredSources = true

        guard let sourceStore else {
            return
        }

        do {
            var restoredSources = try await sourceStore.loadSources()
            var didRefreshBookmark = false

            for index in restoredSources.indices {
                let sourceID = restoredSources[index].id
                sourceStates[sourceID] = .available

                guard
                    let bookmarkData = restoredSources[index].bookmarkData,
                    let bookmarker
                else {
                    continue
                }

                do {
                    let resolved = try bookmarker.resolveBookmark(bookmarkData)
                    restoredSources[index].directoryURL = resolved.url

                    if sourceAccess?.beginAccessing(resolved.url, for: sourceID) == false {
                        sourceStates[sourceID] = .unavailable
                    }

                    if resolved.isStale {
                        restoredSources[index].bookmarkData =
                            try bookmarker.makeBookmark(for: resolved.url)
                        didRefreshBookmark = true
                    }
                } catch {
                    sourceStates[sourceID] = .unavailable
                }
            }

            sources = Self.sortedSources(restoredSources)

            if didRefreshBookmark {
                try await sourceStore.save(sources)
            }

            for source in sources
            where source.isEnabled && sourceState(for: source.id) == .available {
                do {
                    try await rescanSource(source.id)
                } catch {
                    report(
                        error,
                        title: "Unable to Scan \(source.displayName)"
                    )
                }
            }
        } catch {
            report(error, title: "Unable to Restore Directories")
        }
    }

    func addSource(
        at directoryURL: URL,
        agent: SkillAgent = .other
    ) async throws {
        let normalizedURL = directoryURL.standardizedFileURL

        if let existingSource = sources.first(where: {
            $0.directoryURL.standardizedFileURL == normalizedURL
        }) {
            sidebarSelection = .source(existingSource.id)
            if sourceState(for: existingSource.id) == .unavailable {
                try await recoverSource(existingSource.id, at: normalizedURL)
            }
            return
        }

        var source = SkillSource(
            name: normalizedURL.lastPathComponent,
            directoryURL: normalizedURL,
            agent: agent
        )
        let accessGranted =
            sourceAccess?.beginAccessing(normalizedURL, for: source.id) ?? true

        guard accessGranted else {
            throw SourceAccessError.accessDenied
        }

        do {
            source.bookmarkData = try bookmarker?.makeBookmark(for: normalizedURL)
        } catch {
            sourceAccess?.stopAccessing(sourceID: source.id)
            throw error
        }

        sources.append(source)
        sources = Self.sortedSources(sources)
        sourceStates[source.id] = .available
        sidebarSelection = .source(source.id)

        do {
            try await persistSources()
        } catch {
            sources.removeAll { $0.id == source.id }
            sourceStates[source.id] = nil
            sourceAccess?.stopAccessing(sourceID: source.id)
            sidebarSelection = .allSkills
            throw error
        }

        if discoverer != nil {
            do {
                try await rescanSource(source.id)
            } catch {
                report(
                    error,
                    title: "Unable to Scan \(source.displayName)"
                )
            }
        }
    }

    func relocateSource(_ sourceID: SkillSource.ID, to directoryURL: URL) async throws {
        try await recoverSource(sourceID, at: directoryURL.standardizedFileURL)
    }

    func renameSource(_ sourceID: SkillSource.ID, to name: String) async throws {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        let previousName = sources[index].name
        sources[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        sources = Self.sortedSources(sources)

        do {
            try await persistSources()
        } catch {
            guard let rollbackIndex = sources.firstIndex(where: { $0.id == sourceID }) else {
                throw error
            }
            sources[rollbackIndex].name = previousName
            sources = Self.sortedSources(sources)
            throw error
        }
    }

    func setSourceAgent(_ agent: SkillAgent, sourceID: SkillSource.ID) async throws {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        let previousAgent = sources[index].agent
        sources[index].agent = agent
        sources = Self.sortedSources(sources)

        do {
            try await persistSources()
        } catch {
            guard let rollbackIndex = sources.firstIndex(where: { $0.id == sourceID }) else {
                throw error
            }
            sources[rollbackIndex].agent = previousAgent
            sources = Self.sortedSources(sources)
            throw error
        }
    }

    func setSourceEnabled(_ isEnabled: Bool, sourceID: SkillSource.ID) async throws {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        let previousValue = sources[index].isEnabled
        sources[index].isEnabled = isEnabled

        do {
            try await persistSources()
        } catch {
            guard let rollbackIndex = sources.firstIndex(where: { $0.id == sourceID }) else {
                throw error
            }
            sources[rollbackIndex].isEnabled = previousValue
            throw error
        }

        if isEnabled, sourceState(for: sourceID) == .available {
            try await rescanSource(sourceID)
        } else {
            selectedSkillIDs.subtract(
                skills.lazy.filter { $0.sourceID == sourceID }.map(\.id)
            )
        }
    }

    func removeSource(_ sourceID: SkillSource.ID) async throws {
        let previousSources = sources
        let previousSkills = skills
        let previousSelection = selectedSkillIDs
        let previousSourceStates = sourceStates
        let previousSidebarSelection = sidebarSelection

        sources.removeAll { $0.id == sourceID }
        skills.removeAll { $0.sourceID == sourceID }
        selectedSkillIDs.subtract(previousSkills.lazy.filter { $0.sourceID == sourceID }.map(\.id))
        sourceStates[sourceID] = nil

        if sidebarSelection == .source(sourceID) {
            sidebarSelection = .allSkills
        }

        do {
            try await persistSources()
            sourceAccess?.stopAccessing(sourceID: sourceID)
        } catch {
            sources = previousSources
            skills = previousSkills
            sourceStates = previousSourceStates
            sidebarSelection = previousSidebarSelection
            selectedSkillIDs = previousSelection
            throw error
        }
    }

    func rescanSource(_ sourceID: SkillSource.ID) async throws {
        guard
            let source = source(for: sourceID),
            source.isEnabled,
            let discoverer
        else {
            return
        }

        sourceStates[sourceID] = .scanning

        do {
            let discoveredSkills = try await discoverer.discoverSkills(in: source)
            let existingSkills = Dictionary(
                uniqueKeysWithValues:
                    skills
                    .filter { $0.sourceID == sourceID }
                    .map { ($0.id, $0) }
            )
            let mergedSkills = discoveredSkills.map { discoveredSkill in
                guard let existing = existingSkills[discoveredSkill.id] else {
                    return discoveredSkill
                }

                var merged = discoveredSkill
                merged.isEnabled = existing.isEnabled
                merged.availableVersion = existing.availableVersion
                return merged
            }

            skills.removeAll { $0.sourceID == sourceID }
            skills.append(contentsOf: mergedSkills)
            skills = Self.sortedSkills(skills)
            sourceStates[sourceID] = .available
            reconcileSelection()
        } catch {
            sourceStates[sourceID] = .unavailable
            throw error
        }
    }

    func isMutating(_ skillID: AgentSkill.ID) -> Bool {
        mutatingSkillIDs.contains(skillID)
    }

    func updateSkills(_ skillIDs: Set<AgentSkill.ID>) async {
        let selectedSkills = skills.filter {
            skillIDs.contains($0.id)
                && $0.hasUpdate
                && mutatingSkillIDs.contains($0.id) == false
        }
        guard selectedSkills.isEmpty == false else {
            return
        }

        mutatingSkillIDs.formUnion(selectedSkills.map(\.id))
        defer {
            mutatingSkillIDs.subtract(selectedSkills.map(\.id))
        }

        var failures: [LifecycleFailure] = []
        var didUpdate = false

        for skill in selectedSkills {
            guard let skillManager else {
                failures.append(failure(for: skill, error: LifecycleError.unavailable))
                continue
            }
            guard let source = source(for: skill.sourceID) else {
                failures.append(failure(for: skill, error: LifecycleError.sourceMissing))
                continue
            }

            do {
                try await skillManager.update(skill, in: source)
                didUpdate = true
            } catch {
                failures.append(failure(for: skill, error: error))
            }
        }

        if didUpdate {
            let sourceIDs = Set(
                sources
                    .filter {
                        $0.isEnabled && sourceState(for: $0.id) == .available
                    }
                    .map(\.id)
            )
            failures.append(contentsOf: await rescanSources(sourceIDs))
        }

        presentLifecycleFailures(failures, action: "Update", pastParticiple: "Updated")
    }

    func setSkillsEnabled(_ isEnabled: Bool, skillIDs: Set<AgentSkill.ID>) {
        for index in skills.indices where skillIDs.contains(skills[index].id) {
            skills[index].isEnabled = isEnabled
        }
    }

    func removeSkills(_ skillIDs: Set<AgentSkill.ID>) async {
        let selectedSkills = skills.filter {
            skillIDs.contains($0.id) && mutatingSkillIDs.contains($0.id) == false
        }
        guard selectedSkills.isEmpty == false else {
            return
        }

        mutatingSkillIDs.formUnion(selectedSkills.map(\.id))
        defer {
            mutatingSkillIDs.subtract(selectedSkills.map(\.id))
        }

        var failures: [LifecycleFailure] = []
        var removedSkillIDs: Set<AgentSkill.ID> = []
        var affectedDirectoryURLs: Set<URL> = []

        for skill in selectedSkills {
            guard let skillManager else {
                failures.append(failure(for: skill, error: LifecycleError.unavailable))
                continue
            }
            guard let source = source(for: skill.sourceID) else {
                failures.append(failure(for: skill, error: LifecycleError.sourceMissing))
                continue
            }

            do {
                try await skillManager.remove(skill, from: source)
                removedSkillIDs.insert(skill.id)
                affectedDirectoryURLs.insert(source.directoryURL.standardizedFileURL)
            } catch {
                failures.append(failure(for: skill, error: error))
            }
        }

        if removedSkillIDs.isEmpty == false {
            skills.removeAll { removedSkillIDs.contains($0.id) }
            selectedSkillIDs.subtract(removedSkillIDs)

            let sourceIDs = Set(
                sources
                    .filter {
                        affectedDirectoryURLs.contains($0.directoryURL.standardizedFileURL)
                    }
                    .map(\.id)
            )
            failures.append(contentsOf: await rescanSources(sourceIDs))
        }

        presentLifecycleFailures(failures, action: "Remove", pastParticiple: "Removed")
    }

    func selectSkill(at directoryURL: URL, sourceID: SkillSource.ID) {
        guard
            let skill = skills.first(where: {
                $0.sourceID == sourceID
                    && $0.directoryURL.standardizedFileURL == directoryURL.standardizedFileURL
            })
        else {
            return
        }

        sidebarSelection = .source(sourceID)
        selectedSkillIDs = [skill.id]
    }

    func report(_ error: any Error, title: String) {
        presentedError = PresentedError(
            title: title,
            message: error.localizedDescription
        )
    }

    private func failure(for skill: AgentSkill, error: any Error) -> LifecycleFailure {
        LifecycleFailure(name: skill.name, message: error.localizedDescription)
    }

    private func rescanSources(_ sourceIDs: Set<SkillSource.ID>) async -> [LifecycleFailure] {
        var failures: [LifecycleFailure] = []

        for sourceID in sourceIDs {
            guard let source = source(for: sourceID) else {
                continue
            }

            do {
                try await rescanSource(sourceID)
            } catch {
                failures.append(
                    LifecycleFailure(
                        name: source.displayName,
                        message: "The directory could not be rescanned: \(error.localizedDescription)"
                    )
                )
            }
        }

        return failures
    }

    private func presentLifecycleFailures(
        _ failures: [LifecycleFailure],
        action: String,
        pastParticiple: String
    ) {
        guard failures.isEmpty == false else {
            return
        }

        let title =
            failures.count == 1
            ? "Unable to \(action) \(failures[0].name)"
            : "Some Skills Could Not Be \(pastParticiple)"
        let message =
            failures
            .map { "\($0.name): \($0.message)" }
            .joined(separator: "\n")
        presentedError = PresentedError(title: title, message: message)
    }

    private var recentCutoff: Date {
        now().addingTimeInterval(-14 * 24 * 60 * 60)
    }

    private func filteredSkills(
        in scope: SkillLibraryScope,
        query: String
    ) -> [AgentSkill] {
        SkillLibraryFilter.filter(
            skills,
            sources: sources,
            scope: scope,
            query: query,
            recentCutoff: recentCutoff,
            sortOrder: sortOrder
        )
    }

    private func persistSources() async throws {
        try await sourceStore?.save(sources)
    }

    private func recoverSource(
        _ sourceID: SkillSource.ID,
        at directoryURL: URL
    ) async throws {
        guard let sourceIndex = sources.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        let previousSource = sources[sourceIndex]
        let previousState = sourceStates[sourceID]
        let accessGranted =
            sourceAccess?.beginAccessing(directoryURL, for: sourceID) ?? true

        guard accessGranted else {
            restoreSourceAccess(previousSource, state: previousState)
            throw SourceAccessError.accessDenied
        }

        let bookmarkData: Data?
        do {
            bookmarkData = try bookmarker?.makeBookmark(for: directoryURL)
        } catch {
            restoreSourceAccess(previousSource, state: previousState)
            throw error
        }

        sources[sourceIndex].directoryURL = directoryURL
        sources[sourceIndex].bookmarkData = bookmarkData
        sources = Self.sortedSources(sources)
        sourceStates[sourceID] = .available

        do {
            try await persistSources()
        } catch {
            guard let rollbackIndex = sources.firstIndex(where: { $0.id == sourceID }) else {
                throw error
            }
            sources[rollbackIndex] = previousSource
            sources = Self.sortedSources(sources)
            restoreSourceAccess(previousSource, state: previousState)
            throw error
        }

        guard previousSource.isEnabled, discoverer != nil else {
            return
        }

        do {
            try await rescanSource(sourceID)
        } catch {
            report(
                error,
                title: "Unable to Scan \(previousSource.displayName)"
            )
        }
    }

    private func restoreSourceAccess(
        _ source: SkillSource,
        state previousState: SourceState?
    ) {
        if previousState == .available {
            let restoredAccess =
                sourceAccess?.beginAccessing(source.directoryURL, for: source.id)
            sourceStates[source.id] = restoredAccess == false ? .unavailable : .available
        } else {
            sourceAccess?.stopAccessing(sourceID: source.id)
            sourceStates[source.id] = previousState
        }
    }

    private func reconcileSelection() {
        let availableIDs = Set(skills.map(\.id))
        selectedSkillIDs.formIntersection(availableIDs)
    }

    private static func sortedSources(_ sources: [SkillSource]) -> [SkillSource] {
        var sourcesByID: [SkillSource.ID: SkillSource] = [:]
        for source in sources {
            sourcesByID[source.id] = source
        }

        return sourcesByID.values.sorted {
            let agentComparison = $0.agent.displayName.localizedStandardCompare(
                $1.agent.displayName
            )
            if agentComparison != .orderedSame {
                return agentComparison == .orderedAscending
            }

            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private static func sortedSkills(_ skills: [AgentSkill]) -> [AgentSkill] {
        var skillsByID: [AgentSkill.ID: AgentSkill] = [:]
        for skill in skills {
            skillsByID[skill.id] = skill
        }

        return skillsByID.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
