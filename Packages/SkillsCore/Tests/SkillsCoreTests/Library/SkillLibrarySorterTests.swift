import Foundation
import Testing

@testable import SkillsCore

struct SkillLibrarySorterTests {
    @Test("Name sorting uses localized ascending order")
    func sortsByName() {
        let source = makeSource(name: "Codex", agent: .codex)
        let skills = [
            makeSkill(name: "Write", source: source, addedAt: Date(timeIntervalSince1970: 20)),
            makeSkill(name: "Analyze", source: source, addedAt: Date(timeIntervalSince1970: 10)),
        ]

        let results = SkillLibrarySorter.sort(
            skills,
            sources: [source],
            order: .name
        )

        #expect(results.map(\.name) == ["Analyze", "Write"])
    }

    @Test("Date sorting shows the newest skills first and breaks ties by name")
    func sortsByDateAdded() {
        let source = makeSource(name: "Codex", agent: .codex)
        let newestDate = Date(timeIntervalSince1970: 20)
        let skills = [
            makeSkill(name: "Older", source: source, addedAt: Date(timeIntervalSince1970: 10)),
            makeSkill(name: "Zulu", source: source, addedAt: newestDate),
            makeSkill(name: "Alpha", source: source, addedAt: newestDate),
        ]

        let results = SkillLibrarySorter.sort(
            skills,
            sources: [source],
            order: .dateAdded
        )

        #expect(results.map(\.name) == ["Alpha", "Zulu", "Older"])
    }

    @Test("Agent sorting groups skills by assigned agent and then by name")
    func sortsByAgent() {
        let codex = makeSource(name: "Codex Skills", agent: .codex)
        let claude = makeSource(name: "Claude Skills", agent: .claudeCode)
        let skills = [
            makeSkill(name: "Write", source: codex, addedAt: .distantPast),
            makeSkill(name: "Review", source: claude, addedAt: .distantPast),
            makeSkill(name: "Analyze", source: claude, addedAt: .distantPast),
        ]

        let results = SkillLibrarySorter.sort(
            skills,
            sources: [codex, claude],
            order: .agent
        )

        #expect(results.map(\.name) == ["Analyze", "Review", "Write"])
    }

    private func makeSource(name: String, agent: SkillAgent) -> SkillSource {
        SkillSource(
            name: name,
            directoryURL: URL(filePath: "/skills/\(name)"),
            agent: agent
        )
    }

    private func makeSkill(
        name: String,
        source: SkillSource,
        addedAt: Date
    ) -> AgentSkill {
        AgentSkill(
            name: name,
            summary: "\(name) summary",
            directoryURL: source.directoryURL.appending(path: name),
            sourceID: source.id,
            addedAt: addedAt
        )
    }
}
