import Foundation
import Testing

@testable import SkillsCore

struct SkillLibraryFilterTests {
    @Test("A disabled source is excluded from every library scope")
    func excludesDisabledSources() {
        let enabledSource = SkillSource(
            name: "Enabled",
            directoryURL: URL(filePath: "/skills/enabled")
        )
        let disabledSource = SkillSource(
            name: "Disabled",
            directoryURL: URL(filePath: "/skills/disabled"),
            isEnabled: false
        )
        let skills = [
            makeSkill(name: "Visible", sourceID: enabledSource.id),
            makeSkill(name: "Hidden", sourceID: disabledSource.id),
        ]

        let results = SkillLibraryFilter.filter(
            skills,
            sources: [enabledSource, disabledSource],
            scope: .allSkills,
            query: "",
            recentCutoff: .distantPast
        )

        #expect(results.map(\.name) == ["Visible"])
    }

    @Test("Update and disabled groups use independent skill facts")
    func composesManagementState() {
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/skills")
        )
        let disabledUpdate = makeSkill(
            name: "PDF Export",
            sourceID: source.id,
            installedVersion: "1.4.0",
            availableVersion: "1.5.0",
            isEnabled: false
        )

        let updates = SkillLibraryFilter.filter(
            [disabledUpdate],
            sources: [source],
            scope: .updatesAvailable,
            query: "",
            recentCutoff: .distantPast
        )
        let disabled = SkillLibraryFilter.filter(
            [disabledUpdate],
            sources: [source],
            scope: .disabled,
            query: "",
            recentCutoff: .distantPast
        )

        #expect(updates.map(\.name) == ["PDF Export"])
        #expect(disabled.map(\.name) == ["PDF Export"])
    }

    @Test("Recently added includes the cutoff boundary")
    func includesRecentCutoff() {
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/skills")
        )
        let cutoff = Date(timeIntervalSince1970: 1_000)
        let skills = [
            makeSkill(name: "Before", sourceID: source.id, addedAt: cutoff.addingTimeInterval(-1)),
            makeSkill(name: "Boundary", sourceID: source.id, addedAt: cutoff),
            makeSkill(name: "After", sourceID: source.id, addedAt: cutoff.addingTimeInterval(1)),
        ]

        let results = SkillLibraryFilter.filter(
            skills,
            sources: [source],
            scope: .recentlyAdded,
            query: "",
            recentCutoff: cutoff
        )

        #expect(results.map(\.name) == ["After", "Boundary"])
    }

    private func makeSkill(
        name: String,
        sourceID: SkillSource.ID,
        installedVersion: String? = nil,
        availableVersion: String? = nil,
        isEnabled: Bool = true,
        addedAt: Date = .distantPast
    ) -> AgentSkill {
        AgentSkill(
            name: name,
            summary: "\(name) summary",
            installedVersion: installedVersion,
            availableVersion: availableVersion,
            directoryURL: URL(filePath: "/skills/\(name)"),
            sourceID: sourceID,
            isEnabled: isEnabled,
            addedAt: addedAt
        )
    }
}
