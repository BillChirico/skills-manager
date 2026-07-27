import Foundation
import Testing

@testable import SkillsCore

struct SkillAgentTests {
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
}
