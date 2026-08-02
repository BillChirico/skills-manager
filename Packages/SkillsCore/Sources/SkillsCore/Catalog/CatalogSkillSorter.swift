import Foundation

/// Ordering for catalog results.
public enum CatalogSkillSorter {
    /// Orders skills by download count, highest first.
    ///
    /// skills.sh returns search hits in relevance order, so this is what turns a search
    /// into the download-ranked list the library presents. Ties fall back to name and
    /// then identifier so the order stays stable across identical responses.
    public static func byDownloads(_ skills: [CatalogSkill]) -> [CatalogSkill] {
        skills.sorted { lhs, rhs in
            guard lhs.installs == rhs.installs else {
                return lhs.installs > rhs.installs
            }

            let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
            guard nameComparison == .orderedSame else {
                return nameComparison == .orderedAscending
            }

            return lhs.id < rhs.id
        }
    }
}
