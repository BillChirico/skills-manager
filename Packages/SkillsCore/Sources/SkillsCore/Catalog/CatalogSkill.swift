import Foundation

public struct CatalogSkill: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let slug: String
    public let name: String
    public let source: String
    public let installs: Int

    public init(
        id: String,
        slug: String,
        name: String,
        source: String,
        installs: Int
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.source = source
        self.installs = installs
    }

    public var pageURL: URL? {
        URL(string: "https://skills.sh")?.appending(path: id)
    }

    public var githubRepository: (owner: String, name: String)? {
        let components = source.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 2 else {
            return nil
        }

        return (String(components[0]), String(components[1]))
    }
}

public protocol SkillCatalogSearching: Sendable {
    func search(query: String, limit: Int) async throws -> [CatalogSkill]
}
