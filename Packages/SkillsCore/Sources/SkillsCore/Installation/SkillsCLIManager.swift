import Foundation

/// Performs supported skill lifecycle mutations through the official `skills` CLI.
public protocol SkillManaging: Sendable {
    /// Installs a catalog skill into a configured source and returns its directory.
    func install(_ skill: CatalogSkill, into source: SkillSource) async throws -> URL

    /// Updates an installed skill in its configured source.
    func update(_ skill: AgentSkill, in source: SkillSource) async throws

    /// Removes an installed skill from its configured source.
    func remove(_ skill: AgentSkill, from source: SkillSource) async throws
}

/// A direct process invocation. Keeping the executable and argument vector separate
/// prevents catalog or manifest values from ever being interpreted by a shell.
struct ProcessCommand: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
    let currentDirectoryURL: URL
}

protocol ProcessCommandRunning: Sendable {
    func run(_ command: ProcessCommand) async throws
}

actor FoundationProcessCommandRunner: ProcessCommandRunning {
    func run(_ command: ProcessCommand) async throws {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = command.currentDirectoryURL
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw SkillsCLIError.commandCouldNotLaunch
        }

        process.waitUntilExit()

        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw SkillsCLIError.commandFailed(exitCode: process.terminationStatus)
        }
    }
}

/// Errors surfaced by official CLI lifecycle operations.
public enum SkillsCLIError: Error, Equatable, LocalizedError, Sendable {
    case accountHomeUnavailable
    case npxNotFound
    case unsupportedAgent(SkillAgent)
    case unsupportedSourceDirectory(expected: URL, actual: URL)
    case skillDoesNotBelongToSource
    case invalidSkillIdentifier(String)
    case commandCouldNotLaunch
    case commandFailed(exitCode: Int32)
    case expectedManifestMissing(URL)
    case expectedDirectoryPresent(URL)

    public var errorDescription: String? {
        switch self {
        case .accountHomeUnavailable:
            "Skills Manager could not resolve the signed-in account's home directory."
        case .npxNotFound:
            "Skills Manager could not find npx. Install Node.js 18 or newer and reopen the app."
        case .unsupportedAgent(let agent):
            "The skills CLI does not support lifecycle changes for the \(agent.displayName) source."
        case .unsupportedSourceDirectory:
            "The skills CLI can change only this agent's standard skills directory."
        case .skillDoesNotBelongToSource:
            "The selected skill is not a direct child of this source directory."
        case .invalidSkillIdentifier:
            "The skill identifier is not safe to pass to the skills CLI."
        case .commandCouldNotLaunch:
            "Skills Manager could not launch npx. Verify that Node.js 18 or newer is installed."
        case .commandFailed(let exitCode):
            "The skills CLI exited with status \(exitCode). No local state was assumed to have changed."
        case .expectedManifestMissing:
            "The skills CLI finished, but the expected SKILL.md was not found."
        case .expectedDirectoryPresent:
            "The skills CLI finished, but the skill directory still exists."
        }
    }
}

