import Foundation
import SkillsCore
import Testing

@testable import SkillsManager

@MainActor
struct SkillLibraryOrganizationTests {
    @Test("Adding a directory records the agent it belongs to")
    func addsAgentDirectory() async throws {
        let store = OrganizationMemorySourceStore()
        let model = SkillLibraryModel(sourceStore: store)

        try await model.addSource(
            at: URL(filePath: "/skills/codex"),
            agent: .codex
        )

        let source = try #require(model.sources.first)
        #expect(source.agent == .codex)
        #expect(await store.loadSources() == [source])
    }

    @Test("Changing a directory agent persists without changing its identity")
    func changesSourceAgent() async throws {
        let source = SkillSource(
            name: "Shared",
            directoryURL: URL(filePath: "/skills/shared"),
            agent: .other
        )
        let store = OrganizationMemorySourceStore(sources: [source])
        let model = SkillLibraryModel(sources: [source], sourceStore: store)

        try await model.setSourceAgent(.claudeCode, sourceID: source.id)

        let updatedSource = try #require(model.sources.first)
        #expect(updatedSource.id == source.id)
        #expect(updatedSource.agent == .claudeCode)
        #expect(await store.loadSources() == [updatedSource])
    }

    @Test("The selected sort order controls visible skill ordering")
    func appliesSelectedSortOrder() {
        let codex = SkillSource(
            name: "Codex",
            directoryURL: URL(filePath: "/skills/codex"),
            agent: .codex
        )
        let claude = SkillSource(
            name: "Claude",
            directoryURL: URL(filePath: "/skills/claude"),
            agent: .claudeCode
        )
        let model = SkillLibraryModel(
            sources: [codex, claude],
            skills: [
                AgentSkill(
                    name: "Older Codex Skill",
                    summary: "Older",
                    directoryURL: codex.directoryURL.appending(path: "older"),
                    sourceID: codex.id,
                    addedAt: Date(timeIntervalSince1970: 10)
                ),
                AgentSkill(
                    name: "Newer Claude Skill",
                    summary: "Newer",
                    directoryURL: claude.directoryURL.appending(path: "newer"),
                    sourceID: claude.id,
                    addedAt: Date(timeIntervalSince1970: 20)
                ),
            ]
        )

        model.sortOrder = .dateAdded
        #expect(model.visibleSkills.map(\.name) == ["Newer Claude Skill", "Older Codex Skill"])

        model.sortOrder = .agent
        #expect(model.visibleSkills.map(\.name) == ["Newer Claude Skill", "Older Codex Skill"])
    }
}

private actor OrganizationMemorySourceStore: SkillSourceStore {
    private var sources: [SkillSource]

    init(sources: [SkillSource] = []) {
        self.sources = sources
    }

    func loadSources() -> [SkillSource] {
        sources
    }

    func save(_ sources: [SkillSource]) {
        self.sources = sources
    }
}
