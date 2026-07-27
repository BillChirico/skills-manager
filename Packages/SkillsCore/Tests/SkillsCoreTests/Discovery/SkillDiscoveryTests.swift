import Foundation
import Testing

@testable import SkillsCore

struct SkillDiscoveryTests {
    @Test("Discovery reads immediate child SKILL.md manifests")
    func discoversManifestMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "SkillsCoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDirectory = root.appending(path: "web-research", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: skillDirectory,
            withIntermediateDirectories: true
        )
        try """
        ---
        name: Web Research
        description: Search, read, and summarize web pages.
        author: Volvox
        version: 2.1.0
        ---

        # Web Research

        Fetches and reads web pages, then returns a condensed summary.
        """.write(
            to: skillDirectory.appending(path: "SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let ignoredDirectory = root.appending(path: "not-a-skill", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: ignoredDirectory,
            withIntermediateDirectories: true
        )

        let source = SkillSource(name: "Team Skills", directoryURL: root)
        let skills = try await FileSystemSkillDiscoverer().discoverSkills(in: source)
        let skill = try #require(skills.first)

        #expect(skills.count == 1)
        #expect(skill.name == "Web Research")
        #expect(skill.summary == "Search, read, and summarize web pages.")
        #expect(skill.author == "Volvox")
        #expect(skill.installedVersion == "2.1.0")
        #expect(skill.id == SkillIdentifier(sourceID: source.id, relativePath: "web-research"))
        #expect(
            skill.overview
                == "Fetches and reads web pages, then returns a condensed summary."
        )
        #expect(skill.lastScannedAt != nil)
    }

    @Test("Discovery tolerates duplicate front-matter keys")
    func toleratesDuplicateFrontMatterKeys() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "SkillsCoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDirectory = root.appending(path: "duplicate-keys", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: skillDirectory,
            withIntermediateDirectories: true
        )
        try """
        ---
        name: Original Name
        description: Original description.
        name: Final Name
        description: Final description.
        ---

        # Final Name
        """.write(
            to: skillDirectory.appending(path: "SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let source = SkillSource(name: "Team Skills", directoryURL: root)
        let skills = try await FileSystemSkillDiscoverer().discoverSkills(in: source)
        let skill = try #require(skills.first)

        #expect(skill.name == "Final Name")
        #expect(skill.summary == "Final description.")
    }

    @Test("Discovery reads folded front-matter descriptions")
    func readsFoldedFrontMatterDescriptions() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "SkillsCoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDirectory = root.appending(path: "railway", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: skillDirectory,
            withIntermediateDirectories: true
        )
        try """
        ---
        name: Railway
        description: >
          Operate Railway infrastructure,
          deploy services, and inspect logs.
        ---

        # Railway
        """.write(
            to: skillDirectory.appending(path: "SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let source = SkillSource(name: "Team Skills", directoryURL: root)
        let skills = try await FileSystemSkillDiscoverer().discoverSkills(in: source)
        let skill = try #require(skills.first)

        #expect(
            skill.summary
                == "Operate Railway infrastructure, deploy services, and inspect logs."
        )
    }

    @Test("Discovery supplies readable fallbacks for an empty manifest")
    func suppliesEmptyManifestFallbacks() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "SkillsCoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDirectory = root.appending(path: "empty-skill", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: skillDirectory,
            withIntermediateDirectories: true
        )
        try "".write(
            to: skillDirectory.appending(path: "SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let source = SkillSource(name: "Team Skills", directoryURL: root)
        let skills = try await FileSystemSkillDiscoverer().discoverSkills(in: source)
        let skill = try #require(skills.first)

        #expect(skill.name == "empty-skill")
        #expect(skill.summary == "No description provided.")
        #expect(skill.overview == "No description provided.")
    }
}
