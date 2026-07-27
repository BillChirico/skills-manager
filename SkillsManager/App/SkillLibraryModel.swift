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

    private enum SourceRecoveryError: LocalizedError {
        case accessDenied

        var errorDescription: String? {
            "Skills Manager could not access the selected directory."
        }
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

    @ObservationIgnored private let sourceStore: (any SkillSourceStore)?
    @ObservationIgnored private let discoverer: (any SkillDiscovering)?
    @ObservationIgnored private let bookmarker: (any SkillSourceBookmarking)?
    @ObservationIgnored private let sourceAccess: (any SkillSourceAccessing)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var hasRestoredSources = false

    init(
        sources: [SkillSource] = [],
        skills: [AgentSkill] = [],
        sourceStore: (any SkillSourceStore)? = nil,
        discoverer: (any SkillDiscovering)? = nil,
        bookmarker: (any SkillSourceBookmarking)? = nil,
        sourceAccess: (any SkillSourceAccessing)? = nil,
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

    var canSearchAllSkills: Bool {
        let hasQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return hasQuery
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

        let source = SkillSource(
            name: normalizedURL.lastPathComponent,
            directoryURL: normalizedURL,
            agent: agent,
            bookmarkData: try bookmarker?.makeBookmark(for: normalizedURL)
        )
        let accessGranted =
            sourceAccess?.beginAccessing(normalizedURL, for: source.id) ?? true

        sources.append(source)
        sources = Self.sortedSources(sources)
        sourceStates[source.id] = accessGranted ? .available : .unavailable
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

        if accessGranted, discoverer != nil {
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
            sources[index].isEnabled = previousValue
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

    func updateSkills(_ skillIDs: Set<AgentSkill.ID>) {
        for index in skills.indices where skillIDs.contains(skills[index].id) {
            guard let availableVersion = skills[index].availableVersion else {
                continue
            }
            skills[index].installedVersion = availableVersion
        }
    }

    func setSkillsEnabled(_ isEnabled: Bool, skillIDs: Set<AgentSkill.ID>) {
        for index in skills.indices where skillIDs.contains(skills[index].id) {
            skills[index].isEnabled = isEnabled
        }
    }

    func removeSkills(_ skillIDs: Set<AgentSkill.ID>) {
        skills.removeAll { skillIDs.contains($0.id) }
        selectedSkillIDs.subtract(skillIDs)
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
        let bookmarkData = try bookmarker?.makeBookmark(for: directoryURL)
        let accessGranted =
            sourceAccess?.beginAccessing(directoryURL, for: sourceID) ?? true

        guard accessGranted else {
            if previousState == .available,
                sourceAccess?.beginAccessing(previousSource.directoryURL, for: sourceID) == true
            {
                sourceStates[sourceID] = .available
            } else {
                sourceStates[sourceID] = .unavailable
            }
            throw SourceRecoveryError.accessDenied
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

            if previousState == .available {
                let restoredAccess =
                    sourceAccess?.beginAccessing(previousSource.directoryURL, for: sourceID)
                sourceStates[sourceID] = restoredAccess == false ? .unavailable : previousState
            } else {
                sourceAccess?.stopAccessing(sourceID: sourceID)
                sourceStates[sourceID] = previousState
            }
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
