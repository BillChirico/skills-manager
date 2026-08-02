import Foundation
import Testing

#if canImport(Darwin)
    import Darwin
#endif

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
                "--package",
                "skills@1.5.21",
                "--",
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
        #expect(command.currentDirectoryURL != homeDirectory)
        #expect(
            FileManager.default.fileExists(
                atPath: command.currentDirectoryURL.path(percentEncoded: false)
            ) == false
        )
        #expect(command.environment["HOME"] == homeDirectory.path(percentEncoded: false))
        #expect(command.environment["DISABLE_TELEMETRY"] == "1")
        #expect(command.environment["DO_NOT_TRACK"] == "1")
        #expect(command.environment["GIT_CONFIG_GLOBAL"] == "/dev/null")
        #expect(command.environment["GIT_TERMINAL_PROMPT"] == "0")
        #expect(
            command.environment["NPM_CONFIG_GLOBALCONFIG"]
                == command.currentDirectoryURL.appending(
                    path: "unused-global-npmrc",
                    directoryHint: .notDirectory
                ).path(percentEncoded: false)
        )
        #expect(command.environment["NPM_CONFIG_IGNORE_SCRIPTS"] == "true")
        #expect(command.environment["NPM_CONFIG_PREFER_ONLINE"] == "true")
        #expect(command.environment["NPM_CONFIG_REGISTRY"] == "https://registry.npmjs.org/")
        #expect(command.environment["NPM_CONFIG_USERCONFIG"] == "/dev/null")
        #expect(
            command.environment["PATH"]
                == "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        )
        #expect(command.environment["SECRET_TOKEN"] == nil)
        #expect(result == installedURL)
    }

    @Test("Filesystem and process paths remain unencoded", .bug(id: 24))
    func nativePathsRemainUnencoded() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let homeDirectory = temporaryDirectory.appending(
            path: "Account #50% With Spaces",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: homeDirectory,
            withIntermediateDirectories: true
        )
        let source = try makeSource(agent: .codex, homeDirectory: homeDirectory)
        let installedURL = source.directoryURL.appending(
            path: "swift-testing-pro",
            directoryHint: .isDirectory
        )
        let npxExecutableURL = homeDirectory.appending(
            path: "Node Tools #1/bin/npx",
            directoryHint: .notDirectory
        )
        let runner = RecordingCommandRunner { _ in
            try Self.writeManifest(in: installedURL)
        }
        let manager = SkillsCLIManager(
            homeDirectory: homeDirectory,
            runner: runner,
            npxExecutableURL: npxExecutableURL,
            parentEnvironment: ["PATH": "/usr/bin:/bin"]
        )

        let result = try await manager.install(makeCatalogSkill(), into: source)
        let command = try #require(await runner.commands.first)

        #expect(command.environment["HOME"] == homeDirectory.path(percentEncoded: false))
        #expect(
            command.environment["CODEX_HOME"]
                == homeDirectory.appending(
                    path: ".agents",
                    directoryHint: .isDirectory
                ).path(percentEncoded: false)
        )
        let executableDirectoryPath = npxExecutableURL.deletingLastPathComponent().path(
            percentEncoded: false
        )
        let expectedExecutableDirectory =
            executableDirectoryPath.hasSuffix("/")
            ? executableDirectoryPath.dropLast()
            : Substring(executableDirectoryPath)
        #expect(
            command.environment["PATH"]?.split(separator: ":").first
                == expectedExecutableDirectory
        )
        #expect(result == installedURL)
    }

    @Test("npx discovery accepts an unencoded executable path", .bug(id: 24))
    func npxDiscoveryUsesNativePaths() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let executableDirectory = temporaryDirectory.appending(
            path: "Node Tools #1%",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: executableDirectory,
            withIntermediateDirectories: true
        )
        let npxExecutableURL = executableDirectory.appending(
            path: "npx",
            directoryHint: .notDirectory
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: npxExecutableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: npxExecutableURL.path(percentEncoded: false)
        )

        let result = SkillsCLIManager.locateNpx(
            homeDirectory: temporaryDirectory,
            environment: [
                "PATH": executableDirectory.path(percentEncoded: false)
            ]
        )

        #expect(result == npxExecutableURL)
    }

    @Test("An npx directory containing the PATH delimiter fails closed")
    func pathDelimitedNpxDirectoryIsRejected() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let homeDirectory = temporaryDirectory.appending(path: "home", directoryHint: .isDirectory)
        let source = try makeSource(agent: .claudeCode, homeDirectory: homeDirectory)
        let unsafeNpxURL = temporaryDirectory.appending(
            path: "Node:Tools/npx",
            directoryHint: .notDirectory
        )
        let runner = RecordingCommandRunner()
        let manager = SkillsCLIManager(
            homeDirectory: homeDirectory,
            runner: runner,
            npxExecutableURL: unsafeNpxURL,
            parentEnvironment: [:]
        )

        await #expect(throws: SkillsCLIError.unsafeNpxLocation) {
            try await manager.install(makeCatalogSkill(), into: source)
        }
        #expect(await runner.commands.isEmpty)
    }

    @Test("npx discovery excludes relative inherited PATH entries")
    func npxDiscoveryExcludesRelativeInheritedPathEntries() {
        let result = SkillsCLIManager.inheritedExecutableDirectories(
            from: "relative/bin:/usr/bin::./tools:/opt/node/bin"
        )

        #expect(
            result
                == [
                    URL(filePath: "/usr/bin", directoryHint: .isDirectory),
                    URL(filePath: "/opt/node/bin", directoryHint: .isDirectory),
                ]
        )
    }

    @Test("Remove verifies an unencoded skill directory path", .bug(id: 24))
    func removePostconditionUsesNativePaths() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let homeDirectory = temporaryDirectory.appending(
            path: "Account #50% With Spaces",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: homeDirectory,
            withIntermediateDirectories: true
        )
        let source = try makeSource(agent: .claudeCode, homeDirectory: homeDirectory)
        let skill = try makeInstalledSkill(in: source)
        let runner = RecordingCommandRunner()
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(throws: SkillsCLIError.expectedDirectoryPresent(skill.directoryURL)) {
            try await manager.remove(skill, from: source)
        }
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
                ).path(percentEncoded: false)
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

    @Test("Update fails closed because the CLI cannot scope it to one agent")
    func updateIsRejectedBeforeLaunch() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let source = try makeSource(agent: .cursor, homeDirectory: homeDirectory)
        let skill = try makeInstalledSkill(in: source)
        let runner = RecordingCommandRunner()
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(throws: SkillsCLIError.scopedUpdateUnsupported) {
            try await manager.update(skill, in: source)
        }
        #expect(await runner.commands.isEmpty)
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
                "--package",
                "skills@1.5.21",
                "--",
                "skills",
                "remove",
                "swift-testing-pro",
                "--global",
                "--agent",
                "github-copilot",
                "--yes",
            ])
        #expect(
            FileManager.default.fileExists(
                atPath: skill.directoryURL.path(percentEncoded: false)
            ) == false
        )
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

        await #expect(
            throws: SkillsCLIError.expectedManifestMissing(
                manifestURL,
                observedEntryNames: [],
                additionalEntryCount: 0
            )
        ) {
            try await manager.install(makeCatalogSkill(), into: source)
        }
        #expect(await runner.commands.count == 1)
    }

    @Test("Install postcondition reports a capped, escaped entry delta")
    func installPostconditionReportsCappedEscapedEntryDelta() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let source = try makeSource(agent: .claudeCode, homeDirectory: homeDirectory)
        let expectedManifestURL = source.directoryURL
            .appending(path: "swift-testing-pro", directoryHint: .isDirectory)
            .appending(path: "SKILL.md", directoryHint: .notDirectory)
        let observedEntryNames =
            ["00-forged\nalert"]
            + (1...11).map { String(format: "%02d-created-entry", $0) }
        let preexistingDirectoryName = "preexisting-skill"
        try Self.writeManifest(
            in: source.directoryURL.appending(
                path: preexistingDirectoryName,
                directoryHint: .isDirectory
            )
        )
        let runner = RecordingCommandRunner { _ in
            for entryName in observedEntryNames {
                try Self.writeManifest(
                    in: source.directoryURL.appending(
                        path: entryName,
                        directoryHint: .isDirectory
                    )
                )
            }
        }
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)
        let reportedEntryNames = Array(
            observedEntryNames.sorted().prefix(SkillsCLIError.maximumReportedEntryNames)
        )
        let expectedError = SkillsCLIError.expectedManifestMissing(
            expectedManifestURL,
            observedEntryNames: reportedEntryNames,
            additionalEntryCount: observedEntryNames.count - reportedEntryNames.count
        )

        await #expect(throws: expectedError) {
            try await manager.install(makeCatalogSkill(), into: source)
        }
        let description = try #require(expectedError.errorDescription)
        let firstObservedEntryName = try #require(observedEntryNames.first)
        let finalObservedEntryName = try #require(observedEntryNames.last)
        #expect(description.contains(String(reflecting: firstObservedEntryName)))
        #expect(description.contains("\n") == false)
        #expect(description.contains("(and 2 more)"))
        #expect(description.contains(preexistingDirectoryName) == false)
        #expect(
            FileManager.default.fileExists(
                atPath: source.directoryURL.appending(
                    path: finalObservedEntryName,
                    directoryHint: .isDirectory
                ).path(percentEncoded: false)
            )
        )
    }

    @Test("Install reports entries observed before a nonzero exit")
    func installCommandFailureReportsObservedEntries() async throws {
        try await verifyInstallFailureReport(
            runnerError: .commandFailed(exitCode: 23),
            expectedFailure: .nonzeroExit(23)
        )
    }

    @Test("Install reports entries observed before timeout")
    func installTimeoutReportsObservedEntries() async throws {
        try await verifyInstallFailureReport(
            runnerError: .commandTimedOut,
            expectedFailure: .timedOut
        )
    }

    @Test("Install reports entries observed before cancellation")
    func installCancellationReportsObservedEntries() async throws {
        try await verifyInstallFailureReport(
            runnerError: .commandCancelled,
            expectedFailure: .cancelled
        )
    }

    @Test("Install refuses a preexisting destination as an ambiguous postcondition")
    func installRejectsPreexistingDestination() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let source = try makeSource(agent: .claudeCode, homeDirectory: homeDirectory)
        let destinationURL = source.directoryURL.appending(
            path: "swift-testing-pro",
            directoryHint: .isDirectory
        )
        try Self.writeManifest(in: destinationURL)
        let runner = RecordingCommandRunner()
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(throws: SkillsCLIError.destinationAlreadyExists(destinationURL)) {
            try await manager.install(makeCatalogSkill(), into: source)
        }
        #expect(await runner.commands.isEmpty)
    }

    @Test("Install rejects a dangling manifest symlink")
    func installRejectsDanglingManifestSymlink() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let source = try makeSource(agent: .claudeCode, homeDirectory: homeDirectory)
        let destinationURL = source.directoryURL.appending(
            path: "swift-testing-pro",
            directoryHint: .isDirectory
        )
        let manifestURL = destinationURL.appending(path: "SKILL.md")
        let runner = RecordingCommandRunner { _ in
            try FileManager.default.createDirectory(
                at: destinationURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(
                at: manifestURL,
                withDestinationURL: destinationURL.appending(path: "missing-manifest")
            )
        }
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(throws: SkillsCLIError.symbolicLinkNotAllowed(manifestURL)) {
            try await manager.install(makeCatalogSkill(), into: source)
        }
        #expect(await runner.commands.count == 1)
    }

    @Test("A symlink in a standard source path is rejected before launch")
    func symbolicLinkSourceIsRejected() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let homeDirectory = temporaryDirectory.appending(path: "home", directoryHint: .isDirectory)
        let redirectedClaudeDirectory = temporaryDirectory.appending(
            path: "redirected-claude",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: redirectedClaudeDirectory.appending(path: "skills"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        let linkURL = homeDirectory.appending(path: ".claude", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(
            at: linkURL,
            withDestinationURL: redirectedClaudeDirectory
        )

        let source = try makeSource(agent: .claudeCode, homeDirectory: homeDirectory)
        let runner = RecordingCommandRunner()
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        let normalizedLinkURL = URL(
            filePath: linkURL.path(percentEncoded: false),
            directoryHint: .notDirectory
        )
        await #expect(throws: SkillsCLIError.symbolicLinkNotAllowed(normalizedLinkURL)) {
            try await manager.install(makeCatalogSkill(), into: source)
        }
        #expect(await runner.commands.isEmpty)
    }

    @Test("An installed skill directory cannot redirect removal through a symlink")
    func symbolicLinkSkillIsRejected() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let homeDirectory = temporaryDirectory.appending(path: "home", directoryHint: .isDirectory)
        let source = try makeSource(agent: .claudeCode, homeDirectory: homeDirectory)
        try FileManager.default.createDirectory(
            at: source.directoryURL,
            withIntermediateDirectories: true
        )
        let redirectedSkill = temporaryDirectory.appending(
            path: "outside-skill",
            directoryHint: .isDirectory
        )
        try Self.writeManifest(in: redirectedSkill)
        let skillURL = source.directoryURL.appending(
            path: "swift-testing-pro",
            directoryHint: .isDirectory
        )
        try FileManager.default.createSymbolicLink(
            at: skillURL,
            withDestinationURL: redirectedSkill
        )
        let skill = AgentSkill(
            name: "Swift Testing Pro",
            summary: "Modern Swift Testing guidance",
            directoryURL: skillURL,
            sourceID: source.id
        )
        let runner = RecordingCommandRunner()
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        let normalizedSkillURL = URL(
            filePath: skillURL.path(percentEncoded: false),
            directoryHint: .notDirectory
        )
        await #expect(throws: SkillsCLIError.symbolicLinkNotAllowed(normalizedSkillURL)) {
            try await manager.remove(skill, from: source)
        }
        #expect(await runner.commands.isEmpty)
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

    @Test("A dangling directory symlink cannot satisfy remove's postcondition")
    func removeRejectsDanglingDirectorySymlink() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let source = try makeSource(agent: .claudeCode, homeDirectory: homeDirectory)
        let skill = try makeInstalledSkill(in: source)
        let runner = RecordingCommandRunner { _ in
            try FileManager.default.removeItem(at: skill.directoryURL)
            try FileManager.default.createSymbolicLink(
                at: skill.directoryURL,
                withDestinationURL: source.directoryURL.appending(path: "missing-skill")
            )
        }
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

    @Test("Update availability runs the pinned CLI only inside a disposable home")
    func updateAvailabilityUsesIsolatedHome() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        try writeSkillLock(
            in: homeDirectory,
            skills: ["swift-testing-pro": makeLockEntry(name: "swift-testing-pro")],
            extraRootValues: ["lastSelectedAgents": ["claude-code"]]
        )
        let runner = UpdateCheckCommandRunner(
            output:
                """
                \u{1B}[38;5;145mChecking for skill updates…\u{1B}[0m

                \r\u{1B}[38;5;102mChecking skills from source: paulhudson/Swift-Testing-Pro\u{1B}[0m\u{1B}[K
                \r\u{1B}[K\u{1B}[38;5;145mFound 1 global update(s)\u{1B}[0m

                \u{1B}[38;5;145mUpdating swift-testing-pro…\u{1B}[0m
                  \u{1B}[38;5;145m✓\u{1B}[0m Updated swift-testing-pro

                \u{1B}[38;5;145m✓ Updated 1 skill(s)\u{1B}[0m

                """
        )
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        let updates = try await manager.checkForUpdates()
        let command = try #require(await runner.commands.first)
        let isolatedHomePath = try #require(command.environment["HOME"])
        let isolatedHome = URL(filePath: isolatedHomePath, directoryHint: .isDirectory)
        let codexHomePath = try #require(command.environment["CODEX_HOME"])
        let temporaryDirectoryPath = try #require(command.environment["TMPDIR"])
        let mirroredLockData = try #require(await runner.mirroredLockData)
        let mirroredLock = try #require(
            JSONSerialization.jsonObject(with: mirroredLockData) as? [String: Any]
        )

        let expectedSkillURLs = expectedUpdateDirectoryURLs(
            in: homeDirectory,
            skillName: "swift-testing-pro"
        )
        #expect(expectedSkillURLs.count == 1)
        #expect(updates.checkedSkillDirectoryURLs == expectedSkillURLs)
        #expect(updates.updateAvailableSkillDirectoryURLs == expectedSkillURLs)
        #expect(
            command.arguments
                == [
                    "--yes",
                    "--package",
                    "skills@1.5.21",
                    "--",
                    "skills",
                    "check",
                    "--global",
                    "--yes",
                ]
        )
        #expect(isolatedHome != homeDirectory)
        #expect(
            URL(filePath: codexHomePath, directoryHint: .isDirectory).standardizedFileURL
                == isolatedHome.appending(
                    path: ".agents",
                    directoryHint: .isDirectory
                ).standardizedFileURL
        )
        #expect(
            URL(filePath: temporaryDirectoryPath, directoryHint: .isDirectory)
                .deletingLastPathComponent().standardizedFileURL
                == isolatedHome.standardizedFileURL
        )
        #expect(await runner.temporaryDirectoryExisted)
        #expect(command.environment["SECRET_TOKEN"] == nil)
        #expect(mirroredLock["version"] as? Int == 3)
        #expect(mirroredLock["lastSelectedAgents"] == nil)
        #expect(
            FileManager.default.fileExists(atPath: isolatedHome.path(percentEncoded: false))
                == false
        )
        #expect(
            FileManager.default.fileExists(
                atPath: command.currentDirectoryURL.path(percentEncoded: false)
            ) == false
        )
    }

    @Test("Out-of-order update output fails closed")
    func updateAvailabilityRejectsOutOfOrderOutput() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        try writeSkillLock(
            in: homeDirectory,
            skills: ["swift-testing-pro": makeLockEntry(name: "swift-testing-pro")]
        )
        let runner = UpdateCheckCommandRunner(
            output:
                """
                Checking for skill updates…
                Checking skills from source: paulhudson/Swift-Testing-Pro
                Found 1 global update(s)
                ✓ Updated 1 skill(s)
                Updating swift-testing-pro…
                  ✓ Updated swift-testing-pro
                """
        )
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(throws: SkillsCLIError.updateCheckOutputInvalid) {
            try await manager.checkForUpdates()
        }
    }

    @Test("A confirmed no-update transcript identifies the checked skill")
    func updateAvailabilityParsesNoUpdates() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        try writeSkillLock(
            in: homeDirectory,
            skills: ["swift-testing-pro": makeLockEntry(name: "swift-testing-pro")]
        )
        let runner = UpdateCheckCommandRunner(
            output:
                """
                Checking for skill updates…

                Checking skills from source: paulhudson/Swift-Testing-Pro
                ✓ All global skills are up to date

                """
        )
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        let updates = try await manager.checkForUpdates()

        #expect(
            updates.checkedSkillDirectoryURLs
                == expectedUpdateDirectoryURLs(
                    in: homeDirectory,
                    skillName: "swift-testing-pro"
                )
        )
        #expect(updates.updateAvailableSkillDirectoryURLs.isEmpty)
    }

    @Test("An empty valid lock reports that no installed names were checked")
    func updateAvailabilityPreservesEmptyLockAsUnchecked() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        try writeSkillLock(in: homeDirectory, skills: [:])
        let runner = UpdateCheckCommandRunner(output: "")
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        let availability = try await manager.checkForUpdates()

        #expect(availability.checkedSkillDirectoryURLs.isEmpty)
        #expect(availability.updateAvailableSkillDirectoryURLs.isEmpty)
        #expect(await runner.commands.isEmpty)
    }

    @Test("Unknown update output fails closed and cleans every temporary path")
    func updateAvailabilityRejectsUnknownOutput() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        try writeSkillLock(
            in: homeDirectory,
            skills: ["swift-testing-pro": makeLockEntry(name: "swift-testing-pro")]
        )
        let runner = UpdateCheckCommandRunner(
            output:
                """
                Checking for skill updates…
                attacker-controlled diagnostic
                ✓ All global skills are up to date
                """
        )
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(throws: SkillsCLIError.updateCheckOutputInvalid) {
            try await manager.checkForUpdates()
        }

        let command = try #require(await runner.commands.first)
        let isolatedHomePath = try #require(command.environment["HOME"])
        #expect(FileManager.default.fileExists(atPath: isolatedHomePath) == false)
        #expect(
            FileManager.default.fileExists(
                atPath: command.currentDirectoryURL.path(percentEncoded: false)
            ) == false
        )
    }

    @Test("Inconsistent update counts fail closed")
    func updateAvailabilityRejectsCountMismatch() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        try writeSkillLock(
            in: homeDirectory,
            skills: ["swift-testing-pro": makeLockEntry(name: "swift-testing-pro")]
        )
        let runner = UpdateCheckCommandRunner(
            output:
                """
                Checking for skill updates…
                Checking skills from source: paulhudson/Swift-Testing-Pro
                Found 2 global update(s)
                Updating swift-testing-pro…
                  ✓ Updated swift-testing-pro
                ✓ Updated 1 skill(s)
                """
        )
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(throws: SkillsCLIError.updateCheckOutputInvalid) {
            try await manager.checkForUpdates()
        }
    }

    @Test("Oversized CLI output fails closed without loading it")
    func updateAvailabilityRejectsOversizedOutput() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        try writeSkillLock(
            in: homeDirectory,
            skills: ["swift-testing-pro": makeLockEntry(name: "swift-testing-pro")]
        )
        let runner = UpdateCheckCommandRunner(
            outputData: Data(repeating: 0x41, count: SkillsCLIManager.maximumUpdateOutputBytes + 1)
        )
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(throws: SkillsCLIError.updateCheckOutputInvalid) {
            try await manager.checkForUpdates()
        }
    }

    @Test("An invalid or symbolic lock never launches the CLI", arguments: [false, true])
    func updateAvailabilityRejectsUnsafeLock(isSymbolicLink: Bool) async throws {
        let fixtureRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let homeDirectory = fixtureRoot.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        let lockDirectory = homeDirectory.appending(path: ".agents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
        let lockURL = lockDirectory.appending(path: ".skill-lock.json")

        if isSymbolicLink {
            let target = fixtureRoot.appending(path: "outside-lock.json")
            try Data("{\"version\":3,\"skills\":{}}".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(at: lockURL, withDestinationURL: target)
        } else {
            try Data("{\"version\":2,\"skills\":{}}".utf8).write(to: lockURL)
        }

        let runner = UpdateCheckCommandRunner(output: "")
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(throws: SkillsCLIError.updateCheckLockInvalid) {
            try await manager.checkForUpdates()
        }
        #expect(await runner.commands.isEmpty)
    }

    @Test("A missing global lock is distinct from a malformed lock")
    func updateAvailabilityReportsMissingLock() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        let runner = UpdateCheckCommandRunner(output: "")
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        do {
            _ = try await manager.checkForUpdates()
            Issue.record("Expected a missing-lock error")
        } catch let error as SkillsCLIError {
            #expect(error == .updateCheckLockMissing)
        } catch {
            Issue.record("Wrong error thrown: \(error)")
        }
        #expect(await runner.commands.isEmpty)
    }

    @Test("An oversized lock never launches the CLI")
    func updateAvailabilityRejectsOversizedLock() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        let lockDirectory = homeDirectory.appending(path: ".agents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
        try Data(repeating: 0x20, count: SkillsCLIManager.maximumUpdateLockBytes + 1).write(
            to: lockDirectory.appending(path: ".skill-lock.json")
        )
        let runner = UpdateCheckCommandRunner(output: "")
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(throws: SkillsCLIError.updateCheckLockInvalid) {
            try await manager.checkForUpdates()
        }
        #expect(await runner.commands.isEmpty)
    }

    @Test("Malformed remote source metadata never launches the CLI")
    func updateAvailabilityRejectsMalformedSource() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        var entry = makeLockEntry(name: "swift-testing-pro")
        entry["source"] = "../sensitive"
        try writeSkillLock(
            in: homeDirectory,
            skills: ["swift-testing-pro": entry]
        )
        let runner = UpdateCheckCommandRunner(output: "")
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(throws: SkillsCLIError.updateCheckLockInvalid) {
            try await manager.checkForUpdates()
        }
        #expect(await runner.commands.isEmpty)
    }

    @Test("Entries grouped under one source must agree on remote metadata")
    func updateAvailabilityRejectsInconsistentSourceGroup() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        let firstEntry = makeLockEntry(name: "swift-testing-pro")
        var secondEntry = makeLockEntry(name: "swiftui-pro")
        secondEntry["ref"] = "release"
        try writeSkillLock(
            in: homeDirectory,
            skills: [
                "swift-testing-pro": firstEntry,
                "swiftui-pro": secondEntry,
            ]
        )
        let runner = UpdateCheckCommandRunner(output: "")
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(throws: SkillsCLIError.updateCheckLockInvalid) {
            try await manager.checkForUpdates()
        }
        #expect(await runner.commands.isEmpty)
    }

    @Test("Generic Git locks accept their 64-character folder hashes")
    func updateAvailabilityAcceptsGenericGitHash() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        var entry = makeLockEntry(name: "swift-testing-pro")
        entry["source"] = "https://git.example.com/acme/skills.git"
        entry["sourceType"] = "git"
        entry["sourceUrl"] = "https://git.example.com/acme/skills.git"
        entry["skillFolderHash"] = String(repeating: "b", count: 64)
        try writeSkillLock(
            in: homeDirectory,
            skills: ["swift-testing-pro": entry]
        )
        let runner = UpdateCheckCommandRunner(
            output:
                """
                Checking for skill updates…
                Checking skills from source: https://git.example.com/acme/skills.git
                ✓ All global skills are up to date
                """
        )
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        let updates = try await manager.checkForUpdates()

        #expect(
            updates.checkedSkillDirectoryURLs
                == expectedUpdateDirectoryURLs(
                    in: homeDirectory,
                    skillName: "swift-testing-pro"
                )
        )
        #expect(updates.updateAvailableSkillDirectoryURLs.isEmpty)
    }

    @Test(
        "Every process failure removes the disposable home and working directory",
        arguments: [
            SkillsCLIError.commandCouldNotLaunch,
            .commandFailed(exitCode: 23),
            .commandTimedOut,
            .commandCancelled,
        ]
    )
    func updateAvailabilityCleansUpAfterProcessFailure(error: SkillsCLIError) async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }
        try writeSkillLock(
            in: homeDirectory,
            skills: ["swift-testing-pro": makeLockEntry(name: "swift-testing-pro")]
        )
        let runner = UpdateCheckCommandRunner(output: "", error: error)
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(throws: error) {
            try await manager.checkForUpdates()
        }

        let command = try #require(await runner.commands.first)
        let isolatedHomePath = try #require(command.environment["HOME"])
        #expect(FileManager.default.fileExists(atPath: isolatedHomePath) == false)
        #expect(
            FileManager.default.fileExists(
                atPath: command.currentDirectoryURL.path(percentEncoded: false)
            ) == false
        )
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

    @Test("The Foundation runner captures stdout within an explicit byte limit")
    func processOutputCapture() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let runner = FoundationProcessCommandRunner()
        let command = ProcessCommand(
            executableURL: URL(filePath: "/bin/sh"),
            arguments: ["-c", "printf 'update-result'"],
            environment: ["PATH": "/usr/bin:/bin"],
            currentDirectoryURL: directory,
            maximumStandardOutputBytes: 32
        )

        let output = try #require(try await runner.run(command))

        #expect(output == Data("update-result".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("Captured stdout has no child-visible working-directory artifact")
    func processOutputCaptureIsPipeOnly() async throws {
        let workingDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        let runner = FoundationProcessCommandRunner()
        let command = ProcessCommand(
            executableURL: URL(filePath: "/bin/sh"),
            arguments: [
                "-c",
                "if [ -e update-check.stdout ]; then printf 'artifact'; else printf 'pipe-only'; fi",
            ],
            environment: ["PATH": "/usr/bin:/bin"],
            currentDirectoryURL: workingDirectory,
            maximumStandardOutputBytes: 32
        )

        let output = try #require(try await runner.run(command))

        #expect(output == Data("pipe-only".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: workingDirectory.path).isEmpty)
    }

    @Test("The Foundation runner terminates output that exceeds its byte limit")
    func processOutputLimit() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let runner = FoundationProcessCommandRunner(terminationGracePeriod: 0.05)
        let command = ProcessCommand(
            executableURL: URL(filePath: "/bin/sh"),
            arguments: ["-c", "while :; do printf '0123456789'; done"],
            environment: ["PATH": "/usr/bin:/bin"],
            currentDirectoryURL: directory,
            maximumStandardOutputBytes: 32
        )
        let clock = ContinuousClock()
        let start = clock.now

        await #expect(throws: SkillsCLIError.updateCheckOutputInvalid) {
            try await runner.run(command)
        }

        #expect(start.duration(to: clock.now) < .seconds(2))
    }

    @Test("The Foundation runner terminates a command at its deadline")
    func processTimeout() async throws {
        let runner = FoundationProcessCommandRunner(
            timeout: 0.05,
            terminationGracePeriod: 0.05
        )
        let command = signalIgnoringCommand()
        let clock = ContinuousClock()
        let start = clock.now

        await #expect(throws: SkillsCLIError.commandTimedOut) {
            try await runner.run(command)
        }

        #expect(start.duration(to: clock.now) < .seconds(2))
    }

    @Test("Process errors disclose partial state and descendant risk")
    func processErrorDescriptions() {
        #expect(
            SkillsCLIError.commandFailed(exitCode: 23).errorDescription
                == "The skills CLI exited with status 23. Partial filesystem changes may remain."
        )
        #expect(
            SkillsCLIError.commandTimedOut.errorDescription
                == "The skills CLI exceeded its five-minute limit. Timeout handling targets only the directly launched process; work it already started may still continue."
        )
        #expect(
            SkillsCLIError.commandCancelled.errorDescription
                == "The skills CLI operation was cancelled. Cancellation targets only the directly launched process; work it already started may still continue."
        )
    }

    @Test("Cancelling a task stops the directly launched process")
    func processCancellation() async throws {
        let runner = FoundationProcessCommandRunner(
            timeout: 30,
            terminationGracePeriod: 0.05
        )
        let command = longRunningCommand()
        let task = Task {
            try await runner.run(command)
        }
        try await Task.sleep(for: .milliseconds(50))

        task.cancel()

        await #expect(throws: SkillsCLIError.commandCancelled) {
            try await task.value
        }
    }

    @Test("Cancelling a captured command closes its reader without a descriptor race")
    func processOutputCancellation() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let readinessURL = directory.appending(path: "ready")
        let runner = FoundationProcessCommandRunner(
            timeout: 30,
            terminationGracePeriod: 0.05
        )
        let command = ProcessCommand(
            executableURL: URL(filePath: "/bin/sh"),
            arguments: [
                "-c",
                "printf ready > \"$1\"; printf x; trap '' TERM; while :; do :; done",
                "sh",
                readinessURL.path(percentEncoded: false),
            ],
            environment: ["PATH": "/usr/bin:/bin"],
            currentDirectoryURL: directory,
            maximumStandardOutputBytes: 1_024
        )
        let task = Task {
            try await runner.run(command)
        }
        var didLaunch = false
        for _ in 0..<100 {
            if FileManager.default.fileExists(
                atPath: readinessURL.path(percentEncoded: false)
            ) {
                didLaunch = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard didLaunch else {
            task.cancel()
            _ = await task.result
            Issue.record("The captured subprocess did not signal readiness")
            return
        }
        let clock = ContinuousClock()
        let start = clock.now

        task.cancel()

        await #expect(throws: SkillsCLIError.commandCancelled) {
            try await task.value
        }
        #expect(start.duration(to: clock.now) < .seconds(2))
    }

    #if os(macOS)
        @Test("An inherited stdout writer cannot wedge output draining")
        func processOutputDrainDeadline() async throws {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let childPIDURL = directory.appending(path: "child-pid")
            defer {
                if let pidText = try? String(contentsOf: childPIDURL, encoding: .utf8),
                    let pid = Int32(pidText)
                {
                    _ = Darwin.kill(pid, SIGKILL)
                }
            }
            let runner = FoundationProcessCommandRunner()
            let command = ProcessCommand(
                executableURL: URL(filePath: "/bin/sh"),
                arguments: [
                    "-c",
                    "trap '' HUP; sleep 30 & printf '%s' \"$!\" > \"$1\"; printf 'parent-finished'",
                    "sh",
                    childPIDURL.path(percentEncoded: false),
                ],
                environment: ["PATH": "/usr/bin:/bin"],
                currentDirectoryURL: directory,
                maximumStandardOutputBytes: 32
            )
            let clock = ContinuousClock()
            let start = clock.now

            await #expect(throws: SkillsCLIError.updateCheckOutputInvalid) {
                try await runner.run(command)
            }

            #expect(start.duration(to: clock.now) < .seconds(2))
        }
    #endif

    @Test("Lifecycle commands stay serialized while the process runner is suspended")
    func serializesCommands() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let source = try makeSource(agent: .claudeCode, homeDirectory: homeDirectory)
        let firstSkill = makeCatalogSkill(slug: "first-skill")
        let secondSkill = makeCatalogSkill(slug: "second-skill")
        let runner = SuspendingCommandRunner(sourceDirectory: source.directoryURL)
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

    @Test("A failed command releases the lifecycle operation gate")
    func failureReleasesOperationGate() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let source = try makeSource(agent: .claudeCode, homeDirectory: homeDirectory)
        let runner = FailingThenSucceedingCommandRunner(sourceDirectory: source.directoryURL)
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)

        await #expect(
            throws: SkillsCLIError.installCommandFailed(
                .timedOut,
                observedEntryNames: [],
                additionalEntryCount: 0
            )
        ) {
            try await manager.install(makeCatalogSkill(slug: "first-skill"), into: source)
        }
        let installedURL = try await manager.install(
            makeCatalogSkill(slug: "second-skill"),
            into: source
        )

        #expect(installedURL.lastPathComponent == "second-skill")
        #expect(await runner.commandCount == 2)
    }

    private func makeCatalogSkill() -> CatalogSkill {
        makeCatalogSkill(slug: "swift-testing-pro")
    }

    private func verifyInstallFailureReport(
        runnerError: SkillsCLIError,
        expectedFailure: SkillsCLIError.InstallCommandFailure
    ) async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let source = try makeSource(agent: .claudeCode, homeDirectory: homeDirectory)
        let preexistingEntryName = "preexisting-entry"
        try Self.writeManifest(
            in: source.directoryURL.appending(
                path: preexistingEntryName,
                directoryHint: .isDirectory
            )
        )
        let observedEntryNames =
            ["00-partial\nentry"]
            + (1...11).map { String(format: "%02d-partial-entry", $0) }
        let runner = RecordingCommandRunner { _ in
            for entryName in observedEntryNames {
                try Self.writeManifest(
                    in: source.directoryURL.appending(
                        path: entryName,
                        directoryHint: .isDirectory
                    )
                )
            }
            throw runnerError
        }
        let manager = makeManager(homeDirectory: homeDirectory, runner: runner)
        let reportedEntryNames = Array(
            observedEntryNames.sorted().prefix(SkillsCLIError.maximumReportedEntryNames)
        )
        let expectedError = SkillsCLIError.installCommandFailed(
            expectedFailure,
            observedEntryNames: reportedEntryNames,
            additionalEntryCount: observedEntryNames.count - reportedEntryNames.count
        )

        await #expect(throws: expectedError) {
            try await manager.install(makeCatalogSkill(), into: source)
        }
        let description = try #require(expectedError.errorDescription)
        let firstObservedEntryName = try #require(observedEntryNames.first)
        #expect(description.contains("Entries observed so far:"))
        #expect(description.contains(String(reflecting: firstObservedEntryName)))
        #expect(description.contains("\n") == false)
        #expect(description.contains("(and 2 more)"))
        #expect(description.contains(preexistingEntryName) == false)
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

    private func makeLockEntry(name: String) -> [String: Any] {
        [
            "source": "paulhudson/Swift-Testing-Pro",
            "sourceType": "github",
            "sourceUrl": "https://github.com/paulhudson/Swift-Testing-Pro",
            "ref": "main",
            "skillPath": "skills/\(name)/SKILL.md",
            "skillFolderHash": String(repeating: "a", count: 40),
            "installedAt": "2026-08-01T00:00:00.000Z",
            "updatedAt": "2026-08-01T00:00:00.000Z",
        ]
    }

    private func expectedUpdateDirectoryURLs(
        in homeDirectory: URL,
        skillName: String
    ) -> Set<URL> {
        [
            homeDirectory.appending(
                path: ".agents/skills/\(skillName)",
                directoryHint: .isDirectory
            )
        ]
    }

    private func writeSkillLock(
        in homeDirectory: URL,
        skills: [String: [String: Any]],
        extraRootValues: [String: Any] = [:]
    ) throws {
        let lockDirectory = homeDirectory.appending(path: ".agents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: lockDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var object: [String: Any] = [
            "version": 3,
            "skills": skills,
        ]
        object.merge(extraRootValues) { _, new in new }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: lockDirectory.appending(path: ".skill-lock.json"))
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

    fileprivate static func writeManifest(in directoryURL: URL) throws {
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

    private func longRunningCommand() -> ProcessCommand {
        ProcessCommand(
            executableURL: URL(filePath: "/bin/sh"),
            arguments: ["-c", "exec sleep 30"],
            environment: ["PATH": "/usr/bin:/bin"],
            currentDirectoryURL: URL.temporaryDirectory
        )
    }

    private func signalIgnoringCommand() -> ProcessCommand {
        ProcessCommand(
            executableURL: URL(filePath: "/bin/sh"),
            arguments: ["-c", "trap '' TERM; while :; do :; done"],
            environment: ["PATH": "/usr/bin:/bin"],
            currentDirectoryURL: URL.temporaryDirectory
        )
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

    func run(_ command: ProcessCommand) async throws -> Data? {
        commands.append(command)
        try operation(command)
        return nil
    }
}

private actor UpdateCheckCommandRunner: ProcessCommandRunning {
    private(set) var commands: [ProcessCommand] = []
    private(set) var mirroredLockData: Data?
    private(set) var temporaryDirectoryExisted = false
    private let outputData: Data
    private let error: SkillsCLIError?

    init(output: String, error: SkillsCLIError? = nil) {
        self.outputData = Data(output.utf8)
        self.error = error
    }

    init(outputData: Data, error: SkillsCLIError? = nil) {
        self.outputData = outputData
        self.error = error
    }

    func run(_ command: ProcessCommand) async throws -> Data? {
        commands.append(command)

        if let homePath = command.environment["HOME"] {
            let mirrorURL = URL(filePath: homePath, directoryHint: .isDirectory).appending(
                path: ".agents/.skill-lock.json",
                directoryHint: .notDirectory
            )
            mirroredLockData = try Data(contentsOf: mirrorURL)
        }

        if let temporaryDirectoryPath = command.environment["TMPDIR"] {
            temporaryDirectoryExisted = FileManager.default.fileExists(
                atPath: temporaryDirectoryPath
            )
        }

        if let error {
            throw error
        }
        return outputData
    }
}

private actor SuspendingCommandRunner: ProcessCommandRunning {
    private(set) var commands: [ProcessCommand] = []
    private let sourceDirectory: URL
    private var firstContinuation: CheckedContinuation<Void, Never>?

    init(sourceDirectory: URL) {
        self.sourceDirectory = sourceDirectory
    }

    func run(_ command: ProcessCommand) async throws -> Data? {
        commands.append(command)
        if commands.count == 1 {
            await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
        }

        guard
            let skillOptionIndex = command.arguments.firstIndex(of: "--skill"),
            command.arguments.indices.contains(skillOptionIndex + 1)
        else {
            throw FixtureError()
        }
        let slug = command.arguments[skillOptionIndex + 1]
        try SkillsCLIManagerTests.writeManifest(
            in: sourceDirectory.appending(path: slug, directoryHint: .isDirectory)
        )
        return nil
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

private actor FailingThenSucceedingCommandRunner: ProcessCommandRunning {
    private(set) var commandCount = 0
    private let sourceDirectory: URL

    init(sourceDirectory: URL) {
        self.sourceDirectory = sourceDirectory
    }

    func run(_ command: ProcessCommand) async throws -> Data? {
        commandCount += 1
        if commandCount == 1 {
            throw SkillsCLIError.commandTimedOut
        }

        guard
            let skillOptionIndex = command.arguments.firstIndex(of: "--skill"),
            command.arguments.indices.contains(skillOptionIndex + 1)
        else {
            throw FixtureError()
        }
        let slug = command.arguments[skillOptionIndex + 1]
        try SkillsCLIManagerTests.writeManifest(
            in: sourceDirectory.appending(path: slug, directoryHint: .isDirectory)
        )
        return nil
    }
}
