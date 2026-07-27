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

        let matches: [AgentSkill]
        if terms.isEmpty {
            matches = skills
        } else {
            matches = skills.filter { skill in
                let searchableText = [
                    skill.name,
                    skill.summary,
                    skill.author ?? "",
                    skill.directoryURL.lastPathComponent,
                ].joined(separator: " ")

                return terms.allSatisfy(searchableText.localizedCaseInsensitiveContains)
            }
        }

        return matches.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
