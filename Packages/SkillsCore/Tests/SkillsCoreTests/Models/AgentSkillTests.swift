import Foundation
import Testing

@testable import SkillsCore

struct AgentSkillTests {
    @Test("Overview Markdown keeps styling but strips every untrusted link destination")
    func stripsOverviewLinks() {
        let source = SkillSource(
            name: "Local",
            directoryURL: URL(filePath: "/skills")
        )
        let skill = AgentSkill(
            name: "Untrusted",
            summary: "Summary",
            directoryURL: source.directoryURL.appending(path: "untrusted"),
            sourceID: source.id,
            overview:
                """
                **Review** [HTTPS](https://example.com), \
                [script](javascript:alert('owned')), and \
                [file](file:///etc/passwd).
                """
        )

        let overview = skill.attributedOverview

        #expect(
            String(overview.characters)
                == "Review HTTPS, script, and file."
        )
        #expect(overview.runs.allSatisfy { $0.link == nil })
        #expect(overview.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

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
