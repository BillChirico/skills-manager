import Foundation

/// The `skills` CLI invocation that skills.sh prints at the top of a skill page.
///
/// The value is rebuilt locally from validated catalog fields rather than scraped from
/// the remote page, and it is modelled as a program plus an argument vector so no caller
/// can hand a remote-sourced string to a shell. Skills Manager displays it and copies it;
/// it never executes it.
public struct SkillInstallCommand: Hashable, Sendable {
    /// The program a user would run in their own terminal.
    public let program: String

    /// The argument vector, already split so nothing needs shell word splitting.
    public let arguments: [String]

    /// The repository the command installs from.
    public let repositoryURL: URL

    init(program: String, arguments: [String], repositoryURL: URL) {
        self.program = program
        self.arguments = arguments
        self.repositoryURL = repositoryURL
    }

    /// The command as skills.sh renders it.
    ///
    /// No quoting is applied because every component is restricted to
    /// `CatalogIdentifier`'s character set, which contains no shell metacharacters
    /// and no whitespace.
    public var displayText: String {
        ([program] + arguments).joined(separator: " ")
    }
}
