import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

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

struct FoundationProcessCommandRunner: ProcessCommandRunning {
    private let timeout: TimeInterval
    private let terminationGracePeriod: TimeInterval

    init(
        timeout: TimeInterval = 300,
        terminationGracePeriod: TimeInterval = 1
    ) {
        self.timeout = timeout
        self.terminationGracePeriod = terminationGracePeriod
    }

    func run(_ command: ProcessCommand) async throws {
        let execution = ProcessExecution(
            command: command,
            timeout: timeout,
            terminationGracePeriod: terminationGracePeriod
        )
        try await execution.run()
    }
}

/// Coordinates Foundation's callback-based process API with structured
/// cancellation. Access is protected by `lock`; Foundation does not declare
/// `Process` as Sendable even though this wrapper serializes every access.
private final class ProcessExecution: @unchecked Sendable {
    private let process: Process
    private let timeout: TimeInterval
    private let terminationGracePeriod: TimeInterval
    private let lock = NSLock()

    private var continuation: CheckedContinuation<Void, any Error>?
    private var requestedFailure: SkillsCLIError?
    private var timeoutWorkItem: DispatchWorkItem?
    private var forceTerminationWorkItem: DispatchWorkItem?
    private var isComplete = false
    private var didLaunch = false

    init(
        command: ProcessCommand,
        timeout: TimeInterval,
        terminationGracePeriod: TimeInterval
    ) {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = command.currentDirectoryURL
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        self.process = process
        self.timeout = timeout
        self.terminationGracePeriod = terminationGracePeriod
    }

    func run() async throws {
        if Task.isCancelled {
            throw SkillsCLIError.commandCancelled
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                start(continuation: continuation)
            }
        } onCancel: {
            self.requestStop(because: .commandCancelled)
        }
    }

    private func start(continuation: CheckedContinuation<Void, any Error>) {
        lock.lock()

        if let requestedFailure {
            isComplete = true
            lock.unlock()
            continuation.resume(throwing: requestedFailure)
            return
        }

        self.continuation = continuation
        process.terminationHandler = { [self] process in
            processDidTerminate(process)
        }

        do {
            try process.run()
            didLaunch = true
        } catch {
            isComplete = true
            self.continuation = nil
            process.terminationHandler = nil
            lock.unlock()
            continuation.resume(throwing: SkillsCLIError.commandCouldNotLaunch)
            return
        }

        let timeoutWorkItem = DispatchWorkItem { [self] in
            requestStop(because: .commandTimedOut)
        }
        self.timeoutWorkItem = timeoutWorkItem
        lock.unlock()

        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + max(timeout, 0),
            execute: timeoutWorkItem
        )
    }

    private func requestStop(because failure: SkillsCLIError) {
        lock.lock()
        guard isComplete == false else {
            lock.unlock()
            return
        }

        guard requestedFailure == nil else {
            lock.unlock()
            return
        }
        requestedFailure = failure

        guard didLaunch, process.isRunning else {
            lock.unlock()
            return
        }

        let processIdentifier = process.processIdentifier
        lock.unlock()

        process.terminate()

        let forceTerminationWorkItem = DispatchWorkItem { [self] in
            forceTerminateIfNeeded(processIdentifier: processIdentifier)
        }

        lock.lock()
        guard isComplete == false else {
            lock.unlock()
            return
        }
        self.forceTerminationWorkItem?.cancel()
        self.forceTerminationWorkItem = forceTerminationWorkItem
        lock.unlock()

        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + max(terminationGracePeriod, 0),
            execute: forceTerminationWorkItem
        )
    }

    private func forceTerminateIfNeeded(processIdentifier: Int32) {
        lock.lock()
        defer { lock.unlock() }

        guard
            isComplete == false,
            process.isRunning,
            process.processIdentifier == processIdentifier
        else {
            return
        }

        // Keep the liveness decision and signal in one critical section so the
        // launched process cannot be reaped and its pid reused between them.
        #if canImport(Darwin)
            _ = Darwin.kill(processIdentifier, SIGKILL)
        #elseif canImport(Glibc)
            _ = Glibc.kill(processIdentifier, SIGKILL)
        #else
            process.interrupt()
        #endif
    }

    private func processDidTerminate(_ process: Process) {
        lock.lock()
        guard isComplete == false else {
            lock.unlock()
            return
        }

        isComplete = true
        timeoutWorkItem?.cancel()
        forceTerminationWorkItem?.cancel()

        let continuation = continuation
        self.continuation = nil
        let result: Result<Void, any Error>
        if let requestedFailure {
            result = .failure(requestedFailure)
        } else if process.terminationReason == .exit, process.terminationStatus == 0 {
            result = .success(())
        } else {
            result = .failure(SkillsCLIError.commandFailed(exitCode: process.terminationStatus))
        }
        lock.unlock()

        process.terminationHandler = nil
        continuation?.resume(with: result)
    }
}

