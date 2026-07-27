import Foundation
import Observation
import SkillsCore

@MainActor
@Observable
final class SkillLibraryModel {
    enum SidebarSelection: Hashable {
        case allSkills
        case source(SkillSource.ID)
    }

    private(set) var sources: [SkillSource]
    private(set) var skills: [AgentSkill]
    var sidebarSelection: SidebarSelection
    var selectedSkillID: AgentSkill.ID?
    var searchText = ""

    init(
        sources: [SkillSource] = [],
        skills: [AgentSkill] = []
    ) {
        self.sources = sources
        self.skills = skills
        self.sidebarSelection = .allSkills
    }

    var visibleSkills: [AgentSkill] {
        let scopedSkills: [AgentSkill]

        switch sidebarSelection {
        case .allSkills:
            scopedSkills = skills
        case .source(let sourceID):
            scopedSkills = skills.filter { $0.sourceID == sourceID }
        }

        return SkillSearch.filter(scopedSkills, query: searchText)
    }

    var selectedSkill: AgentSkill? {
        guard let selectedSkillID else {
            return nil
        }

        return skills.first { $0.id == selectedSkillID }
    }

    func addSource(at directoryURL: URL) {
        let normalizedURL = directoryURL.standardizedFileURL

        if let existingSource = sources.first(where: {
            $0.directoryURL.standardizedFileURL == normalizedURL
        }) {
            sidebarSelection = .source(existingSource.id)
            return
        }

        let source = SkillSource(
            name: normalizedURL.lastPathComponent,
            directoryURL: normalizedURL
        )

        sources.append(source)
        sources.sort {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        sidebarSelection = .source(source.id)
    }
}
