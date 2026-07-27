import SkillsCore

extension SkillAgent {
    var systemImage: String {
        switch self {
        case .claudeCode:
            "brain"
        case .codex:
            "terminal"
        case .cursor:
            "cursorarrow.rays"
        case .githubCopilot:
            "chevron.left.forwardslash.chevron.right"
        case .gemini:
            "sparkle"
        case .other:
            "cpu"
        }
    }
}
