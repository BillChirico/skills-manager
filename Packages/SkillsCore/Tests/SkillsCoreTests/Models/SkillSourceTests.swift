import Foundation
import Testing

@testable import SkillsCore

struct SkillSourceTests {
    @Test("A source uses its configured name when present")
    func configuredDisplayName() {
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/Users/example/.agents/skills")
        )

        #expect(source.displayName == "Team Skills")
    }

    @Test("A blank source name falls back to the directory name")
    func directoryFallbackDisplayName() {
        let source = SkillSource(
            name: "  \n",
            directoryURL: URL(filePath: "/Users/example/.agents/skills")
        )

        #expect(source.displayName == "skills")
    }

    @Test("Bookmark data survives source persistence")
    func bookmarkDataRoundTrip() throws {
        let bookmarkData = Data("security-scoped-bookmark".utf8)
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/Users/example/.agents/skills"),
            bookmarkData: bookmarkData
        )

        let encoded = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(SkillSource.self, from: encoded)

        #expect(decoded.bookmarkData == bookmarkData)
    }
}
