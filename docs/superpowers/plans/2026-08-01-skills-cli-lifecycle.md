# skills.sh CLI Lifecycle Implementation Plan

> **Historical plan:** The implementation has since received a security
> hardening amendment. Current behavior, including the pinned CLI, unavailable
> agent-scoped update, symlink containment, process deadline/cancellation, and
> Hardened Runtime, is authoritative in `docs/ARCHITECTURE.md` and
> `docs/SECURITY.md`. Command examples below record the original plan and must
> not be copied into production unchanged.
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `npx skills` the tested production backend for installing,
updating, and removing skills while keeping UI state synchronized with disk.

**Architecture:** Add an actor-backed `SkillsCLIManager` in `SkillsCore` behind
an injected `SkillManaging` protocol. Both app models share that manager;
catalog installs and library mutations report per-target outcomes and rescan
successful sources. Direct CLI execution requires changing the app from an App
Sandbox product to a disclosed non-sandboxed developer tool.

**Tech Stack:** Swift 6.2 toolchain with Swift 6 language mode, Foundation
`Process`, Observation, SwiftUI, Swift Testing, XcodeGen, macOS 15+

## Global Constraints

- Run no shell; use an executable URL plus an argument vector.
- Accept lifecycle mutations only for validated standard agent directories.
- Never pass unrelated parent-process environment variables to `npx`.
- Disable skills CLI telemetry and npm prompts for app-initiated commands.
- Preserve partial success for multi-directory and multi-skill operations.
- Do not create a PR until Documentation, QA, and Security reviews complete.
- Keep `README.md`, `AGENTS.md`, `CLAUDE.md`, and `docs/ARCHITECTURE.md`
  consistent with production behavior.

---

### Task 1: Build the tested Skills CLI boundary

**Files:**

- Create: `Packages/SkillsCore/Sources/SkillsCore/Installation/SkillsCLIManager.swift`
- Create: `Packages/SkillsCore/Tests/SkillsCoreTests/Installation/SkillsCLIManagerTests.swift`
- Modify: `Packages/SkillsCore/Sources/SkillsCore/Catalog/SkillInstallCommand.swift`
- Modify: `Packages/SkillsCore/Sources/SkillsCore/Models/SkillAgent.swift`

**Interfaces:**

- Produces: `SkillManaging.install(_:into:)`, `update(_:in:)`, and
  `remove(_:from:)` asynchronous operations.
- Produces: `SkillsCLIManager(homeDirectory:)`, shared by both app models.
- Produces: `SkillAgent.skillsCLIIdentifier` for supported agent mappings.
- Consumes: `CatalogSkill.installCommand`, `CatalogIdentifier`, `SkillSource`,
  and `AgentSkill`.

- [ ] **Step 1: Write failing command-construction tests**

```swift
@Test("Install uses the official non-interactive skills CLI command")
func installCommand() async throws {
    let fixture = try CLIFixture(agent: .claudeCode)
    let installedURL = fixture.source.directoryURL.appending(path: "swift-testing-pro")
    await fixture.runner.onRun { _ in
        try FileManager.default.createDirectory(at: installedURL, withIntermediateDirectories: true)
        try Data("---\nname: swift-testing-pro\n---".utf8)
            .write(to: installedURL.appending(path: "SKILL.md"))
    }

    let result = try await fixture.manager.install(makeCatalogSkill(), into: fixture.source)
    let command = try #require(await fixture.runner.commands.first)

    #expect(
        command.arguments == [
            "--yes", "skills", "add",
            "https://github.com/paulhudson/Swift-Testing-Pro",
            "--skill", "swift-testing-pro", "--global",
            "--agent", "claude-code", "--copy", "--yes",
        ]
    )
    #expect(result == installedURL)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```sh
swift test --package-path Packages/SkillsCore --filter SkillsCLIManagerTests
```

Expected: compilation fails because `SkillsCLIManager`, `SkillManaging`, and
the command-runner test seam do not exist.

- [ ] **Step 3: Implement the minimal protocol, command model, locator, and runner**

```swift
public protocol SkillManaging: Sendable {
    func install(_ skill: CatalogSkill, into source: SkillSource) async throws -> URL
    func update(_ skill: AgentSkill, in source: SkillSource) async throws
    func remove(_ skill: AgentSkill, from source: SkillSource) async throws
}

