import Foundation
import Testing

@testable import SkillsManager

struct SkillLibraryModelTests {
    @Test("Adding a directory selects a new source")
    @MainActor
    func addsAndSelectsSource() throws {
        let model = SkillLibraryModel()

        model.addSource(at: URL(filePath: "/tmp/team-skills"))

        let source = try #require(model.sources.first)
        #expect(model.sources.map(\.displayName) == ["team-skills"])
        #expect(model.sidebarSelection == .source(source.id))
    }

    @Test("Adding the same normalized directory does not create a duplicate")
    @MainActor
    func deduplicatesSources() {
        let model = SkillLibraryModel()

        model.addSource(at: URL(filePath: "/tmp/team-skills"))
        model.addSource(at: URL(filePath: "/tmp/other/../team-skills"))

        #expect(model.sources.count == 1)
    }
}