/// Actor-backed lifecycle manager for the official `npx skills` CLI.
///
/// The actor also maintains an explicit operation gate because awaiting a separate
/// process runner makes actors reentrant. This keeps CLI lock-file mutations serial
/// even when callers start multiple lifecycle tasks concurrently.
public actor SkillsCLIManager: SkillManaging {
    private struct CLITarget: Sendable {
        let agentIdentifier: String
        let codexHomeDirectory: URL?
    }

    private let homeDirectory: URL
    private let runner: any ProcessCommandRunning
    private let npxExecutableURL: URL?
    private let parentEnvironment: [String: String]
    private let initializationError: SkillsCLIError?

    private var operationIsRunning = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    /// Creates a lifecycle manager using the current user's home directory and environment.
    public init(
        homeDirectory: URL? = FileManager.default.homeDirectoryForCurrentUser
    ) {
        let environment = ProcessInfo.processInfo.environment
        let standardizedHome = homeDirectory?.standardizedFileURL

        self.homeDirectory = standardizedHome ?? URL(filePath: "/", directoryHint: .isDirectory)
        self.runner = FoundationProcessCommandRunner()
        self.npxExecutableURL = standardizedHome.flatMap {
            Self.locateNpx(homeDirectory: $0, environment: environment)
        }
        self.parentEnvironment = environment
        self.initializationError = standardizedHome == nil ? .accountHomeUnavailable : nil
    }

    init(
        homeDirectory: URL,
        runner: any ProcessCommandRunning,
        npxExecutableURL: URL?,
        parentEnvironment: [String: String]
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.runner = runner
        self.npxExecutableURL = npxExecutableURL?.standardizedFileURL
        self.parentEnvironment = parentEnvironment
        self.initializationError = nil
    }

    public func install(_ skill: CatalogSkill, into source: SkillSource) async throws -> URL {
        await beginOperation()
        defer { finishOperation() }

        let target = try cliTarget(for: source)
        guard
            let installCommand = skill.installCommand,
            let slug = CatalogIdentifier.validatedInstallationDirectoryName(skill.slug)
        else {
            throw SkillsCLIError.invalidSkillIdentifier(skill.slug)
        }

        let destinationURL = source.directoryURL.appending(
            path: slug,
            directoryHint: .isDirectory
        )
        let manifestURL = destinationURL.appending(
            path: "SKILL.md",
            directoryHint: .notDirectory
        )

        try await run(
            arguments: ["--yes"] + installCommand.arguments + [
                "--global",
                "--agent",
                target.agentIdentifier,
                "--copy",
                "--yes",
            ],
            target: target
        )

        guard pathExists(at: manifestURL) else {
            throw SkillsCLIError.expectedManifestMissing(manifestURL)
        }

        return destinationURL
    }

    public func update(_ skill: AgentSkill, in source: SkillSource) async throws {
        await beginOperation()
        defer { finishOperation() }

        let target = try cliTarget(for: source)
        let identifier = try validatedIdentifier(for: skill, in: source)
        let manifestURL = skill.directoryURL.appending(
            path: "SKILL.md",
            directoryHint: .notDirectory
        )

        guard pathExists(at: manifestURL) else {
            throw SkillsCLIError.expectedManifestMissing(manifestURL)
        }

        try await run(
            arguments: [
                "--yes",
                "skills",
                "update",
                identifier,
                "--global",
                "--yes",
            ],
            target: target
        )

        guard pathExists(at: manifestURL) else {
            throw SkillsCLIError.expectedManifestMissing(manifestURL)
        }
    }

    public func remove(_ skill: AgentSkill, from source: SkillSource) async throws {
        await beginOperation()
        defer { finishOperation() }

        let target = try cliTarget(for: source)
        let identifier = try validatedIdentifier(for: skill, in: source)

        try await run(
            arguments: [
                "--yes",
                "skills",
                "remove",
                identifier,
                "--global",
                "--agent",
                target.agentIdentifier,
                "--yes",
            ],
            target: target
        )

        guard pathExists(at: skill.directoryURL) == false else {
            throw SkillsCLIError.expectedDirectoryPresent(skill.directoryURL)
        }
    }

    private func beginOperation() async {
        guard operationIsRunning else {
            operationIsRunning = true
            return
        }

        await withCheckedContinuation { continuation in
            operationWaiters.append(continuation)
        }
    }

    private func finishOperation() {
        guard operationWaiters.isEmpty == false else {
            operationIsRunning = false
            return
        }

        operationWaiters.removeFirst().resume()
    }

    private func cliTarget(for source: SkillSource) throws -> CLITarget {
        if let initializationError {
            throw initializationError
        }

        guard
            let expectedDirectory = source.agent.defaultSkillsDirectory(in: homeDirectory),
            let agentIdentifier = source.agent.skillsCLIAgentIdentifier
        else {
            throw SkillsCLIError.unsupportedAgent(source.agent)
        }

        let expected = expectedDirectory.standardizedFileURL
        let actual = source.directoryURL.standardizedFileURL
        guard expected == actual else {
            throw SkillsCLIError.unsupportedSourceDirectory(expected: expected, actual: actual)
        }

        let codexHomeDirectory: URL? =
            switch source.agent {
            case .global, .codex:
                homeDirectory.appending(path: ".agents", directoryHint: .isDirectory)
            default:
                nil
            }

        return CLITarget(
            agentIdentifier: agentIdentifier,
            codexHomeDirectory: codexHomeDirectory
        )
    }

    private func validatedIdentifier(
        for skill: AgentSkill,
        in source: SkillSource
    ) throws -> String {
        let sourceDirectory = source.directoryURL.standardizedFileURL
        let skillDirectory = skill.directoryURL.standardizedFileURL

        guard
            skill.sourceID == source.id,
            skillDirectory.deletingLastPathComponent() == sourceDirectory
        else {
            throw SkillsCLIError.skillDoesNotBelongToSource
        }

        let identifier = skillDirectory.lastPathComponent
        guard
            let validated = CatalogIdentifier.validatedInstallationDirectoryName(identifier)
        else {
            throw SkillsCLIError.invalidSkillIdentifier(identifier)
        }

        return validated
    }

    private func run(arguments: [String], target: CLITarget) async throws {
        guard let npxExecutableURL else {
            throw SkillsCLIError.npxNotFound
        }

        var environment = sanitizedEnvironment(npxExecutableURL: npxExecutableURL)
        if let codexHomeDirectory = target.codexHomeDirectory {
            environment["CODEX_HOME"] = codexHomeDirectory.path(percentEncoded: false)
        }

        try await runner.run(
            ProcessCommand(
                executableURL: npxExecutableURL,
                arguments: arguments,
                environment: environment,
                currentDirectoryURL: homeDirectory
            )
        )
    }

    private func sanitizedEnvironment(npxExecutableURL: URL) -> [String: String] {
        var environment: [String: String] = [
            "HOME": homeDirectory.path(percentEncoded: false),
            "DISABLE_TELEMETRY": "1",
            "DO_NOT_TRACK": "1",
            "NO_COLOR": "1",
            "NPM_CONFIG_AUDIT": "false",
            "NPM_CONFIG_FUND": "false",
            "NPM_CONFIG_UPDATE_NOTIFIER": "false",
            "NPM_CONFIG_YES": "true",
        ]

        for key in ["LANG", "LC_ALL", "TMPDIR"] {
            environment[key] = parentEnvironment[key]
        }

        let executableDirectory = npxExecutableURL.deletingLastPathComponent().path(
            percentEncoded: false
        )
        let inheritedPath = parentEnvironment["PATH"] ?? "/usr/bin:/bin"
        var pathComponents = [executableDirectory]
        pathComponents.append(contentsOf: inheritedPath.split(separator: ":").map(String.init))
        environment["PATH"] = Array(NSOrderedSet(array: pathComponents))
            .compactMap { $0 as? String }
            .joined(separator: ":")

        return environment
    }

    private func pathExists(at url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false)
        )) != nil
    }

    static func locateNpx(
        homeDirectory: URL,
        environment: [String: String]
    ) -> URL? {
        var candidateDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(filePath: String($0), directoryHint: .isDirectory) }

        candidateDirectories.append(contentsOf: [
            homeDirectory.appending(path: ".volta/bin", directoryHint: .isDirectory),
            homeDirectory.appending(path: ".local/bin", directoryHint: .isDirectory),
            homeDirectory.appending(path: ".local/share/mise/shims", directoryHint: .isDirectory),
            homeDirectory.appending(path: ".asdf/shims", directoryHint: .isDirectory),
            URL(filePath: "/opt/homebrew/bin", directoryHint: .isDirectory),
            URL(filePath: "/usr/local/bin", directoryHint: .isDirectory),
            URL(filePath: "/usr/bin", directoryHint: .isDirectory),
            URL(filePath: "/bin", directoryHint: .isDirectory),
        ])
        candidateDirectories.append(contentsOf: versionManagerBinDirectories(in: homeDirectory))

        for directory in candidateDirectories {
            let candidate = directory.appending(path: "npx", directoryHint: .notDirectory)
            if FileManager.default.isExecutableFile(
                atPath: candidate.path(percentEncoded: false)
            ) {
                return candidate
            }
        }

        return nil
    }

    private static func versionManagerBinDirectories(in homeDirectory: URL) -> [URL] {
        let roots = [
            homeDirectory.appending(path: ".nvm/versions/node", directoryHint: .isDirectory),
            homeDirectory.appending(
                path: "Library/Application Support/fnm/node-versions",
                directoryHint: .isDirectory
            ),
        ]

        return roots.flatMap { root -> [URL] in
            guard
                let versions = try? FileManager.default.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
            else {
                return []
            }

            return versions.sorted(by: versionDirectoryComesFirst).map { version in
                if root.lastPathComponent == "node-versions" {
                    return version.appending(
                        path: "installation/bin",
                        directoryHint: .isDirectory
                    )
                }

                return version.appending(path: "bin", directoryHint: .isDirectory)
            }
        }
    }

    private static func versionDirectoryComesFirst(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsComponents = numericVersionComponents(lhs.lastPathComponent)
        let rhsComponents = numericVersionComponents(rhs.lastPathComponent)
        let componentCount = max(lhsComponents.count, rhsComponents.count)

        for index in 0..<componentCount {
            let lhsComponent = index < lhsComponents.count ? lhsComponents[index] : 0
            let rhsComponent = index < rhsComponents.count ? rhsComponents[index] : 0
            if lhsComponent != rhsComponent {
                return lhsComponent > rhsComponent
            }
        }

        return lhs.lastPathComponent > rhs.lastPathComponent
    }

    private static func numericVersionComponents(_ value: String) -> [Int] {
        value
            .split { $0.isNumber == false }
            .compactMap { Int($0) }
    }
}

private extension SkillAgent {
    var skillsCLIAgentIdentifier: String? {
        switch self {
        case .global, .codex:
            "codex"
        case .claudeCode:
            "claude-code"
        case .cursor:
            "cursor"
        case .githubCopilot:
            "github-copilot"
        case .gemini:
            "gemini-cli"
        case .other:
            nil
        }
    }
}