/// Errors surfaced by official CLI lifecycle operations.
public enum SkillsCLIError: Error, Equatable, LocalizedError, Sendable {
    public enum InstallCommandFailure: Equatable, Sendable {
        case nonzeroExit(Int32)
        case timedOut
        case cancelled
    }

    static let maximumReportedEntryNames = 10

    case accountHomeUnavailable
    case npxNotFound
    case unsupportedAgent(SkillAgent)
    case unsupportedSourceDirectory(expected: URL, actual: URL)
    case skillDoesNotBelongToSource
    case invalidSkillIdentifier(String)
    case scopedUpdateUnsupported
    case symbolicLinkNotAllowed(URL)
    case destinationAlreadyExists(URL)
    case unsafeNpxLocation
    case workingDirectoryUnavailable
    case commandCouldNotLaunch
    case commandFailed(exitCode: Int32)
    case commandTimedOut
    case commandCancelled
    case installCommandFailed(
        InstallCommandFailure,
        observedEntryNames: [String],
        additionalEntryCount: Int
    )
    case expectedManifestMissing(
        URL,
        observedEntryNames: [String],
        additionalEntryCount: Int
    )
    case expectedDirectoryPresent(URL)

    public var errorDescription: String? {
        switch self {
        case .accountHomeUnavailable:
            "Skills Manager could not resolve the signed-in account's home directory."
        case .npxNotFound:
            "Skills Manager could not find npx. Install Node.js 22.20 or newer and reopen the app."
        case .unsupportedAgent(let agent):
            "The skills CLI does not support lifecycle changes for the \(agent.displayName) source."
        case .unsupportedSourceDirectory:
            "The skills CLI can change only this agent's standard skills directory."
        case .skillDoesNotBelongToSource:
            "The selected skill is not a direct child of this source directory."
        case .invalidSkillIdentifier:
            "The skill identifier is not safe to pass to the skills CLI."
        case .scopedUpdateUnsupported:
            "The pinned skills CLI cannot limit an update to one agent directory. Reinstall the skill from its trusted source instead."
        case .symbolicLinkNotAllowed:
            "Skills Manager stopped because a lifecycle path contains a symbolic link."
        case .destinationAlreadyExists:
            "The install destination already exists. Remove it or use a separately verified update flow."
        case .unsafeNpxLocation:
            "Skills Manager cannot safely construct an executable search path for this npx installation."
        case .workingDirectoryUnavailable:
            "Skills Manager could not create a private working directory for the skills CLI."
        case .commandCouldNotLaunch:
            "Skills Manager could not launch npx. Verify that Node.js 22.20 or newer is installed."
        case .commandFailed(let exitCode):
            "The skills CLI exited with status \(exitCode). Partial filesystem changes may remain."
        case .commandTimedOut:
            "The skills CLI exceeded its five-minute limit. Timeout handling targets only the directly launched process; work it already started may still continue."
        case .commandCancelled:
            "The skills CLI operation was cancelled. Cancellation targets only the directly launched process; work it already started may still continue."
        case .installCommandFailed(
            let failure,
            let observedEntryNames,
            let additionalEntryCount
        ):
            Self.installCommandFailureDescription(
                failure,
                observedEntryNames: observedEntryNames,
                additionalEntryCount: additionalEntryCount
            )
        case .expectedManifestMissing(
            _,
            let observedEntryNames,
            let additionalEntryCount
        ):
            "The skills CLI finished, but the expected regular, non-symbolic SKILL.md was not found. \(Self.observedEntriesDescription(observedEntryNames, additionalEntryCount: additionalEntryCount))"
        case .expectedDirectoryPresent:
            "The skills CLI finished, but the skill directory still exists."
        }
    }

