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

    @Test("Persisted bookmarks are readable only by their owner")
    func savesWithOwnerOnlyPermissions() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SkillsCoreStoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(
            path: "sources.json",
            directoryHint: .notDirectory
        )
        let store = JSONSkillSourceStore(fileURL: fileURL)
        let source = SkillSource(
            name: "Claude Skills",
            directoryURL: URL(filePath: "/skills/claude"),
            bookmarkData: Data("bookmark".utf8)
        )

        try await store.save([source])
        // A second save exercises the atomic replacement path, which drops the
        // permissions of the file it replaces.
        try await store.save([source])

        let filePermissions =
            try FileManager.default
            .attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber
        let directoryPermissions =
            try FileManager.default
            .attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber

        #expect(filePermissions?.intValue == 0o600)
        #expect(directoryPermissions?.intValue == 0o700)
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
