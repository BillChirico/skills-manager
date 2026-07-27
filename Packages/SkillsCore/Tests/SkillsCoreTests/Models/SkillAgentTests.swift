import Foundation
import Testing

@testable import SkillsCore

struct SkillAgentTests {
    struct DefaultDirectoryCase: Sendable {
        let agent: SkillAgent
        let relativePath: String
    }

    @Test("Agent assignments survive source persistence")
    func sourceAgentRoundTrip() throws {
        let source = SkillSource(
            name: "Codex",
            directoryURL: URL(filePath: "/skills/codex"),
            agent: .codex
        )

        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(SkillSource.self, from: data)

        #expect(decoded.agent == .codex)
    }

    @Test("Sources saved before agent assignments existed decode as Other")
    func legacySourceDefaultsToOther() throws {
        let id = UUID()
        let data = Data(
            """
            {
              "id": "\(id.uuidString)",
              "name": "Legacy Skills",
              "directoryURL": "file:///skills/legacy/",
              "isEnabled": true
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(SkillSource.self, from: data)

        #expect(decoded.agent == .other)
    }

    @Test(
        "Known agents expose their standard user skill directories",
        arguments: [
            DefaultDirectoryCase(agent: .claudeCode, relativePath: ".claude/skills"),
            DefaultDirectoryCase(agent: .codex, relativePath: ".agents/skills"),
            DefaultDirectoryCase(agent: .cursor, relativePath: ".cursor/skills"),
            DefaultDirectoryCase(agent: .githubCopilot, relativePath: ".copilot/skills"),
            DefaultDirectoryCase(agent: .gemini, relativePath: ".gemini/skills"),
        ]
    )
    func standardUserDirectory(testCase: DefaultDirectoryCase) {
        let homeDirectory = URL(filePath: "/Users/example", directoryHint: .isDirectory)
        let expectedURL = homeDirectory.appending(
            path: testCase.relativePath,
            directoryHint: .isDirectory
        )

        #expect(
            testCase.agent.defaultSkillsDirectoryRelativePath
                == testCase.relativePath
        )
        #expect(
            testCase.agent.defaultSkillsDirectory(in: homeDirectory)
                == expectedURL
        )
    }

    @Test("Other agents do not assume a default directory")
    func otherAgentHasNoDefaultDirectory() {
        #expect(SkillAgent.other.defaultSkillsDirectoryRelativePath == nil)
        #expect(
            SkillAgent.other.defaultSkillsDirectory(
                in: URL(filePath: "/Users/example")
            ) == nil
        )
    }
}
