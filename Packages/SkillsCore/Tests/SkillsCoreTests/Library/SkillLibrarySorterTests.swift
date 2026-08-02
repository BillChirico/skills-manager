import Foundation
import Testing

@testable import SkillsCore

struct SkillLibrarySorterTests {
    @Test(
        "Available updates are first while preserving the selected secondary order",
        arguments: SkillSortOrder.allCases
    )
    func prioritizesUpdates(order: SkillSortOrder) {
        let codex = makeSource(name: "Codex Skills", agent: .codex)
        let claude = makeSource(name: "Claude Skills", agent: .claudeCode)
        let skills = [
            makeSkill(
                name: "Zulu Update",
                source: codex,
                addedAt: Date(timeIntervalSince1970: 1),
                updateStatus: .available
            ),
            makeSkill(
                name: "Beta Current",
                source: codex,
                addedAt: Date(timeIntervalSince1970: 30)
            ),
            makeSkill(
                name: "Alpha Current",
                source: claude,
                addedAt: Date(timeIntervalSince1970: 20)
            ),
        ]

        let results = SkillLibrarySorter.sort(skills, sources: [codex, claude], order: order)
        let expectedNames =
            switch order {
            case .name:
                ["Zulu Update", "Alpha Current", "Beta Current"]
            case .dateAdded:
                ["Zulu Update", "Beta Current", "Alpha Current"]
            case .agent:
                ["Zulu Update", "Alpha Current", "Beta Current"]
            }

        #expect(results.map(\.name) == expectedNames)
    }

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

    @Test("Equivalent display keys use stable source identity as the final tie breaker")
    func deterministicFinalTieBreaker() throws {
        let firstSourceID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )
        let secondSourceID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")
        )
        let firstSource = SkillSource(
            id: firstSourceID,
            name: "Shared",
            directoryURL: URL(filePath: "/skills/one"),
            agent: .codex
        )
        let secondSource = SkillSource(
            id: secondSourceID,
            name: "Shared",
            directoryURL: URL(filePath: "/skills/two"),
            agent: .codex
        )
        let first = makeSkill(name: "Same", source: firstSource, addedAt: .distantPast)
        let second = makeSkill(name: "Same", source: secondSource, addedAt: .distantPast)

        let results = SkillLibrarySorter.sort(
            [second, first],
            sources: [secondSource, firstSource],
            order: .agent
        )

        #expect(results.map(\.sourceID) == [firstSource.id, secondSource.id])
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
        addedAt: Date,
        updateStatus: SkillUpdateStatus? = nil
    ) -> AgentSkill {
        AgentSkill(
            name: name,
            summary: "\(name) summary",
            updateStatus: updateStatus,
            directoryURL: source.directoryURL.appending(path: name),
            sourceID: source.id,
            addedAt: addedAt
        )
    }
}
