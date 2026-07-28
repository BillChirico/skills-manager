import Foundation
import Testing

@testable import SkillsCore

struct CatalogSkillTests {
    @Test("A well-formed catalog skill exposes its page, repository, and install command")
    func exposesDerivedValues() throws {
        let skill = makeSkill()

        #expect(
            skill.pageURL
                == URL(
                    string: "https://skills.sh/twostraws/swift-testing-agent-skill/swift-testing-pro"
                )
        )

        let repository = try #require(skill.githubRepository)
        #expect(repository.owner == "twostraws")
        #expect(repository.name == "swift-testing-agent-skill")

        let command = try #require(skill.installCommand)
        #expect(command.program == "npx")
        #expect(
            command.arguments == [
                "skills",
                "add",
                "https://github.com/twostraws/swift-testing-agent-skill",
                "--skill",
                "swift-testing-pro",
            ]
        )
        #expect(
            command.displayText
                == "npx skills add https://github.com/twostraws/swift-testing-agent-skill --skill swift-testing-pro"
        )
        #expect(skill.isInstallable)
    }

    @Test(
        "A source with a relative path segment is not treated as a repository",
        arguments: ["../etc", "..", "owner/..", "../..", "owner/."]
    )
    func rejectsTraversalSources(source: String) {
        let skill = makeSkill(source: source)

        #expect(skill.githubRepository == nil)
        #expect(skill.repositoryURL == nil)
        #expect(skill.installCommand == nil)
        #expect(skill.isInstallable == false)
    }

    @Test(
        "A source that is not a two-component GitHub path is not installable",
        arguments: [
            "https://gitlab.com/owner/name",
            "owner",
            "owner/name/extra",
            "owner name",
            "owner/na me",
            "owner/",
            "/name",
            "owner/name;rm -rf ~",
            "owner/name`whoami`",
            "owner/$(id)",
        ]
    )
    func rejectsNonRepositorySources(source: String) {
        let skill = makeSkill(source: source)

        #expect(skill.githubRepository == nil)
        #expect(skill.installCommand == nil)
    }

    @Test(
        "A component that reads as a command-line option never reaches the argument vector",
        arguments: ["--force", "-rf"]
    )
    func rejectsOptionLikeComponents(slug: String) {
        let optionSlug = makeSkill(slug: slug)
        #expect(optionSlug.installCommand == nil)

        let optionOwner = makeSkill(source: "\(slug)/name")
        #expect(optionOwner.installCommand == nil)
        // A leading dash is safe inside a URL path, so browsing the source still works.
        #expect(optionOwner.githubRepository != nil)
    }

    @Test("An overlong identifier is rejected")
    func rejectsOverlongIdentifiers() {
        let longName = String(repeating: "a", count: CatalogIdentifier.maximumLength + 1)
        let skill = makeSkill(source: "owner/\(longName)")

        #expect(skill.githubRepository == nil)
        #expect(skill.installCommand == nil)
    }

    @Test(
        "A catalog identifier that is not a safe path yields no page URL",
        arguments: ["owner/../secret", "owner//name", "owner/name/../..", ""]
    )
    func rejectsUnsafePageIdentifiers(id: String) {
        let skill = makeSkill(id: id)

        #expect(skill.pageURL == nil)
    }

    private func makeSkill(
        id: String = "twostraws/swift-testing-agent-skill/swift-testing-pro",
        slug: String = "swift-testing-pro",
        source: String = "twostraws/swift-testing-agent-skill"
    ) -> CatalogSkill {
        CatalogSkill(
            id: id,
            slug: slug,
            name: "Swift Testing Pro",
            source: source,
            installs: 6_900
        )
    }
}
