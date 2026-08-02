import Foundation
import Observation
import SkillsCore

/// Coordinates skills.sh browsing and installation for the Discover Skills scene.
///
/// The model keeps the leaderboard and the search results apart so clearing the search
/// field falls back to the cached top downloads instead of an empty screen or a refetch.
@MainActor
@Observable
final class SkillCatalogModel {
    private enum CatalogInstallError: LocalizedError {
        case invalidCatalogEntry
        case installInProgress

        var errorDescription: String? {
            switch self {
            case .invalidCatalogEntry:
                "This skill's catalog data cannot be installed safely."
            case .installInProgress:
                "Another skill installation is already in progress."
            }
        }
    }

    /// What one configured directory got out of a multi-directory install.
    struct InstallOutcome: Identifiable, Hashable {
        let sourceID: SkillSource.ID
        let sourceName: String
        let installedURL: URL?
        let errorMessage: String?

        var id: SkillSource.ID { sourceID }

        var didSucceed: Bool { installedURL != nil }
    }

    /// The shortest query skills.sh will accept.
    static let minimumQueryLength = 2

    var query = "" {
        didSet {
            guard query != oldValue else {
                return
            }

            activeSearchRequestID = nil
            searchResults = []
            searchErrorMessage = nil
            isSearching = trimmedQuery.count >= Self.minimumQueryLength
        }
    }
    private(set) var searchResults: [CatalogSkill] = []
    private(set) var topDownloads: [CatalogSkill] = []
    private(set) var isSearching = false
    private(set) var isLoadingTopDownloads = false
    private(set) var searchErrorMessage: String?
    private(set) var topDownloadsErrorMessage: String?
    private(set) var installingSkillID: CatalogSkill.ID?

    @ObservationIgnored private let catalog: any SkillCatalogSearching
    @ObservationIgnored private let skillManager: any SkillManaging
    @ObservationIgnored private var hasRequestedTopDownloads = false
    @ObservationIgnored private var activeSearchRequestID: UUID?
    @ObservationIgnored private var topDownloadsTask: Task<Void, Never>?

    init(
        catalog: any SkillCatalogSearching,
        skillManager: any SkillManaging
    ) {
        self.catalog = catalog
        self.skillManager = skillManager
    }

    /// Whether the leaderboard is standing in for search results.
    var isShowingTopDownloads: Bool {
        trimmedQuery.count < Self.minimumQueryLength
    }

    /// What the result list should render, download-ranked in both modes.
    var results: [CatalogSkill] {
        isShowingTopDownloads ? topDownloads : searchResults
    }

    var isLoading: Bool {
        isShowingTopDownloads ? isLoadingTopDownloads : isSearching
    }

    var errorMessage: String? {
        isShowingTopDownloads ? topDownloadsErrorMessage : searchErrorMessage
    }

    /// Loads the leaderboard once per session so reopening Discover is instant.
    func loadTopDownloads() async {
        if let topDownloadsTask {
            await topDownloadsTask.value
            return
        }

        guard hasRequestedTopDownloads == false else {
            return
        }

        await requestTopDownloads()
    }

    /// Reloads the leaderboard, which is what the failure state's retry action calls.
    func refreshTopDownloads() async {
        await requestTopDownloads()
    }

    /// Starts one request or joins the request already warming the session cache.
    private func requestTopDownloads() async {
        if let topDownloadsTask {
            await topDownloadsTask.value
            return
        }

        hasRequestedTopDownloads = true
        isLoadingTopDownloads = true
        topDownloadsErrorMessage = nil

        let request = Task { @MainActor in
            defer {
                isLoadingTopDownloads = false
            }

            do {
                let page = try await catalog.topDownloads(page: 0)
                topDownloads = CatalogSkillSorter.byDownloads(page.skills)
            } catch is CancellationError {
                // Let a future appearance retry if the loader itself cancels the request.
                hasRequestedTopDownloads = false
            } catch {
                topDownloads = []
                topDownloadsErrorMessage = error.localizedDescription
            }
        }

        topDownloadsTask = request
        await request.value
        topDownloadsTask = nil
    }

    func search() async {
        let submittedQuery = trimmedQuery
        guard submittedQuery.count >= Self.minimumQueryLength else {
            activeSearchRequestID = nil
            searchResults = []
            searchErrorMessage = nil
            isSearching = false
            return
        }

        let requestID = UUID()
        activeSearchRequestID = requestID
        searchResults = []
        isSearching = true
        searchErrorMessage = nil
        defer {
            if activeSearchRequestID == requestID {
                activeSearchRequestID = nil
                isSearching = false
            }
        }

        do {
            let matches = try await catalog.search(query: submittedQuery, limit: 100)
            guard
                Task.isCancelled == false,
                trimmedQuery == submittedQuery,
                activeSearchRequestID == requestID
            else {
                return
            }

            searchResults = CatalogSkillSorter.byDownloads(matches)
        } catch is CancellationError {
            return
        } catch {
            guard
                Task.isCancelled == false,
                activeSearchRequestID == requestID
            else {
                return
            }

            searchResults = []
            searchErrorMessage = error.localizedDescription
        }
    }

    /// Installs a skill into each selected directory through the official skills CLI.
    ///
    /// One directory's failure does not stop the others, so the caller always receives an
    /// outcome per destination rather than a single thrown error.
    ///
    /// - Parameters:
    ///   - skill: The catalog skill to install.
    ///   - destinations: The configured directories the user selected.
    /// - Returns: One outcome per destination, in the order the destinations were given.
    func install(
        _ skill: CatalogSkill,
        into destinations: [SkillSource]
    ) async -> [InstallOutcome] {
        guard destinations.isEmpty == false else {
            return []
        }

        guard skill.isInstallable else {
            return destinations.map {
                InstallOutcome(
                    sourceID: $0.id,
                    sourceName: $0.displayName,
                    installedURL: nil,
                    errorMessage: CatalogInstallError.invalidCatalogEntry.localizedDescription
                )
            }
        }

        guard installingSkillID == nil else {
            return destinations.map {
                InstallOutcome(
                    sourceID: $0.id,
                    sourceName: $0.displayName,
                    installedURL: nil,
                    errorMessage: CatalogInstallError.installInProgress.localizedDescription
                )
            }
        }

        installingSkillID = skill.id
        defer {
            installingSkillID = nil
        }

        var outcomes: [InstallOutcome] = []
        outcomes.reserveCapacity(destinations.count)

        for destination in destinations {
            do {
                let installedURL = try await skillManager.install(skill, into: destination)
                outcomes.append(
                    InstallOutcome(
                        sourceID: destination.id,
                        sourceName: destination.displayName,
                        installedURL: installedURL,
                        errorMessage: nil
                    )
                )
            } catch {
                outcomes.append(
                    InstallOutcome(
                        sourceID: destination.id,
                        sourceName: destination.displayName,
                        installedURL: nil,
                        errorMessage: error.localizedDescription
                    )
                )
            }
        }

        return outcomes
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