public final actor SkillsCLIManager: SkillManaging {
    public init(homeDirectory: URL?)
    public func install(_ skill: CatalogSkill, into source: SkillSource) async throws -> URL
    public func update(_ skill: AgentSkill, in source: SkillSource) async throws
    public func remove(_ skill: AgentSkill, from source: SkillSource) async throws
}
```

Use `Process.executableURL`, `Process.arguments`, `Process.environment`, and
`Process.currentDirectoryURL`; route standard streams to the null device and
throw a localized error for a nonzero termination status.

- [ ] **Step 4: Add red/green tests for every security and lifecycle branch**

Add tests proving:

```swift
#expect(command.environment["DISABLE_TELEMETRY"] == "1")
#expect(command.environment["DO_NOT_TRACK"] == "1")
#expect(command.environment["SECRET_TOKEN"] == nil)
#expect(command.environment["CODEX_HOME"] == home.appending(path: ".agents").path())
```

Also cover unsupported/custom sources, a leading-option skill directory,
missing `npx`, nonzero exit, missing install output, failed removal
postcondition, update arguments, and remove arguments.

- [ ] **Step 5: Run all SkillsCore tests and refactor while green**

Run:

```sh
swift test --package-path Packages/SkillsCore
```

Expected: all package tests pass with zero failures.

- [ ] **Step 6: Commit the core boundary**

```sh
git add Packages/SkillsCore
git commit -m "feat(core): add skills CLI lifecycle backend"
```

### Task 2: Route catalog installation through `npx`

**Files:**

- Modify: `SkillsManager/Features/Catalog/SkillCatalogModel.swift`
- Modify: `SkillsManager/App/SkillsManagerApp.swift`
- Modify: `Tests/SkillsManagerTests/Catalog/SkillCatalogModelTests.swift`

**Interfaces:**

- Consumes: `SkillManaging.install(_:into:)` from Task 1.
- Produces: the existing ordered `[SkillCatalogModel.InstallOutcome]` contract,
  now backed by one CLI operation per destination.

- [ ] **Step 1: Replace native-installer fixtures with a failing CLI-manager test**

```swift
@Test("Install invokes the skills CLI for every selected directory")
func installsIntoEverySelectedDirectory() async {
    let manager = FixtureSkillManager()
    let model = SkillCatalogModel(catalog: FixtureCatalog(), skillManager: manager)
    let codex = makeSource(name: "Codex", path: "/skills/codex")
    let claude = makeSource(name: "Claude", path: "/skills/claude")

    let outcomes = await model.install(makeSkill(), into: [codex, claude])

    #expect(await manager.installedSourceIDs == [codex.id, claude.id])
    #expect(outcomes.filter(\.didSucceed).count == 2)
}
```

- [ ] **Step 2: Run the app test and verify RED**

Run:

```sh
xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:SkillsManagerTests/SkillCatalogModelTests test
```

Expected: the catalog model still requires package-fetcher and package-installer
dependencies.

- [ ] **Step 3: Replace package fetching/copying with injected CLI operations**

```swift
@ObservationIgnored private let skillManager: any SkillManaging

init(catalog: any SkillCatalogSearching, skillManager: any SkillManaging) {
    self.catalog = catalog
    self.skillManager = skillManager
}
```

Keep existing invalid-entry and busy-state guards. Call
`skillManager.install(skill, into: destination)` sequentially and translate
each result into the existing per-source outcome.

- [ ] **Step 4: Share one manager in app composition**

```swift
let skillManager = SkillsCLIManager(homeDirectory: UserHomeDirectory.current)
```

Inject that exact instance into both `SkillLibraryModel` and
`SkillCatalogModel` so the manager actor serializes lock-file operations.

- [ ] **Step 5: Re-run the focused app test**

Expected: all catalog model tests pass.

- [ ] **Step 6: Commit catalog integration**

```sh
git add SkillsManager/Features/Catalog SkillsManager/App/SkillsManagerApp.swift \
  Tests/SkillsManagerTests/Catalog
git commit -m "feat(catalog): install skills through npx"
```

### Task 3: Make update and remove real asynchronous mutations

**Files:**

- Modify: `SkillsManager/App/SkillLibraryModel.swift`
- Modify: `SkillsManager/Features/Library/SkillList.swift`
- Modify: `SkillsManager/Features/Library/SkillDetail.swift`
- Modify: `Tests/SkillsManagerTests/App/SkillLibraryModelTests.swift`

**Interfaces:**

- Consumes: `SkillManaging.update(_:in:)` and `remove(_:from:)` from Task 1.
- Produces: async `updateSkills(_:)` and `removeSkills(_:)` model actions.
- Produces: observable `mutatingSkillIDs` and `isMutatingSkills` state.

- [ ] **Step 1: Write failing update/remove model tests**

```swift
@Test("Update delegates to the CLI and refreshes successful skills")
func updatesSkillsOnDisk() async {
    let manager = FixtureSkillManager()
    let model = makeLibraryModel(skillManager: manager, skills: [skillWithUpdate])

    await model.updateSkills([skillWithUpdate.id])

    #expect(await manager.updatedSkillIDs == [skillWithUpdate.id])
    #expect(model.mutatingSkillIDs.isEmpty)
}

