import Foundation
import SkillsCore
import Testing

@testable import SkillsManager

struct AgentDirectorySuggestionTests {
    private let homeDirectory = URL(
        filePath: "/Users/reviewer",
        directoryHint: .isDirectory
    )

    @Test("Only agent folders that exist on disk are suggested")
    func suggestsOnlyExistingDirectories() {
        let suggestions = AgentDirectorySuggestion.suggestions(
            in: homeDirectory,
            directoryExists: existenceCheck(for: [.claudeCode, .cursor])
        )

        #expect(suggestions.map(\.agent) == [.claudeCode, .cursor])
    }

    @Test("A home directory without agent folders suggests nothing")
    func suggestsNothingWhenNoDirectoryExists() {
        let suggestions = AgentDirectorySuggestion.suggestions(
            in: homeDirectory,
            directoryExists: { _ in false }
        )

        #expect(suggestions.isEmpty)
    }

    @Test("Agents without a standard location are never suggested")
    func neverSuggestsAgentsWithoutAStandardLocation() {
        let suggestions = AgentDirectorySuggestion.suggestions(
            in: homeDirectory,
            directoryExists: { _ in true }
        )

        #expect(suggestions.contains { $0.agent == .other } == false)
        #expect(suggestions.map(\.agent) == SkillAgent.allCases.filter { $0 != .other })
    }

    @Test("The shared agent location leads the suggestions under its own name")
    func globalLeadsTheSuggestions() throws {
        let suggestions = AgentDirectorySuggestion.suggestions(
            in: homeDirectory,
            directoryExists: { _ in true }
        )

        let global = try #require(suggestions.first)
        #expect(global.agent == .global)
        #expect(global.relativePath == ".agents/skills")
        #expect(global.title == "Global — ~/.agents/skills")
        #expect(
            global.directoryURL
                == SkillAgent.global.defaultSkillsDirectory(in: homeDirectory)
        )
    }

    /// `Global` and `Codex` share `~/.agents/skills`, so both suggestions can be
    /// offered at once. Adding the second one re-selects the source the first one
    /// created rather than configuring the same folder twice.
    @Test("The shared agent location and Codex suggest the same folder")
    func globalAndCodexSuggestTheSameFolder() throws {
        let suggestions = AgentDirectorySuggestion.suggestions(
            in: homeDirectory,
            directoryExists: { _ in true }
        )

        let global = try #require(suggestions.first { $0.agent == .global })
        let codex = try #require(suggestions.first { $0.agent == .codex })
        #expect(global.directoryURL == codex.directoryURL)
    }

    @Test("A suggestion titles itself without exposing the account name")
    func titleAbbreviatesTheHomeDirectory() throws {
        let suggestions = AgentDirectorySuggestion.suggestions(
            in: homeDirectory,
            directoryExists: existenceCheck(for: [.claudeCode])
        )

        let claudeCode = try #require(suggestions.first)
        #expect(claudeCode.title == "Claude Code — ~/.claude/skills")
        #expect(claudeCode.title.contains("reviewer") == false)
    }

    @Test("Only an existing directory counts as a suggestable location")
    func directoryExistenceRejectsFilesAndMissingPaths() throws {
        let root = URL.temporaryDirectory.appending(
            path: "AgentDirectorySuggestionTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appending(path: "skills", directoryHint: .notDirectory)
        try Data("not a directory".utf8).write(to: fileURL)

        #expect(AgentDirectorySuggestion.directoryExists(at: root))
        #expect(AgentDirectorySuggestion.directoryExists(at: fileURL) == false)
        #expect(
            AgentDirectorySuggestion.directoryExists(
                at: root.appending(path: "missing", directoryHint: .isDirectory)
            ) == false
        )
    }

    private func existenceCheck(
        for agents: Set<SkillAgent>
    ) -> (URL) -> Bool {
        let existingURLs = Set(
            agents.compactMap { $0.defaultSkillsDirectory(in: homeDirectory) }
        )

        return { existingURLs.contains($0) }
    }
}

@MainActor
struct SuggestedFolderAddTests {
    @Test("A suggestion adds its folder through the library model without a picker")
    func addsSuggestedFolderDirectly() async throws {
        let homeDirectory = URL(filePath: "/Users/reviewer", directoryHint: .isDirectory)
        let suggestion = try #require(
            AgentDirectorySuggestion.suggestions(
                in: homeDirectory,
                directoryExists: { _ in true }
            )
            .first { $0.agent == .global }
        )
        let model = SkillLibraryModel()

        try await model.addSource(
            at: suggestion.directoryURL,
            agent: suggestion.agent
        )

        let source = try #require(model.sources.first)
        #expect(model.sources.count == 1)
        #expect(source.agent == .global)
        #expect(source.directoryURL == suggestion.directoryURL.standardizedFileURL)
        #expect(model.sidebarSelection == .source(source.id))
    }

    @Test("Adding the Codex suggestion after Global re-selects the same folder")
    func sharedFolderIsNeverConfiguredTwice() async throws {
        let homeDirectory = URL(filePath: "/Users/reviewer", directoryHint: .isDirectory)
        let suggestions = AgentDirectorySuggestion.suggestions(
            in: homeDirectory,
            directoryExists: { _ in true }
        )
        let global = try #require(suggestions.first { $0.agent == .global })
        let codex = try #require(suggestions.first { $0.agent == .codex })
        let model = SkillLibraryModel()

        try await model.addSource(at: global.directoryURL, agent: global.agent)
        try await model.addSource(at: codex.directoryURL, agent: codex.agent)

        let source = try #require(model.sources.first)
        #expect(model.sources.count == 1)
        #expect(source.agent == .global)
        #expect(model.sidebarSelection == .source(source.id))
    }
}
