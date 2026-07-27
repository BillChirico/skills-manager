import Foundation
import SkillsCore

/// A standard agent skills directory that exists on disk right now.
///
/// Settings only suggests a location it can see, so a suggestion never points at a
/// folder the user has not created for that agent yet.
struct AgentDirectorySuggestion: Identifiable, Hashable, Sendable {
    let agent: SkillAgent
    let relativePath: String
    let directoryURL: URL

    var id: SkillAgent { agent }

    /// The menu title, which pairs the agent with its home-relative path so the
    /// account name stays off screen.
    var title: String {
        "\(agent.displayName) — ~/\(relativePath)"
    }

    /// The suggestions to offer for `homeDirectory`, in `SkillAgent.allCases` order.
    ///
    /// - Parameters:
    ///   - homeDirectory: The account home the standard locations resolve against.
    ///   - directoryExists: Reports whether a resolved location exists on disk.
    /// - Returns: One suggestion per agent whose standard location exists.
    static func suggestions(
        in homeDirectory: URL,
        directoryExists: (URL) -> Bool = AgentDirectorySuggestion.directoryExists(at:)
    ) -> [AgentDirectorySuggestion] {
        SkillAgent.allCases.compactMap { agent in
            guard
                let relativePath = agent.defaultSkillsDirectoryRelativePath,
                let directoryURL = agent.defaultSkillsDirectory(in: homeDirectory),
                directoryExists(directoryURL)
            else {
                return nil
            }

            return AgentDirectorySuggestion(
                agent: agent,
                relativePath: relativePath,
                directoryURL: directoryURL
            )
        }
    }

    /// Reports whether `url` is a directory that exists right now.
    ///
    /// - Parameter url: The location to test.
    /// - Returns: `true` when the location exists and is a directory.
    static func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )

        return exists && isDirectory.boolValue
    }
}
