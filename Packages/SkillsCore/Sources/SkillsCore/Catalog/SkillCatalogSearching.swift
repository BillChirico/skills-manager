import Foundation

/// One page of a catalog listing.
public struct CatalogPage: Hashable, Sendable {
    public let skills: [CatalogSkill]
    public let page: Int
    public let hasMore: Bool

    public init(skills: [CatalogSkill], page: Int, hasMore: Bool) {
        self.skills = skills
        self.page = page
        self.hasMore = hasMore
    }
}

/// Read access to a remote skill catalog.
public protocol SkillCatalogSearching: Sendable {
    /// Searches the catalog. Callers receive results in the catalog's own order.
    func search(query: String, limit: Int) async throws -> [CatalogSkill]

    /// Lists the catalog's most downloaded skills, highest first.
    ///
    /// - Parameter page: A zero-based page index. Page `0` is the top of the leaderboard.
    func topDownloads(page: Int) async throws -> CatalogPage
}