    private static func installCommandFailureDescription(
        _ failure: InstallCommandFailure,
        observedEntryNames: [String],
        additionalEntryCount: Int
    ) -> String {
        let failureDescription =
            switch failure {
            case .nonzeroExit(let exitCode):
                "The skills CLI exited with status \(exitCode). Partial filesystem changes may remain."
            case .timedOut:
                "The skills CLI exceeded its five-minute limit. Timeout handling targets only the directly launched process; work it already started may still continue."
            case .cancelled:
                "The skills CLI operation was cancelled. Cancellation targets only the directly launched process; work it already started may still continue."
            }

        return
            "\(failureDescription) \(observedEntriesDescription(observedEntryNames, additionalEntryCount: additionalEntryCount))"
    }

    private static func observedEntriesDescription(
        _ observedEntryNames: [String],
        additionalEntryCount: Int
    ) -> String {
        let sortedEntryNames = observedEntryNames.sorted()
        let reportedEntryNames = Array(sortedEntryNames.prefix(maximumReportedEntryNames))
        let omittedEntryCount =
            max(additionalEntryCount, 0)
            + max(sortedEntryNames.count - reportedEntryNames.count, 0)

        guard reportedEntryNames.isEmpty == false else {
            return
                "No new entries were observed so far. Existing entries or later descendant writes may still have changed."
        }

        // Entry names can be repository-controlled. Reflection escapes embedded
        // newlines and control characters before the text reaches an alert.
        let escapedEntryNames = reportedEntryNames.map { String(reflecting: $0) }
        let omittedDescription =
            omittedEntryCount > 0 ? " (and \(omittedEntryCount) more)" : ""

        return
            "Entries observed so far: \(escapedEntryNames.joined(separator: ", "))\(omittedDescription). These entries remain on disk; existing entries or later descendant writes may also have changed."
    }
}

