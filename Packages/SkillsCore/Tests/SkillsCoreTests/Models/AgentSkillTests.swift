import Foundation
import Testing

@testable import SkillsCore

struct AgentSkillTests {
    @Test("The same discovered skill keeps its identity across scans")
    func stableIdentityAcrossScans() {
        let sourceID = UUID()
        let directoryURL = URL(filePath: "/skills/web-research")

        let firstScan = AgentSkill(
            name: "Web Research",
            summary: "Search and summarize web pages.",
            directoryURL: directoryURL,
            sourceID: sourceID
        )
        let secondScan = AgentSkill(
            name: "Web Research",
            summary: "Search and summarize web pages.",
            directoryURL: directoryURL,
            sourceID: sourceID
        )

        #expect(firstScan.id == secondScan.id)
    }

    @Test("Disabled skills can still report an available update")
    func disabledSkillWithUpdate() {
        let skill = AgentSkill(
            name: "PDF Export",
            summary: "Render markdown as a publication-ready PDF.",
            installedVersion: "1.4.0",
            availableVersion: "1.5.0",
            directoryURL: URL(filePath: "/skills/pdf-export"),
            sourceID: UUID(),
            isEnabled: false
        )

        #expect(skill.isEnabled == false)
        #expect(skill.hasUpdate)
    }
}
