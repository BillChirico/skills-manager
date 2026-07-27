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
}
