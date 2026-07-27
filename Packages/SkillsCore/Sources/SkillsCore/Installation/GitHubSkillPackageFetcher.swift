import Foundation

public enum SkillPackageFetchError: LocalizedError, Equatable {
    case unsupportedSource
    case repositoryUnavailable
    case skillNotFound
    case packageTooLarge

    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "This skill source is not a GitHub repository and cannot be installed yet."
        case .repositoryUnavailable:
            "The skill repository could not be downloaded."
        case .skillNotFound:
            "The selected skill could not be found in its source repository."
        case .packageTooLarge:
            "The selected skill is too large to install safely."
        }
    }
}

public struct GitHubSkillPackageFetcher: SkillPackageFetching {
    private struct TreeResponse: Decodable {
        let tree: [TreeItem]
        let truncated: Bool
    }

    private struct TreeItem: Decodable {
        let path: String
        let mode: String
        let type: String
    }

    private static let maximumFileCount = 200
    private static let maximumPackageSize = 10 * 1_024 * 1_024

    private let dataLoader: any HTTPDataLoading
    private let apiBaseURL: URL
    private let rawContentBaseURL: URL

    public init(
        dataLoader: any HTTPDataLoading = URLSessionHTTPDataLoader(),
        apiBaseURL: URL = URL(string: "https://api.github.com")!,
        rawContentBaseURL: URL = URL(string: "https://raw.githubusercontent.com")!
    ) {
        self.dataLoader = dataLoader
        self.apiBaseURL = apiBaseURL
        self.rawContentBaseURL = rawContentBaseURL
    }

    public func fetchPackage(for skill: CatalogSkill) async throws -> SkillPackage {
        guard let repository = skill.githubRepository else {
            throw SkillPackageFetchError.unsupportedSource
        }

        let tree = try await fetchTree(owner: repository.owner, repository: repository.name)
        guard tree.truncated == false else {
            throw SkillPackageFetchError.packageTooLarge
        }

        let manifestItems = tree.tree.filter {
            $0.type == "blob" && $0.path.split(separator: "/").last == "SKILL.md"
        }
        let matchingManifest =
            manifestItems.first {
                let components = $0.path.split(separator: "/")
                return components.dropLast().last.map(String.init) == skill.slug
            }
            ?? manifestItems.first { $0.path == "SKILL.md" }
        guard let matchingManifest else {
            throw SkillPackageFetchError.skillNotFound
        }

        let manifestComponents = matchingManifest.path.split(separator: "/")
        let directoryPrefix = manifestComponents.dropLast().joined(separator: "/")
        let packageItems = tree.tree
            .filter { item in
                guard item.type == "blob" else {
                    return false
                }

                if directoryPrefix.isEmpty {
                    return true
                }

                return item.path.hasPrefix("\(directoryPrefix)/")
            }
            .sorted { $0.path < $1.path }

        guard packageItems.count <= Self.maximumFileCount else {
            throw SkillPackageFetchError.packageTooLarge
        }

        var totalSize = 0
        var files: [SkillPackageFile] = []
        files.reserveCapacity(packageItems.count)

        for item in packageItems {
            let response = try await fetchFile(
                owner: repository.owner,
                repository: repository.name,
                path: item.path
            )
            totalSize += response.data.count
            guard totalSize <= Self.maximumPackageSize else {
                throw SkillPackageFetchError.packageTooLarge
            }

            let relativePath =
                directoryPrefix.isEmpty
                ? item.path
                : String(item.path.dropFirst(directoryPrefix.count + 1))
            files.append(
                SkillPackageFile(path: relativePath, contents: response.data)
            )
        }

        guard files.contains(where: { $0.path == "SKILL.md" }) else {
            throw SkillPackageFetchError.skillNotFound
        }

        return SkillPackage(skillID: skill.id, files: files)
    }

    private func fetchTree(owner: String, repository: String) async throws -> TreeResponse {
        let endpoint =
            apiBaseURL
            .appending(path: "repos")
            .appending(path: owner)
            .appending(path: repository)
            .appending(path: "git/trees/HEAD")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "recursive", value: "1")]
        guard let url = components?.url else {
            throw SkillPackageFetchError.repositoryUnavailable
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SkillsManager/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let response = try await dataLoader.data(for: request)
        guard response.statusCode == 200 else {
            throw SkillPackageFetchError.repositoryUnavailable
        }

        return try JSONDecoder().decode(TreeResponse.self, from: response.data)
    }

    private func fetchFile(
        owner: String,
        repository: String,
        path: String
    ) async throws -> HTTPDataResponse {
        var url =
            rawContentBaseURL
            .appending(path: owner)
            .appending(path: repository)
            .appending(path: "HEAD")
        for component in path.split(separator: "/") {
            url.append(path: String(component))
        }

        var request = URLRequest(url: url)
        request.setValue("SkillsManager/0.1", forHTTPHeaderField: "User-Agent")
        let response = try await dataLoader.data(for: request)
        guard response.statusCode == 200 else {
            throw SkillPackageFetchError.repositoryUnavailable
        }

        return response
    }
}