/// Actor-backed lifecycle manager for the official `npx skills` CLI.
///
/// The actor also maintains an explicit operation gate because awaiting a separate
/// process runner makes actors reentrant. This keeps CLI lock-file mutations serial
/// even when callers start multiple lifecycle tasks concurrently.
public actor SkillsCLIManager: SkillManaging {
    /// The audited npm release used by every lifecycle command. The published
    /// tarball's SHA-512 integrity is recorded in `docs/SECURITY.md`.
    static let skillsPackageSpecifier = "skills@1.5.21"

    private struct CLITarget: Sendable {
        let agentIdentifier: String
        let codexHomeDirectory: URL?
    }

    private struct ObservedEntryReport: Sendable {
        let entryNames: [String]
        let additionalEntryCount: Int
    }

    private let homeDirectory: URL
    private let runner: any ProcessCommandRunning
    private let npxExecutableURL: URL?
    private let parentEnvironment: [String: String]
    private let initializationError: SkillsCLIError?

    private var operationIsRunning = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    /// Creates a lifecycle manager using the resolved account home and current environment.
    public init(
        homeDirectory: URL?
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

        guard fileSystemEntry(at: destinationURL) == .missing else {
            throw SkillsCLIError.destinationAlreadyExists(destinationURL)
        }
        let sourceEntryNamesBeforeInstall = directoryEntryNames(at: source.directoryURL)

        do {
            try await run(
                arguments: installCommand.arguments + [
                    "--global",
                    "--agent",
                    target.agentIdentifier,
                    "--copy",
                    "--yes",
                ],
                target: target
            )
        } catch let error as SkillsCLIError {
            let failure: SkillsCLIError.InstallCommandFailure
            switch error {
            case .commandFailed(let exitCode):
                failure = .nonzeroExit(exitCode)
            case .commandTimedOut:
                failure = .timedOut
            case .commandCancelled:
                failure = .cancelled
            default:
                throw error
            }

            _ = try cliTarget(for: source)
            let report = observedEntryReport(
                at: source.directoryURL,
                since: sourceEntryNamesBeforeInstall
            )
            throw SkillsCLIError.installCommandFailed(
                failure,
                observedEntryNames: report.entryNames,
                additionalEntryCount: report.additionalEntryCount
            )
        }

        _ = try cliTarget(for: source)
        let report = observedEntryReport(
            at: source.directoryURL,
            since: sourceEntryNamesBeforeInstall
        )
        try validateInstalledSkill(
            at: destinationURL,
            manifestURL: manifestURL,
            in: source.directoryURL,
            observedEntryNames: report.entryNames,
            additionalEntryCount: report.additionalEntryCount
        )

        return destinationURL
    }

    public func update(_ skill: AgentSkill, in source: SkillSource) async throws {
        await beginOperation()
        defer { finishOperation() }

        _ = try cliTarget(for: source)
        _ = try validatedIdentifier(for: skill, in: source)

        // skills@1.5.21 supports global/project update scope and a skill-name
        // filter, but it has no --agent option. Running it here could therefore
        // mutate other agents that share the global lock. Fail closed until the
        // upstream CLI exposes an agent-scoped update contract.
        throw SkillsCLIError.scopedUpdateUnsupported
    }

    public func remove(_ skill: AgentSkill, from source: SkillSource) async throws {
        await beginOperation()
        defer { finishOperation() }

        let target = try cliTarget(for: source)
        let identifier = try validatedIdentifier(for: skill, in: source)

        try await run(
            arguments: [
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

        _ = try cliTarget(for: source)
        guard fileSystemEntry(at: skill.directoryURL) == .missing else {
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
        try rejectSymbolicLinks(from: homeDirectory, through: actual)

        let resolvedHome = homeDirectory.resolvingSymlinksInPath().standardizedFileURL
        let resolvedActual = actual.resolvingSymlinksInPath().standardizedFileURL
        guard path(resolvedActual, isWithin: resolvedHome) else {
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

        try rejectSymbolicLinks(from: sourceDirectory, through: skillDirectory)
        guard
            fileSystemEntry(at: skillDirectory) == .directory,
            skillDirectory.resolvingSymlinksInPath().deletingLastPathComponent()
                == sourceDirectory.resolvingSymlinksInPath()
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

        let workingDirectory = try makePrivateWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        var environment = try sanitizedEnvironment(
            npxExecutableURL: npxExecutableURL,
            workingDirectory: workingDirectory
        )
        if let codexHomeDirectory = target.codexHomeDirectory {
            environment["CODEX_HOME"] = codexHomeDirectory.path(percentEncoded: false)
        }

        try await runner.run(
            ProcessCommand(
                executableURL: npxExecutableURL,
                arguments: [
                    "--yes",
                    "--package",
                    Self.skillsPackageSpecifier,
                    "--",
                ] + arguments,
                environment: environment,
                currentDirectoryURL: workingDirectory
            )
        )
    }

    private func sanitizedEnvironment(
        npxExecutableURL: URL,
        workingDirectory: URL
    ) throws -> [String: String] {
        var environment: [String: String] = [
            "HOME": homeDirectory.path(percentEncoded: false),
            "DISABLE_TELEMETRY": "1",
            "DO_NOT_TRACK": "1",
            "NO_COLOR": "1",
            "NPM_CONFIG_AUDIT": "false",
            "NPM_CONFIG_FUND": "false",
            "NPM_CONFIG_GLOBALCONFIG": workingDirectory.appending(
                path: "unused-global-npmrc",
                directoryHint: .notDirectory
            ).path(percentEncoded: false),
            "NPM_CONFIG_IGNORE_SCRIPTS": "true",
            "NPM_CONFIG_PREFER_ONLINE": "true",
            "NPM_CONFIG_REGISTRY": "https://registry.npmjs.org/",
            "NPM_CONFIG_UPDATE_NOTIFIER": "false",
            "NPM_CONFIG_USERCONFIG": "/dev/null",
            "NPM_CONFIG_YES": "true",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
        ]

        for key in ["LANG", "LC_ALL", "TMPDIR"] {
            environment[key] = parentEnvironment[key]
        }

        let executableDirectoryPath = npxExecutableURL.deletingLastPathComponent().path(
            percentEncoded: false
        )
        guard
            let executableDirectory = Self.validatedExecutableSearchPathComponent(
                executableDirectoryPath
            )
        else {
            throw SkillsCLIError.unsafeNpxLocation
        }
        let pathComponents = [
            executableDirectory,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        var seenPathComponents = Set<String>()
        environment["PATH"] =
            pathComponents
            .filter { seenPathComponents.insert($0).inserted }
            .joined(separator: ":")

        return environment
    }

    private enum FileSystemEntry {
        case missing
        case symbolicLink
        case directory
        case regularFile
        case other
    }

    private func fileSystemEntry(at url: URL) -> FileSystemEntry {
        var path = url.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil {
            return .symbolicLink
        }

        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            let type = attributes[.type] as? FileAttributeType
        else {
            return .missing
        }

        switch type {
        case .typeDirectory:
            return .directory
        case .typeRegular:
            return .regularFile
        case .typeSymbolicLink:
            return .symbolicLink
        default:
            return .other
        }
    }

    private func rejectSymbolicLinks(from rootURL: URL, through targetURL: URL) throws {
        let root = rootURL.standardizedFileURL
        let target = targetURL.standardizedFileURL
        let rootComponents = root.pathComponents
        let targetComponents = target.pathComponents

        guard targetComponents.starts(with: rootComponents) else {
            throw SkillsCLIError.skillDoesNotBelongToSource
        }

        var candidate = root
        if fileSystemEntry(at: candidate) == .symbolicLink {
            throw SkillsCLIError.symbolicLinkNotAllowed(candidate)
        }

        for component in targetComponents.dropFirst(rootComponents.count) {
            candidate.append(path: component)
            if fileSystemEntry(at: candidate) == .symbolicLink {
                throw SkillsCLIError.symbolicLinkNotAllowed(candidate)
            }
        }
    }

    private func path(_ candidate: URL, isWithin root: URL) -> Bool {
        candidate.pathComponents.starts(with: root.pathComponents)
    }

    private func validateInstalledSkill(
        at directoryURL: URL,
        manifestURL: URL,
        in sourceDirectory: URL,
        observedEntryNames: [String],
        additionalEntryCount: Int
    ) throws {
        try rejectSymbolicLinks(from: sourceDirectory, through: manifestURL)

        guard
            fileSystemEntry(at: directoryURL) == .directory,
            directoryURL.resolvingSymlinksInPath().deletingLastPathComponent()
                == sourceDirectory.resolvingSymlinksInPath()
        else {
            throw SkillsCLIError.expectedManifestMissing(
                manifestURL,
                observedEntryNames: observedEntryNames,
                additionalEntryCount: additionalEntryCount
            )
        }

        guard fileSystemEntry(at: manifestURL) == .regularFile else {
            throw SkillsCLIError.expectedManifestMissing(
                manifestURL,
                observedEntryNames: observedEntryNames,
                additionalEntryCount: additionalEntryCount
            )
        }
    }

    private func observedEntryReport(
        at directoryURL: URL,
        since previousEntryNames: Set<String>
    ) -> ObservedEntryReport {
        let observedEntryNames = directoryEntryNames(at: directoryURL)
            .subtracting(previousEntryNames)
            .sorted()
        let reportedEntryNames = Array(
            observedEntryNames.prefix(SkillsCLIError.maximumReportedEntryNames)
        )

        return ObservedEntryReport(
            entryNames: reportedEntryNames,
            additionalEntryCount: observedEntryNames.count - reportedEntryNames.count
        )
    }

    private func directoryEntryNames(at directoryURL: URL) -> Set<String> {
        guard fileSystemEntry(at: directoryURL) == .directory else {
            return []
        }

        return Set(
            (try? FileManager.default.contentsOfDirectory(
                atPath: directoryURL.path(percentEncoded: false)
            )) ?? []
        )
    }

    private func makePrivateWorkingDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SkillsManager-CLI-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            return directory
        } catch {
            throw SkillsCLIError.workingDirectoryUnavailable
        }
    }

    static func locateNpx(
        homeDirectory: URL,
        environment: [String: String]
    ) -> URL? {
        var candidateDirectories = inheritedExecutableDirectories(
            from: environment["PATH"] ?? ""
        )

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
            guard
                let directoryPath = validatedExecutableSearchPathComponent(
                    directory.path(percentEncoded: false)
                )
            else {
                continue
            }
            let candidate = URL(filePath: directoryPath, directoryHint: .isDirectory).appending(
                path: "npx",
                directoryHint: .notDirectory
            )
            if FileManager.default.isExecutableFile(
                atPath: candidate.path(percentEncoded: false)
            ) {
                return candidate
            }
        }

        return nil
    }

    static func inheritedExecutableDirectories(from searchPath: String) -> [URL] {
        searchPath
            .split(separator: ":", omittingEmptySubsequences: false)
            .compactMap { validatedExecutableSearchPathComponent(String($0)) }
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    static func validatedExecutableSearchPathComponent(_ component: String) -> String? {
        var normalizedComponent = component
        while normalizedComponent.count > 1 && normalizedComponent.hasSuffix("/") {
            normalizedComponent.removeLast()
        }

        guard
            normalizedComponent.hasPrefix("/"),
            normalizedComponent.contains(":") == false
        else {
            return nil
        }

        return normalizedComponent
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
