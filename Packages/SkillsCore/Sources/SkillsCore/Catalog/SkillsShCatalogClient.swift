import Foundation

public enum SkillsShCatalogError: LocalizedError, Equatable {
    case invalidEndpoint
    case rateLimited
    case serviceUnavailable
    case requestFailed(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "Skills Manager could not build the skills.sh search request."
        case .rateLimited:
            "skills.sh is receiving too many requests. Try again in a moment."
        case .serviceUnavailable:
            "skills.sh is temporarily unavailable. Try again in a moment."
        case .requestFailed(let statusCode):
            "skills.sh returned an unexpected response (\(statusCode))."
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

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: response.data)
        return decoded.skills.map {
            CatalogSkill(
                id: $0.id,
                slug: $0.skillId,
                name: $0.name,
                source: $0.source,
                installs: $0.installs
            )
        }
    }
}
