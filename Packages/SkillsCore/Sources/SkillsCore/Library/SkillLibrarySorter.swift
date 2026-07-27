import Foundation

public enum SkillSortOrder: String, CaseIterable, Codable, Identifiable, Sendable {
    case name
    case dateAdded
    case agent

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .name:
            "Name"
        case .dateAdded:
            "Date Added"
        case .agent:
            "Agent"
        }
    }
}

public enum SkillLibrarySorter {
    public static func sort(
        _ skills: [AgentSkill],
        sources: [SkillSource],
        order: SkillSortOrder
    ) -> [AgentSkill] {
        let sourcesByID = Dictionary(
            uniqueKeysWithValues: sources.map { ($0.id, $0) }
        )

        return skills.sorted { lhs, rhs in
            switch order {
            case .name:
                return nameComesFirst(lhs, rhs)
            case .dateAdded:
                if lhs.addedAt != rhs.addedAt {
                    return lhs.addedAt > rhs.addedAt
                }
                return nameComesFirst(lhs, rhs)
            case .agent:
                let lhsSource = sourcesByID[lhs.sourceID]
                let rhsSource = sourcesByID[rhs.sourceID]
                let agentComparison = (lhsSource?.agent.displayName ?? "")
                    .localizedStandardCompare(rhsSource?.agent.displayName ?? "")
                if agentComparison != .orderedSame {
                    return agentComparison == .orderedAscending
                }

                let sourceComparison = (lhsSource?.displayName ?? "")
                    .localizedStandardCompare(rhsSource?.displayName ?? "")
                if sourceComparison != .orderedSame {
                    return sourceComparison == .orderedAscending
                }

                return nameComesFirst(lhs, rhs)
            }
        }
    }

    private static func nameComesFirst(_ lhs: AgentSkill, _ rhs: AgentSkill) -> Bool {
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }

        return lhs.id.relativePath < rhs.id.relativePath
    }
}
