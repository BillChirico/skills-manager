import Foundation
import Testing

@testable import SkillsCore

struct CatalogSkillSorterTests {
    @Test("Skills are ordered by download count, highest first")
    func ordersByDownloads() {
        let sorted = CatalogSkillSorter.byDownloads([
            makeSkill(slug: "middle", installs: 500),
            makeSkill(slug: "lowest", installs: 1),
            makeSkill(slug: "highest", installs: 9_000),
        ])

        #expect(sorted.map(\.slug) == ["highest", "middle", "lowest"])
    }

    @Test("Equal download counts fall back to a stable name order")
    func breaksTiesDeterministically() {
        let sorted = CatalogSkillSorter.byDownloads([
            makeSkill(slug: "zulu", name: "Zulu", installs: 42),
            makeSkill(slug: "alpha", name: "Alpha", installs: 42),
            makeSkill(slug: "mike", name: "Mike", installs: 42),
        ])

        #expect(sorted.map(\.name) == ["Alpha", "Mike", "Zulu"])
    }

    @Test("Identical names fall back to the catalog identifier")
    func breaksNameTiesByIdentifier() {
        let sorted = CatalogSkillSorter.byDownloads([
            makeSkill(id: "b/repo/tdd", slug: "tdd", name: "TDD", installs: 7),
            makeSkill(id: "a/repo/tdd", slug: "tdd", name: "TDD", installs: 7),
        ])

        #expect(sorted.map(\.id) == ["a/repo/tdd", "b/repo/tdd"])
    }

    @Test("Sorting an empty catalog produces an empty result")
    func handlesEmptyInput() {
        #expect(CatalogSkillSorter.byDownloads([]).isEmpty)
    }

    private func makeSkill(
        id: String? = nil,
        slug: String,
        name: String? = nil,
        installs: Int
    ) -> CatalogSkill {
        CatalogSkill(
            id: id ?? "owner/repo/\(slug)",
            slug: slug,
            name: name ?? slug,
            source: "owner/repo",
            installs: installs
        )
    }
}
