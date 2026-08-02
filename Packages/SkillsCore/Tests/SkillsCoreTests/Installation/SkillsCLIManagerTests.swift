import Foundation
import Testing

@testable import SkillsCore

struct SkillsCLIManagerTests {
    @Test("Install uses the official non-interactive skills CLI command")
    func installCommand() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let source = try makeSource(agent: .claudeCode, homeDirectory: homeDirectory)
        let installedURL = source.directoryURL.appending(
            path: "swift-testing-pro",
            directoryHint: .isDirectory
        )
        let runner = RecordingCommandRunner { _ in
            try FileManager.default.createDirectory(
                at: installedURL,
                withIntermediateDirectories: true
            )
            try Data("---\nname: swift-testing-pro\n---\n".utf8).write(
                to: installedURL.appending(path: "SKILL.md")
            )
        }
        let manager = SkillsCLIManager(
            homeDirectory: homeDirectory,
            runner: runner,
            npxExecutableURL: URL(filePath: "/usr/local/bin/npx"),
            parentEnvironment: [
                "PATH": "/usr/local/bin:/usr/bin:/bin",
                "LANG": "en_US.UTF-8",
                "SECRET_TOKEN": "must-not-leak",
            ]
        )

        let result = try await manager.install(makeCatalogSkill(), into: source)
        let command = try #require(await runner.commands.first)

