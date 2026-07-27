import Foundation
import Observation
import SkillsCore

@MainActor
@Observable
final class SkillCatalogModel {
    var query = ""
    private(set) var results: [CatalogSkill] = []
    private(set) var isSearching = false
    private(set) var searchErrorMessage: String?
    private(set) var installingSkillID: CatalogSkill.ID?

    @ObservationIgnored private let catalog: any SkillCatalogSearching
    @ObservationIgnored private let packageFetcher: any SkillPackageFetching
    @ObservationIgnored private let packageInstaller: any SkillPackageInstalling

    init(
        catalog: any SkillCatalogSearching,
        packageFetcher: any SkillPackageFetching,
        packageInstaller: any SkillPackageInstalling
    ) {
        self.catalog = catalog
        self.packageFetcher = packageFetcher
        self.packageInstaller = packageInstaller
    }

    func search() async {
        let submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard submittedQuery.count >= 2 else {
            results = []
            searchErrorMessage = nil
            isSearching = false
            return
        }

        isSearching = true
        searchErrorMessage = nil

        do {
            let searchResults = try await catalog.search(query: submittedQuery, limit: 100)
            guard
                Task.isCancelled == false,
                query.trimmingCharacters(in: .whitespacesAndNewlines) == submittedQuery
            else {
                return
            }

            results = searchResults
            isSearching = false
        } catch is CancellationError {
            isSearching = false
        } catch {
            guard Task.isCancelled == false else {
                isSearching = false
                return
            }

            results = []
            searchErrorMessage = error.localizedDescription
            isSearching = false
        }
    }

    func install(_ skill: CatalogSkill, into directoryURL: URL) async throws -> URL {
        installingSkillID = skill.id
        defer {
            installingSkillID = nil
        }

        let package = try await packageFetcher.fetchPackage(for: skill)
        let packageInstaller = packageInstaller
        return try await Task.detached(priority: .userInitiated) {
            try packageInstaller.install(
                package,
                directoryName: skill.slug,
                into: directoryURL
            )
        }.value
    }
}
