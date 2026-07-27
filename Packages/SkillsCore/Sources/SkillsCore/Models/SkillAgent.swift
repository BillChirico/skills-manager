import Foundation

public enum SkillAgent: String, CaseIterable, Codable, Identifiable, Sendable {
    case claudeCode
    case codex
    case cursor
    case githubCopilot
    case gemini
    case other

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .claudeCode:
            "Claude Code"
        case .codex:
            "Codex"
        case .cursor:
            "Cursor"
        case .githubCopilot:
            "GitHub Copilot"
        case .gemini:
            "Gemini"
        case .other:
            "Other"
        }
    }

    public var defaultSkillsDirectoryRelativePath: String? {
        switch self {
        case .claudeCode:
            ".claude/skills"
        case .codex:
            ".agents/skills"
        case .cursor:
            ".cursor/skills"
        case .githubCopilot:
            ".copilot/skills"
        case .gemini:
            ".gemini/skills"
        case .other:
            nil
        }
    }

    public func defaultSkillsDirectory(in homeDirectory: URL) -> URL? {
        guard let relativePath = defaultSkillsDirectoryRelativePath else {
            return nil
        }

        return relativePath.split(separator: "/").reduce(
            homeDirectory.standardizedFileURL
        ) { directoryURL, component in
            directoryURL.appending(
                path: String(component),
                directoryHint: .isDirectory
            )
        }
    }
}
