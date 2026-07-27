import Foundation

public enum SkillLibraryScope: Hashable, Sendable {
    case allSkills
    case updatesAvailable
    case disabled
    case recentlyAdded
    case source(SkillSource.ID)
}

public enum SkillLibraryFilter {
    public static func filter(
        _ skills: [AgentSkill],
        sources: [SkillSource],
        scope: SkillLibraryScope,
        query: String,
        recentCutoff: Date,
        sortOrder: SkillSortOrder = .name
    ) -> [AgentSkill] {
        let enabledSourceIDs = Set(
            sources
                .filter(\.isEnabled)
                .map(\.id)
        )
        let availableSkills = skills.filter { enabledSourceIDs.contains($0.sourceID) }

        let scopedSkills = availableSkills.filter { skill in
            switch scope {
            case .allSkills:
                true
            case .updatesAvailable:
                skill.hasUpdate
            case .disabled:
                skill.isEnabled == false
            case .recentlyAdded:
                skill.addedAt >= recentCutoff
            case .source(let sourceID):
                skill.sourceID == sourceID
            }
        }

        return SkillLibrarySorter.sort(
            SkillSearch.filter(scopedSkills, query: query),
            sources: sources,
            order: sortOrder
        )
    }
}
