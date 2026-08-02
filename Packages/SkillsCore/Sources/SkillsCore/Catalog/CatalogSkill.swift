import Foundation

/// A skill published on skills.sh.
///
/// Every stored property is remote input. The derived URLs and the install command are
/// therefore rebuilt from validated components instead of being interpolated directly,
/// and they return `nil` when the catalog sends something Skills Manager will not act on.
public struct CatalogSkill: Identifiable, Hashable, Codable, Sendable {
    private static let pageBaseURL = URL(string: "https://skills.sh")!
    private static let repositoryBaseURL = URL(string: "https://github.com")!

    public let id: String
    public let slug: String
    public let name: String
    public let source: String

    /// The catalog's all-time download count, which the UI presents as "Downloads".
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

    /// The skill's page on skills.sh, or `nil` when the catalog identifier is not a safe path.
    public var pageURL: URL? {
        let components = id.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard
            components.isEmpty == false,
            let validated = validatedPathComponents(components)
        else {
            return nil
        }

        return validated.reduce(Self.pageBaseURL) { $0.appending(path: $1) }
    }

    /// The backing GitHub repository, or `nil` when the source is not `owner/name`.
    public var githubRepository: (owner: String, name: String)? {
        let components = source.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard
            components.count == 2,
            let validated = validatedPathComponents(components)
        else {
            return nil
        }

        return (validated[0], validated[1])
    }

    /// The repository URL that skills.sh prints in the skill's install command.
    public var repositoryURL: URL? {
        guard let repository = githubRepository else {
            return nil
        }

        return
            Self.repositoryBaseURL
            .appending(path: repository.owner)
            .appending(path: repository.name)
    }

    /// The install command shown at the top of the skill's skills.sh page.
    ///
    /// `nil` when any component fails validation, in which case the skill stays
    /// browsable but is not offered for installation.
    public var installCommand: SkillInstallCommand? {
        guard
            let repository = githubRepository,
            CatalogIdentifier.validatedArgument(repository.owner) != nil,
            CatalogIdentifier.validatedArgument(repository.name) != nil,
            let slug = CatalogIdentifier.validatedInstallationDirectoryName(slug),
            let repositoryURL
        else {
            return nil
        }

        return SkillInstallCommand(
            program: "npx",
            arguments: ["skills", "add", repositoryURL.absoluteString, "--skill", slug],
            repositoryURL: repositoryURL
        )
    }

    /// Whether Skills Manager can install this skill into a configured directory.
    public var isInstallable: Bool {
        installCommand != nil
    }

    private func validatedPathComponents(_ components: [String]) -> [String]? {
        var validated: [String] = []
        validated.reserveCapacity(components.count)

        for component in components {
            guard let component = CatalogIdentifier.validatedPathComponent(component) else {
                return nil
            }
            validated.append(component)
        }

        return validated
    }
}
