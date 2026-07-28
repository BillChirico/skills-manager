import Foundation

public enum SkillsShCatalogError: LocalizedError, Equatable {
    case invalidEndpoint
    case rateLimited
    case serviceUnavailable
    case requestFailed(statusCode: Int)
    case responseTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "Skills Manager could not build the skills.sh request."
        case .rateLimited:
            "skills.sh is receiving too many requests. Try again in a moment."
        case .serviceUnavailable:
            "skills.sh is temporarily unavailable. Try again in a moment."
        case .requestFailed(let statusCode):
            "skills.sh returned an unexpected response (\(statusCode))."
        case .responseTooLarge:
            "skills.sh returned more data than Skills Manager will read."
        }
    }
}

public struct SkillsShCatalogClient: SkillCatalogSearching {
    private struct SearchResponse: Decodable {
        let skills: [SearchResult]
    }

    private struct SearchResult: Decodable {
        let id: String
        let skillId: String
        let name: String
        let installs: Int
        let source: String
    }

    private struct LeaderboardResponse: Decodable {
        let skills: [LeaderboardResult]
        let hasMore: Bool
    }

    private struct LeaderboardResult: Decodable {
        let skillId: String
        let name: String?
        let installs: Int
        let source: String
    }

    /// The leaderboard's own page size. A larger payload is a server change or an
    /// unexpected response, and either way the extra entries are dropped.
    private static let maximumPageSize = 200

    /// A ceiling on the body Skills Manager will decode, so a runaway response cannot
    /// exhaust memory in the app process.
    private static let maximumResponseSize = 8 * 1_024 * 1_024

    private let baseURL: URL
    private let dataLoader: any HTTPDataLoading

    public init(
        baseURL: URL = URL(string: "https://skills.sh")!,
        dataLoader: any HTTPDataLoading = URLSessionHTTPDataLoader()
    ) {
        self.baseURL = baseURL
        self.dataLoader = dataLoader
    }

    public func search(query: String, limit: Int = 50) async throws -> [CatalogSkill] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            return []
        }

        let requestedLimit = min(max(limit, 1), 100)
        var components = URLComponents(
            url: baseURL.appending(path: "api/search"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(requestedLimit)),
        ]
        guard let url = components?.url else {
            throw SkillsShCatalogError.invalidEndpoint
        }

        let data = try await validatedData(for: url)
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.skills.prefix(requestedLimit).compactMap {
            catalogSkill(
                id: $0.id,
                slug: $0.skillId,
                name: $0.name,
                source: $0.source,
                installs: $0.installs
            )
        }
    }

    public func topDownloads(page: Int) async throws -> CatalogPage {
        guard page >= 0 else {
            throw SkillsShCatalogError.invalidEndpoint
        }

        let url =
            baseURL
            .appending(path: "api/skills/all-time")
            .appending(path: String(page))

        let data = try await validatedData(for: url)
        let decoded = try JSONDecoder().decode(LeaderboardResponse.self, from: data)
        let skills = decoded.skills.prefix(Self.maximumPageSize).compactMap { result in
            catalogSkill(
                id: nil,
                slug: result.skillId,
                name: result.name,
                source: result.source,
                installs: result.installs
            )
        }

        return CatalogPage(skills: skills, page: page, hasMore: decoded.hasMore)
    }

    /// Builds a domain value, dropping an entry the catalog sent without the fields
    /// Skills Manager needs to identify it.
    ///
    /// The leaderboard endpoint omits `id`, so it is composed from `source` and `skillId`
    /// the same way the search endpoint reports it.
    private func catalogSkill(
        id: String?,
        slug: String,
        name: String?,
        source: String,
        installs: Int
    ) -> CatalogSkill? {
        let slug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard slug.isEmpty == false, source.isEmpty == false else {
            return nil
        }

        let identifier = nonEmpty(id) ?? "\(source)/\(slug)"

        return CatalogSkill(
            id: identifier,
            slug: slug,
            name: nonEmpty(name) ?? slug,
            source: source,
            installs: max(installs, 0)
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            value.isEmpty == false
        else {
            return nil
        }

        return value
    }

    private func validatedData(for url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await dataLoader.data(for: request)

        switch response.statusCode {
        case 200:
            break
        case 429:
            throw SkillsShCatalogError.rateLimited
        case 503:
            throw SkillsShCatalogError.serviceUnavailable
        default:
            throw SkillsShCatalogError.requestFailed(statusCode: response.statusCode)
        }

        guard response.data.count <= Self.maximumResponseSize else {
            throw SkillsShCatalogError.responseTooLarge
        }

        return response.data
    }
}