@Test("Remove keeps a skill visible when the CLI fails")
func keepsFailedRemovalVisible() async {
    let manager = FixtureSkillManager(removalError: FixtureError())
    let model = makeLibraryModel(skillManager: manager, skills: [skill])

    await model.removeSkills([skill.id])

    #expect(model.skills.contains(where: { $0.id == skill.id }))
    #expect(model.presentedError?.title == "Unable to Remove Some Skills")
}
```

- [ ] **Step 2: Run the focused app test and verify RED**

Run the `SkillLibraryModelTests` target with the Task 2 Xcode command pattern.
Expected: the current synchronous methods mutate only memory and expose no busy
state.

- [ ] **Step 3: Implement async partial-success operations**

Snapshot selected skills before awaiting. Mark all requested IDs busy, execute
CLI calls one at a time, collect failures, rescan affected sources, clear cached
update availability for successful updates, and remove only successful removal
IDs. Always clear busy IDs with `defer`.

- [ ] **Step 4: Update SwiftUI action call sites and destructive copy**

```swift
Button("Remove Skill", role: .destructive) {
    let skillIDs = skillIDsPendingRemoval
    skillIDsPendingRemoval.removeAll()
    Task { await model.removeSkills(skillIDs) }
}
```

Run update actions in tracked `Task` blocks, disable actions whose IDs intersect
`mutatingSkillIDs`, and change the confirmation message to say the CLI removes
the folders from disk.

- [ ] **Step 5: Run catalog and library app tests**

Expected: both focused suites pass with zero failures.

- [ ] **Step 6: Commit lifecycle integration**

```sh
git add SkillsManager/App/SkillLibraryModel.swift SkillsManager/Features/Library \
  Tests/SkillsManagerTests/App/SkillLibraryModelTests.swift
git commit -m "feat(library): update and remove skills through npx"
```

### Task 4: Align product configuration and documentation

**Files:**

- Modify: `project.yml`
- Modify: `SkillsManager.xcodeproj/project.pbxproj` through XcodeGen only
- Delete: `SkillsManager/Support/SkillsManager.entitlements`
- Modify: `SkillsManager/Features/Catalog/SkillCatalogView.swift`
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `docs/ARCHITECTURE.md`

**Interfaces:**

- Produces: an unsandboxed app target capable of launching local `npx`.
- Produces: user-facing and contributor-facing disclosure of Node.js 22.20+, CLI
  execution, standard-directory limitations, environment scrubbing, and review
  expectations.

- [ ] **Step 1: Change the authoritative project specification**

Remove `CODE_SIGN_ENTITLEMENTS`, set `ENABLE_APP_SANDBOX: NO`, and remove the
now-unused entitlements file. Do not edit `project.pbxproj` directly.

- [ ] **Step 2: Regenerate the project**

Run:

```sh
make generate
```

Expected: XcodeGen updates `project.pbxproj` from `project.yml` and removes the
entitlements file reference/build setting.

- [ ] **Step 3: Update Discover trust-boundary copy**

Replace the native-copy assurance with concise copy explaining that Skills
Manager runs the official skills CLI through `npx`, that the npm package executes
with user permissions, and that users should review both the source and installed
`SKILL.md`.

- [ ] **Step 4: Update all durable documentation**

Document:

```text
Requirements: macOS 15+, Xcode 26+, XcodeGen 2.46+, Node.js 22.20+ with npx
Lifecycle: npx skills add/update/remove, --copy, --global, non-interactive
Supported mutations: configured standard directories for known agents
Security: no shell, validated argv, scrubbed environment, telemetry disabled,
          no App Sandbox containment
```

Remove stale claims that installation never executes code or that update/remove
semantics are only planned extension points.

- [ ] **Step 5: Run documentation and generated-file checks**

Run:

```sh
git diff --check
git diff --exit-code -- SkillsManager.xcodeproj/project.pbxproj
```

The second command is run after a fresh second `make generate`; expected output
is empty.

- [ ] **Step 6: Commit configuration and documentation**

```sh
git add project.yml SkillsManager.xcodeproj \
  SkillsManager/Features/Catalog/SkillCatalogView.swift README.md AGENTS.md \
  CLAUDE.md docs
git add -A SkillsManager/Support
git commit -m "docs: describe npx lifecycle trust boundary"
```

### Task 5: Verify and prepare the review-only handoff

**Files:**

- Review: every changed file
- No PR creation in this task

**Interfaces:**

- Consumes: all requirements in the design specification and this plan.
- Produces: verified commits and a branch/commit handoff for Documentation, QA,
  and Security reviewers.

- [ ] **Step 1: Format and lint**

Run:

```sh
swift format --configuration .swift-format --in-place --recursive \
  SkillsManager Packages/SkillsCore/Sources Packages/SkillsCore/Tests Tests
make lint
```

Expected: no formatting errors or warnings.

- [ ] **Step 2: Run the complete local validation chain**

Run:

```sh
make check
```

Expected: project generation is stable, all package and app tests pass, and the
macOS app builds without code signing.

- [ ] **Step 3: Review the final diff and requirement coverage**

Run:

```sh
git status --short
git diff origin/main...HEAD --check
git diff --stat origin/main...HEAD
git diff origin/main...HEAD
```

Confirm install/update/remove all call `SkillManaging`, no production model
still uses the native installer or in-memory-only mutation, all user-facing
copy matches the new behavior, and no unrelated files changed.

- [ ] **Step 4: Commit any verification fixes and record the reviewed head**

```sh
git rev-parse HEAD
git log --oneline origin/main..HEAD
```

- [ ] **Step 5: Hand off without opening a PR**

Post one Multica issue reply containing the branch and head SHA, exact
verification evidence and limitations, and explicit first-time mentions for
the Documentation Agent, QA Reviewer, and Security Reviewer. Do not mention the
Chief of Staff as a sign-off and do not create a PR.
