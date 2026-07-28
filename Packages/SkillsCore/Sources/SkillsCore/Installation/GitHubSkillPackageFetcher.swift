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

    private static let maximumCommitResponseSize = 1_024
    private static let maximumTreeResponseSize = 8 * 1_024 * 1_024
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

        let commitSHA = try await resolveCommitSHA(
            owner: repository.owner,
            repository: repository.name
        )
        let tree = try await fetchTree(
            owner: repository.owner,
            repository: repository.name,
            commitSHA: commitSHA
        )
        guard tree.truncated == false else {
            throw SkillPackageFetchError.packageTooLarge
        }

        // Tree paths are remote input and end up in a raw.githubusercontent URL, so a
        // relative segment is dropped before it can steer the request off the repository.
        let treeItems = tree.tree.filter { Self.isSafeRepositoryPath($0.path) }
        let manifestItems = treeItems.filter {
            $0.type == "blob" && $0.path.split(separator: "/").last == "SKILL.md"
        }
        let matchingManifests =
            manifestItems.filter {
                let components = $0.path.split(separator: "/")
                return components.dropLast().last.map(String.init) == skill.slug
            }
        let matchingManifest: TreeItem?
        if matchingManifests.count == 1 {
            matchingManifest = matchingManifests[0]
        } else if matchingManifests.isEmpty,
            manifestItems.count == 1,
            manifestItems[0].path == "SKILL.md",
            repository.name == skill.slug
        {
            matchingManifest = manifestItems[0]
        } else {
            matchingManifest = nil
        }
        guard let matchingManifest else {
            throw SkillPackageFetchError.skillNotFound
        }

        let manifestComponents = matchingManifest.path.split(separator: "/")
        let directoryPrefix = manifestComponents.dropLast().joined(separator: "/")
        let packageItems =
            treeItems
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
            let remainingPackageSize = Self.maximumPackageSize - totalSize
            let response = try await fetchFile(
                owner: repository.owner,
                repository: repository.name,
                commitSHA: commitSHA,
                maximumBytes: remainingPackageSize,
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

    /// Whether a repository-relative path can be appended to a URL and written to disk
    /// without escaping its own directory.
    private static func isSafeRepositoryPath(_ path: String) -> Bool {
        guard path.hasPrefix("/") == false, path.contains("\\") == false else {
            return false
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.isEmpty == false
            && components.allSatisfy { $0.isEmpty == false && $0 != "." && $0 != ".." }
    }

    /// Resolves the symbolic default-branch `HEAD` to one immutable commit. GitHub's SHA
    /// media type avoids receiving the much larger commit JSON representation.
    private func resolveCommitSHA(
        owner: String,
        repository: String
    ) async throws -> String {
        let endpoint =
            apiBaseURL
            .appending(path: "repos")
            .appending(path: owner)
            .appending(path: repository)
            .appending(path: "commits")
            .appending(path: "HEAD")
        var request = githubAPIRequest(url: endpoint)
        request.setValue("application/vnd.github.sha", forHTTPHeaderField: "Accept")

        let response = try await load(
            request,
            maximumBytes: Self.maximumCommitResponseSize
        )
        guard response.statusCode == 200 else {
            throw SkillPackageFetchError.repositoryUnavailable
        }

        let sha = String(decoding: response.data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            sha.count == 40,
            sha.allSatisfy(\.isHexDigit)
        else {
            throw SkillPackageFetchError.repositoryUnavailable
        }

        return sha.lowercased()
    }

    private func fetchTree(
        owner: String,
        repository: String,
        commitSHA: String
    ) async throws -> TreeResponse {
        let endpoint =
            apiBaseURL
            .appending(path: "repos")
            .appending(path: owner)
            .appending(path: repository)
            .appending(path: "git")
            .appending(path: "trees")
            .appending(path: commitSHA)
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "recursive", value: "1")]
        guard let url = components?.url else {
            throw SkillPackageFetchError.repositoryUnavailable
        }

        let response = try await load(
            githubAPIRequest(url: url),
            maximumBytes: Self.maximumTreeResponseSize
        )
        guard response.statusCode == 200 else {
            throw SkillPackageFetchError.repositoryUnavailable
        }

        return try JSONDecoder().decode(TreeResponse.self, from: response.data)
    }

    private func fetchFile(
        owner: String,
        repository: String,
        commitSHA: String,
        maximumBytes: Int,
        path: String
    ) async throws -> HTTPDataResponse {
        var url =
            rawContentBaseURL
            .appending(path: owner)
            .appending(path: repository)
            .appending(path: commitSHA)
        for component in path.split(separator: "/") {
            url.append(path: String(component))
        }

        var request = URLRequest(url: url)
        request.setValue("SkillsManager/0.1", forHTTPHeaderField: "User-Agent")
        let response = try await load(request, maximumBytes: maximumBytes)
        guard response.statusCode == 200 else {
            throw SkillPackageFetchError.repositoryUnavailable
        }

        return response
    }

    private func githubAPIRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SkillsManager/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func load(
        _ request: URLRequest,
        maximumBytes: Int
    ) async throws -> HTTPDataResponse {
        do {
            let response = try await dataLoader.data(
                for: request,
                maximumBytes: maximumBytes
            )
            guard response.data.count <= maximumBytes else {
                throw SkillPackageFetchError.packageTooLarge
            }
            return response
        } catch HTTPDataLoadingError.responseTooLarge {
            throw SkillPackageFetchError.packageTooLarge
        }
    }
}
