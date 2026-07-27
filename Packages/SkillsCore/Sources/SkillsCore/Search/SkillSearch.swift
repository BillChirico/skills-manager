import Foundation

public enum SkillSearch {
    public static func filter(
        _ skills: [AgentSkill],
        query: String
    ) -> [AgentSkill] {
        let terms =
            query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        if terms.isEmpty {
            return skills.sorted(by: localizedNameOrder)
        }

        return skills.compactMap { skill -> (skill: AgentSkill, score: Int)? in
            var score = 0

            for term in terms {
                let name = normalized(skill.name)
                let normalizedTerm = normalized(term)

                if name.hasPrefix(normalizedTerm) {
                    score += 4
                } else if name.contains(normalizedTerm) {
                    score += 3
                } else if normalized(skill.author ?? "").contains(normalizedTerm) {
                    score += 2
                } else if normalized(skill.directoryURL.lastPathComponent).contains(normalizedTerm) {
                    score += 2
                } else if normalized(skill.summary).contains(normalizedTerm) {
                    score += 1
                } else {
                    return nil
                }
            }

            return (skill, score)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }

            return localizedNameOrder(lhs.skill, rhs.skill)
        }
        .map(\.skill)
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: .diacriticInsensitive, locale: .current)
            .localizedLowercase
    }

    private static func localizedNameOrder(_ lhs: AgentSkill, _ rhs: AgentSkill) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
