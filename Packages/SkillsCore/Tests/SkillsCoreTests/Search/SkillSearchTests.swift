import Foundation
import Testing

@testable import SkillsCore

struct SkillSearchTests {
    struct SearchCase: Sendable {
        let query: String
        let expectedName: String
    }

    private let sourceID = UUID()

    @Test(
        "Search matches skill metadata",
        arguments: [
            SearchCase(query: "review", expectedName: "Code Review"),
            SearchCase(query: "volvox", expectedName: "Project Planner"),
            SearchCase(query: "planner", expectedName: "Project Planner"),
        ]
    )
    func searchesMetadata(testCase: SearchCase) {
        let results = SkillSearch.filter(fixtures, query: testCase.query)

        #expect(results.map(\.name) == [testCase.expectedName])
    }

    @Test("Every search term must match")
    func matchesEveryTerm() {
        let results = SkillSearch.filter(fixtures, query: "project volvox")

        #expect(results.map(\.name) == ["Project Planner"])
    }

    @Test("An empty search returns a localized name ordering")
    func emptySearchReturnsSortedSkills() {
        let results = SkillSearch.filter(fixtures, query: " \n ")

        #expect(results.map(\.name) == ["Code Review", "Project Planner"])
    }

    @Test("A name match ranks ahead of a description match")
    func ranksNameMatchesFirst() {
        let skills = [
            AgentSkill(
                name: "Design Review",
                summary: "Review spacing in generated diagrams.",
                directoryURL: URL(filePath: "/skills/design-review"),
                sourceID: sourceID
            ),
            AgentSkill(
                name: "Diagram",
                summary: "Turn descriptions into editable visuals.",
                directoryURL: URL(filePath: "/skills/diagram"),
                sourceID: sourceID
            ),
        ]

        let results = SkillSearch.filter(skills, query: "diagram")

        #expect(results.map(\.name) == ["Diagram", "Design Review"])
    }

    private var fixtures: [AgentSkill] {
        [
            AgentSkill(
                name: "Project Planner",
                summary: "Turns product ideas into implementation plans.",
                author: "Volvox",
                directoryURL: URL(filePath: "/skills/planner"),
                sourceID: sourceID
            ),
            AgentSkill(
                name: "Code Review",
                summary: "Reviews a pending change for correctness.",
                directoryURL: URL(filePath: "/skills/reviewer"),
                sourceID: sourceID
            ),
        ]
    }
}
