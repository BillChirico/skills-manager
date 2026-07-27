import Foundation
import Testing

@testable import SkillsCore

struct JSONSkillSourceStoreTests {
    @Test("Saving sources replaces and reloads the persisted collection")
    func savesAndLoadsSources() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SkillsCoreStoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = JSONSkillSourceStore(
            fileURL: directory.appending(path: "sources.json", directoryHint: .notDirectory)
        )
        let source = SkillSource(
            name: "Claude Skills",
            directoryURL: URL(filePath: "/skills/claude"),
            bookmarkData: Data("bookmark".utf8)
        )

        try await store.save([source])
        let loaded = try await store.loadSources()

        #expect(loaded == [source])
    }

    @Test("A missing persistence file loads as an empty collection")
    func missingFileIsEmpty() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SkillsCoreStoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = JSONSkillSourceStore(
            fileURL: directory.appending(path: "sources.json", directoryHint: .notDirectory)
        )

        let loaded = try await store.loadSources()

        #expect(loaded.isEmpty)
    }
}
