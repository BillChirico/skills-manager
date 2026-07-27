import Foundation
import SkillsCore
import Testing

@testable import SkillsManager

@MainActor
struct SkillLibraryScopeTitleTests {
    @Test("The scope title names the selected smart group")
    func namesSmartGroups() {
        let model = SkillLibraryModel()

        model.sidebarSelection = .allSkills
        #expect(model.scopeTitle == "All Skills")

        model.sidebarSelection = .updatesAvailable
        #expect(model.scopeTitle == "Updates Available")

        model.sidebarSelection = .disabled
        #expect(model.scopeTitle == "Disabled")

        model.sidebarSelection = .recentlyAdded
        #expect(model.scopeTitle == "Recently Added")
    }

    @Test("The scope title names the selected directory")
    func namesSelectedDirectory() {
        let source = SkillSource(
            name: "Claude Skills",
            directoryURL: URL(filePath: "/skills/claude"),
            agent: .claudeCode
        )
        let model = SkillLibraryModel(sources: [source])

        model.sidebarSelection = .source(source.id)

        #expect(model.scopeTitle == "Claude Skills")
    }

    @Test("The scope title falls back to the app name for an unknown directory")
    func fallsBackForUnknownDirectory() {
        let model = SkillLibraryModel()

        model.sidebarSelection = .source(UUID())

        #expect(model.scopeTitle == "Skills Manager")
    }

    @Test("The scope subtitle counts the skills in view")
    func countsSkillsInView() {
        let source = SkillSource(
            name: "Claude Skills",
            directoryURL: URL(filePath: "/skills/claude"),
            agent: .claudeCode
        )
        let model = SkillLibraryModel(
            sources: [source],
            skills: [
                AgentSkill(
                    name: "Alpha",
                    summary: "First",
                    directoryURL: source.directoryURL.appending(path: "alpha"),
                    sourceID: source.id
                ),
                AgentSkill(
                    name: "Beta",
                    summary: "Second",
                    directoryURL: source.directoryURL.appending(path: "beta"),
                    sourceID: source.id
                ),
            ]
        )

        #expect(model.scopeSubtitle == "2 skills")
    }

    @Test("The scope subtitle uses the singular noun for one skill")
    func usesSingularNoun() {
        let source = SkillSource(
            name: "Claude Skills",
            directoryURL: URL(filePath: "/skills/claude"),
            agent: .claudeCode
        )
        let model = SkillLibraryModel(
            sources: [source],
            skills: [
                AgentSkill(
                    name: "Alpha",
                    summary: "First",
                    directoryURL: source.directoryURL.appending(path: "alpha"),
                    sourceID: source.id
                )
            ]
        )

        #expect(model.scopeSubtitle == "1 skill")
    }

    @Test("The scope subtitle reads as empty when nothing is in view")
    func describesEmptyScope() {
        let model = SkillLibraryModel()

        #expect(model.scopeSubtitle == "No skills")
    }

    @Test("The scope subtitle reports how many skills match the search")
    func reportsSearchMatches() {
        let source = SkillSource(
            name: "Claude Skills",
            directoryURL: URL(filePath: "/skills/claude"),
            agent: .claudeCode
        )
        let model = SkillLibraryModel(
            sources: [source],
            skills: [
                AgentSkill(
                    name: "Alpha",
                    summary: "First",
                    directoryURL: source.directoryURL.appending(path: "alpha"),
                    sourceID: source.id
                ),
                AgentSkill(
                    name: "Beta",
                    summary: "Second",
                    directoryURL: source.directoryURL.appending(path: "beta"),
                    sourceID: source.id
                ),
            ]
        )

        model.searchText = "Alpha"

        #expect(model.scopeSubtitle == "1 of 2 skills")
    }

    @Test("A whitespace-only search does not change the scope subtitle")
    func ignoresWhitespaceOnlySearch() {
        let source = SkillSource(
            name: "Claude Skills",
            directoryURL: URL(filePath: "/skills/claude"),
            agent: .claudeCode
        )
        let model = SkillLibraryModel(
            sources: [source],
            skills: [
                AgentSkill(
                    name: "Alpha",
                    summary: "First",
                    directoryURL: source.directoryURL.appending(path: "alpha"),
                    sourceID: source.id
                )
            ]
        )

        model.searchText = "   "

        #expect(model.scopeSubtitle == "1 skill")
    }
}
