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

    var query = ""
    private(set) var searchResults: [CatalogSkill] = []
    private(set) var topDownloads: [CatalogSkill] = []
    private(set) var isSearching = false
    private(set) var isLoadingTopDownloads = false
    private(set) var searchErrorMessage: String?
    private(set) var topDownloadsErrorMessage: String?
    private(set) var installingSkillID: CatalogSkill.ID?

    @ObservationIgnored private let catalog: any SkillCatalogSearching
    @ObservationIgnored private let packageFetcher: any SkillPackageFetching
    @ObservationIgnored private let packageInstaller: any SkillPackageInstalling
    @ObservationIgnored private var hasRequestedTopDownloads = false

    init(
        catalog: any SkillCatalogSearching,
        packageFetcher: any SkillPackageFetching,
        packageInstaller: any SkillPackageInstalling
    ) {
        self.catalog = catalog
        self.packageFetcher = packageFetcher
        self.packageInstaller = packageInstaller
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
        guard hasRequestedTopDownloads == false else {
            return
        }

        await refreshTopDownloads()
    }

    /// Reloads the leaderboard, which is what the failure state's retry action calls.
    func refreshTopDownloads() async {
        hasRequestedTopDownloads = true
        isLoadingTopDownloads = true
        topDownloadsErrorMessage = nil

        do {
            let page = try await catalog.topDownloads(page: 0)
            guard Task.isCancelled == false else {
                isLoadingTopDownloads = false
                return
            }

            topDownloads = CatalogSkillSorter.byDownloads(page.skills)
            isLoadingTopDownloads = false
        } catch is CancellationError {
            // A cancelled load never reached the catalog, so let the next appearance retry.
            hasRequestedTopDownloads = false
            isLoadingTopDownloads = false
        } catch {
            guard Task.isCancelled == false else {
                isLoadingTopDownloads = false
                return
            }

            topDownloads = []
            topDownloadsErrorMessage = error.localizedDescription
            isLoadingTopDownloads = false
        }
    }

    func search() async {
        let submittedQuery = trimmedQuery
        guard submittedQuery.count >= Self.minimumQueryLength else {
            searchResults = []
            searchErrorMessage = nil
            isSearching = false
            return
        }

        isSearching = true
        searchErrorMessage = nil

        do {
            let matches = try await catalog.search(query: submittedQuery, limit: 100)
            guard Task.isCancelled == false, trimmedQuery == submittedQuery else {
                return
            }

            searchResults = CatalogSkillSorter.byDownloads(matches)
            isSearching = false
        } catch is CancellationError {
            isSearching = false
        } catch {
            guard Task.isCancelled == false else {
                isSearching = false
                return
            }

            searchResults = []
            searchErrorMessage = error.localizedDescription
            isSearching = false
        }
    }

    /// Downloads a skill once and copies it into each selected directory.
    ///
    /// The package is fetched a single time no matter how many directories are selected,
    /// and one directory's failure does not stop the others, so the caller always receives
    /// an outcome per destination rather than a single thrown error.
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

        installingSkillID = skill.id
        defer {
            installingSkillID = nil
        }

        let package: SkillPackage
        do {
            package = try await packageFetcher.fetchPackage(for: skill)
        } catch {
            return destinations.map {
                InstallOutcome(
                    sourceID: $0.id,
                    sourceName: $0.displayName,
                    installedURL: nil,
                    errorMessage: error.localizedDescription
                )
            }
        }

        var outcomes: [InstallOutcome] = []
        outcomes.reserveCapacity(destinations.count)

        for destination in destinations {
            do {
                let installedURL = try await write(
                    package,
                    directoryName: skill.slug,
                    into: destination.directoryURL
                )
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

    private func write(
        _ package: SkillPackage,
        directoryName: String,
        into directoryURL: URL
    ) async throws -> URL {
        let packageInstaller = packageInstaller
        return try await Task.detached(priority: .userInitiated) {
            try packageInstaller.install(
                package,
                directoryName: directoryName,
                into: directoryURL
            )
        }.value
    }
}
