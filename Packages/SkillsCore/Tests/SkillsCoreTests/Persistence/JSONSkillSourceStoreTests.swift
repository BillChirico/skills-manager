import Foundation
import Testing

@testable import SkillsCore

struct JSONSkillSourceStoreTests {
    @Test("Saving a configuration preserves automatic-folder exclusions")
    func savesAndLoadsConfiguration() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SkillsCoreStoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let store: any SkillSourceStore = JSONSkillSourceStore(
            fileURL: directory.appending(
                path: "sources.json",
                directoryHint: .notDirectory
            )
        )
        let source = SkillSource(
            name: "Claude Skills",
            directoryURL: URL(filePath: "/skills/claude")
        )
        let excludedURL = URL(
            filePath: "/skills/cursor",
            directoryHint: .isDirectory
        )
        let configuration = SkillSourceConfiguration(
            sources: [source],
            excludedAutomaticDirectoryURLs: Set([excludedURL])
        )

        try await store.save(configuration)
        let loaded = try await store.loadConfiguration()

        #expect(loaded == configuration)
    }

    @Test("A failed commit preserves the last good configuration")
    func failedCommitPreservesLastGoodConfiguration() async throws {
        struct CommitError: Error {}

        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SkillsCoreStoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(
            path: "sources.json",
            directoryHint: .notDirectory
        )
        let originalSource = SkillSource(
            name: "Original Skills",
            directoryURL: URL(filePath: "/skills/original")
        )
        let replacementSource = SkillSource(
            name: "Replacement Skills",
            directoryURL: URL(filePath: "/skills/replacement")
        )
        let readableStore = JSONSkillSourceStore(fileURL: fileURL)
        try await readableStore.save([originalSource])
        let failingStore = JSONSkillSourceStore(
            fileURL: fileURL,
            commitFile: { _, _ in throw CommitError() }
        )

        await #expect(throws: CommitError.self) {
            try await failingStore.save([replacementSource])
        }

        #expect(try await readableStore.loadSources() == [originalSource])
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                == ["sources.json"]
        )
    }

    @Test("A legacy source array loads as a configuration without exclusions")
    func loadsLegacySourceArray() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SkillsCoreStoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let fileURL = directory.appending(
            path: "sources.json",
            directoryHint: .notDirectory
        )
        let source = SkillSource(
            name: "Legacy Skills",
            directoryURL: URL(filePath: "/skills/legacy")
        )
        try JSONEncoder().encode([source]).write(to: fileURL)
        let store = JSONSkillSourceStore(fileURL: fileURL)

        let loaded = try await store.loadConfiguration()

        #expect(loaded.sources == [source])
        #expect(loaded.excludedAutomaticDirectoryURLs.isEmpty)
    }

    @Test("Saving only sources preserves existing automatic-folder exclusions")
    func sourceOnlySavePreservesExclusions() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SkillsCoreStoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = JSONSkillSourceStore(
            fileURL: directory.appending(
                path: "sources.json",
                directoryHint: .notDirectory
            )
        )
        let excludedURL = URL(
            filePath: "/skills/gemini",
            directoryHint: .isDirectory
        )
        try await store.save(
            SkillSourceConfiguration(
                excludedAutomaticDirectoryURLs: Set([excludedURL])
            )
        )
        let source = SkillSource(
            name: "Team Skills",
            directoryURL: URL(filePath: "/skills/team")
        )

        try await store.save([source])
        let loaded = try await store.loadConfiguration()

        #expect(loaded.sources == [source])
        #expect(loaded.excludedAutomaticDirectoryURLs == Set([excludedURL]))
    }

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

        let loaded = try await store.loadConfiguration()

        #expect(loaded == SkillSourceConfiguration())
    }
}