        #expect(
            command.arguments == [
                "--yes",
                "skills",
                "add",
                "https://github.com/paulhudson/Swift-Testing-Pro",
                "--skill",
                "swift-testing-pro",
                "--global",
                "--agent",
                "claude-code",
                "--copy",
                "--yes",
            ]
        )
        #expect(command.executableURL == URL(filePath: "/usr/local/bin/npx"))
        #expect(command.currentDirectoryURL == homeDirectory)
        #expect(command.environment["HOME"] == homeDirectory.path())
        #expect(command.environment["DISABLE_TELEMETRY"] == "1")
        #expect(command.environment["DO_NOT_TRACK"] == "1")
        #expect(command.environment["SECRET_TOKEN"] == nil)
        #expect(result == installedURL)
    }

    @Test("Codex installs target the shared agents directory")
    func codexHome() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let source = try makeSource(agent: .codex, homeDirectory: homeDirectory)
        let installedURL = source.directoryURL.appending(
            path: "swift-testing-pro",
            directoryHint: .isDirectory
        )
        let runner = RecordingCommandRunner { _ in
            try Self.writeManifest(in: installedURL)
        }
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        _ = try await manager.install(makeCatalogSkill(), into: source)
        let command = try #require(await runner.commands.first)

        #expect(
            command.environment["CODEX_HOME"]
                == homeDirectory.appending(
                    path: ".agents",
                    directoryHint: .isDirectory
                ).path()
        )
        #expect(
            command.arguments.suffix(5)
                == [
                    "--global",
                    "--agent",
                    "codex",
                    "--copy",
                    "--yes",
                ].suffix(5))
    }

    @Test("Update uses the official global update command")
    func updateCommand() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let source = try makeSource(agent: .cursor, homeDirectory: homeDirectory)
        let skill = try makeInstalledSkill(in: source)
        let runner = RecordingCommandRunner()
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        try await manager.update(skill, in: source)
        let command = try #require(await runner.commands.first)

        #expect(
            command.arguments == [
                "--yes",
                "skills",
                "update",
                "swift-testing-pro",
                "--global",
                "--yes",
            ])
        #expect(command.environment["CODEX_HOME"] == nil)
    }

    @Test("Remove uses the official agent-specific remove command")
    func removeCommand() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let source = try makeSource(agent: .githubCopilot, homeDirectory: homeDirectory)
        let skill = try makeInstalledSkill(in: source)
        let runner = RecordingCommandRunner { _ in
            try FileManager.default.removeItem(at: skill.directoryURL)
        }
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        try await manager.remove(skill, from: source)
        let command = try #require(await runner.commands.first)

        #expect(
            command.arguments == [
                "--yes",
                "skills",
                "remove",
                "swift-testing-pro",
                "--global",
                "--agent",
                "github-copilot",
                "--yes",
            ])
        #expect(FileManager.default.fileExists(atPath: skill.directoryURL.path()) == false)
    }

    @Test("Custom directories remain discoverable but cannot be mutated")
    func customDirectoryIsRejected() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let customDirectory = homeDirectory.appending(
            path: "custom-skills",
            directoryHint: .isDirectory
        )
        let source = SkillSource(
            name: "Custom",
            directoryURL: customDirectory,
            agent: .other
        )
        let runner = RecordingCommandRunner()
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(throws: SkillsCLIError.unsupportedAgent(.other)) {
            try await manager.install(makeCatalogSkill(), into: source)
        }
        #expect(await runner.commands.isEmpty)
    }

    @Test("A standard agent cannot redirect CLI writes to a custom directory")
    func redirectedStandardSourceIsRejected() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let expected = try #require(SkillAgent.claudeCode.defaultSkillsDirectory(in: homeDirectory))
        let actual = homeDirectory.appending(path: "redirected", directoryHint: .isDirectory)
        let source = SkillSource(name: "Redirected", directoryURL: actual, agent: .claudeCode)
        let runner = RecordingCommandRunner()
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(
            throws: SkillsCLIError.unsupportedSourceDirectory(expected: expected, actual: actual)
        ) {
            try await manager.install(makeCatalogSkill(), into: source)
        }
        #expect(await runner.commands.isEmpty)
    }

    @Test("Missing npx fails before a process is launched")
    func missingNpx() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let source = try makeSource(agent: .gemini, homeDirectory: homeDirectory)
        let runner = RecordingCommandRunner()
        let manager = SkillsCLIManager(
            homeDirectory: homeDirectory,
            runner: runner,
            npxExecutableURL: nil,
            parentEnvironment: [:]
        )

        await #expect(throws: SkillsCLIError.npxNotFound) {
            try await manager.install(makeCatalogSkill(), into: source)
        }
        #expect(await runner.commands.isEmpty)
    }

    @Test("An unresolved account home fails closed")
    func missingAccountHome() async {
        let source = SkillSource(
            name: "Claude Code",
            directoryURL: URL(filePath: "/unresolved/.claude/skills"),
            agent: .claudeCode
        )
        let manager = SkillsCLIManager(homeDirectory: nil)

        await #expect(throws: SkillsCLIError.accountHomeUnavailable) {
            try await manager.install(makeCatalogSkill(), into: source)
        }
    }

    @Test("Install verifies that the CLI created a manifest")
    func installPostcondition() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let source = try makeSource(agent: .claudeCode, homeDirectory: homeDirectory)
        let manifestURL = source.directoryURL
            .appending(path: "swift-testing-pro", directoryHint: .isDirectory)
            .appending(path: "SKILL.md", directoryHint: .notDirectory)
        let runner = RecordingCommandRunner()
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(throws: SkillsCLIError.expectedManifestMissing(manifestURL)) {
            try await manager.install(makeCatalogSkill(), into: source)
        }
        #expect(await runner.commands.count == 1)
    }

    @Test("Remove verifies that the CLI deleted the directory")
    func removePostcondition() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let source = try makeSource(agent: .claudeCode, homeDirectory: homeDirectory)
        let skill = try makeInstalledSkill(in: source)
        let runner = RecordingCommandRunner()
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(throws: SkillsCLIError.expectedDirectoryPresent(skill.directoryURL)) {
            try await manager.remove(skill, from: source)
        }
        #expect(await runner.commands.count == 1)
    }

    @Test("Installed skill identifiers cannot be interpreted as CLI options")
    func optionLikeInstalledIdentifierIsRejected() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let source = try makeSource(agent: .claudeCode, homeDirectory: homeDirectory)
        let skill = try makeInstalledSkill(named: "--force", in: source)
        let runner = RecordingCommandRunner()
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(throws: SkillsCLIError.invalidSkillIdentifier("--force")) {
            try await manager.update(skill, in: source)
        }
        #expect(await runner.commands.isEmpty)
    }

    @Test("The Foundation runner reports nonzero exit status")
    func processFailure() async throws {
        let runner = FoundationProcessCommandRunner()
        let command = ProcessCommand(
            executableURL: URL(filePath: "/usr/bin/false"),
            arguments: [],
            environment: [:],
            currentDirectoryURL: URL(filePath: "/tmp", directoryHint: .isDirectory)
        )

        await #expect(throws: SkillsCLIError.commandFailed(exitCode: 1)) {
            try await runner.run(command)
        }
    }

    @Test("Lifecycle commands stay serialized while the process runner is suspended")
    func serializesCommands() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let source = try makeSource(agent: .claudeCode, homeDirectory: homeDirectory)
        let firstSkill = makeCatalogSkill(slug: "first-skill")
        let secondSkill = makeCatalogSkill(slug: "second-skill")
        try Self.writeManifest(
            in: source.directoryURL.appending(path: firstSkill.slug, directoryHint: .isDirectory)
        )
        try Self.writeManifest(
            in: source.directoryURL.appending(path: secondSkill.slug, directoryHint: .isDirectory)
        )
        let runner = SuspendingCommandRunner()
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        let firstInstall = Task {
            try await manager.install(firstSkill, into: source)
        }
        await runner.waitUntilFirstCommandStarted()

        let secondInstall = Task {
            try await manager.install(secondSkill, into: source)
        }
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(await runner.commands.count == 1)

        await runner.resumeFirstCommand()
        _ = try await firstInstall.value
        _ = try await secondInstall.value

        #expect(await runner.commands.count == 2)
    }

    private func makeCatalogSkill() -> CatalogSkill {
        makeCatalogSkill(slug: "swift-testing-pro")
    }

    private func makeCatalogSkill(slug: String) -> CatalogSkill {
        CatalogSkill(
            id: "paulhudson/Swift-Testing-Pro/\(slug)",
            slug: slug,
            name: "Swift Testing Pro",
            source: "paulhudson/Swift-Testing-Pro",
            installs: 6_900
        )
    }

    private func makeManager(
        homeDirectory: URL,
        runner: any ProcessCommandRunning
    ) -> SkillsCLIManager {
        SkillsCLIManager(
            homeDirectory: homeDirectory,
            runner: runner,
            npxExecutableURL: URL(filePath: "/usr/local/bin/npx"),
            parentEnvironment: [
                "PATH": "/usr/local/bin:/usr/bin:/bin",
                "LANG": "en_US.UTF-8",
            ]
        )
    }

    private func makeInstalledSkill(
        named identifier: String = "swift-testing-pro",
        in source: SkillSource
    ) throws -> AgentSkill {
        let directoryURL = source.directoryURL.appending(
            path: identifier,
            directoryHint: .isDirectory
        )
        try Self.writeManifest(in: directoryURL)

        return AgentSkill(
            name: "Swift Testing Pro",
            summary: "Modern Swift Testing guidance",
            directoryURL: directoryURL,
            sourceID: source.id
        )
    }

    private static func writeManifest(in directoryURL: URL) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try Data("---\nname: swift-testing-pro\n---\n".utf8).write(
            to: directoryURL.appending(path: "SKILL.md")
        )
    }

    private func makeSource(
        agent: SkillAgent,
        homeDirectory: URL
    ) throws -> SkillSource {
        guard let directoryURL = agent.defaultSkillsDirectory(in: homeDirectory) else {
            throw FixtureError()
        }

        return SkillSource(
            name: agent.displayName,
            directoryURL: directoryURL,
            agent: agent
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL.temporaryDirectory.appending(
            path: "SkillsCLIManagerTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

private struct FixtureError: Error {}

private actor RecordingCommandRunner: ProcessCommandRunning {
    private(set) var commands: [ProcessCommand] = []
    private let operation: @Sendable (ProcessCommand) throws -> Void

    init(operation: @escaping @Sendable (ProcessCommand) throws -> Void) {
        self.operation = operation
    }

    init() {
        self.operation = { _ in }
    }

    func run(_ command: ProcessCommand) async throws {
        commands.append(command)
        try operation(command)
    }
}

private actor SuspendingCommandRunner: ProcessCommandRunning {
    private(set) var commands: [ProcessCommand] = []
    private var firstContinuation: CheckedContinuation<Void, Never>?

    func run(_ command: ProcessCommand) async throws {
        commands.append(command)
        guard commands.count == 1 else {
            return
        }

        await withCheckedContinuation { continuation in
            firstContinuation = continuation
        }
    }

    func waitUntilFirstCommandStarted() async {
        while firstContinuation == nil {
            await Task.yield()
        }
    }

    func resumeFirstCommand() {
        firstContinuation?.resume()
        firstContinuation = nil
    }
}
