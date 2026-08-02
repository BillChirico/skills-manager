# skills.sh CLI Lifecycle Design

## Goal

Make the official `skills` CLI, launched through `npx`, the production backend
for installing and removing skills. A successful app action must represent a
successful on-disk mutation, not only an in-memory state change. Update must fail
closed while the upstream CLI cannot scope that mutation to one agent.

## Current behavior and root cause

Discover currently downloads GitHub files itself and copies them with
`FileSystemSkillPackageInstaller`. Library update and remove actions only edit
the observable `AgentSkill` array: update copies `availableVersion` into
`installedVersion`, and remove hides the row while leaving the directory on
disk. These three paths therefore have different authorities and the latter two
do not perform the operation their labels promise.

## Considered approaches

### 1. Direct CLI backend in the application process (selected)

Launch the locally installed `npx` executable with a validated argument vector,
non-interactive `skills` flags, a minimal environment, and no shell. Keep one
injected actor-backed manager as the serialization boundary for install,
update, and remove. This is the smallest implementation that makes the official
CLI authoritative and keeps command construction unit-testable.

The application must no longer use App Sandbox. Apple documents that a child
created by `Process` inherits the parent sandbox, while security-scoped access
granted after launch is not a reliable capability boundary for an external
Node/npm process. Running the requested external CLI and letting it manage its
lock data and agent directories therefore conflicts with the current sandboxed
architecture.

### 2. Unsandboxed XPC or helper application

Keep the SwiftUI process sandboxed and add an independently privileged helper.
This provides a stronger process boundary, but it adds a new target, signing and
IPC contracts, lifecycle management, authorization rules, and a larger review
surface. The helper would still execute the same npm package outside the main
sandbox. This is disproportionate for the current single-user developer tool.

### 3. Run the CLI in a staging home and copy files natively

Point `npx skills` at an app-controlled temporary home, then copy its output to
the selected directory. This retains more sandboxing, but native copying would
remain the actual install/remove backend, the CLI lock file would not describe
the real destinations, and `skills update` could not authoritatively manage
existing installations. It does not meet the issue's lifecycle requirement.

## Architecture

`SkillsCore` will expose a `SkillManaging` protocol with asynchronous install,
update, and remove operations. `SkillsCLIManager` will implement it and own:

- supported `SkillAgent` to official CLI identifier mapping;
- validation that a configured source is that agent's standard account-level
  directory;
- catalog and installed-skill argument validation;
- `npx` discovery from absolute, delimiter-safe GUI process path entries and
  common Node installation paths;
- an exact reviewed npm package version and scrubbed child environment;
- direct, deadline-bound `Process` execution without a shell;
- symlink-free lifecycle path containment; and
- stale-state-resistant checks for the expected manifest or removed directory.

The same manager instance is injected into `SkillCatalogModel` and
`SkillLibraryModel`. Its actor isolation serializes lock-file mutations even
when separate UI scenes initiate work.

The official non-interactive commands are:

```text
npx --yes --package skills@1.5.21 -- skills add <repository-url> --skill <slug> --global --agent <agent> --copy --yes
npx --yes --package skills@1.5.21 -- skills remove <skill-directory-name> --global --agent <agent> --yes
```

The verified 1.5.21 update command has no `--agent` option and can act through
shared global lock state. The manager therefore returns
`scopedUpdateUnsupported` before launch. See `docs/SECURITY.md` for the upstream
evidence and accepted residual risks.

`global` and `codex` sources both represent `~/.agents/skills` in this product.
They target the official `codex` agent while setting `CODEX_HOME=~/.agents`, so
the CLI writes to the directory the user configured rather than its default
`~/.codex/skills`. Other supported agents use their official identifiers:
`claude-code`, `cursor`, `github-copilot`, and `gemini-cli`. Arbitrary `other`
directories remain discoverable and readable, but lifecycle mutations fail
with an actionable unsupported-directory message because the CLI has no exact
destination-path option.

## Data flow

### Install

1. The catalog model rejects empty destinations, unsafe catalog identifiers,
   and overlapping install requests.
2. For each selected source, the CLI manager snapshots source entry names,
   validates the target, launches the official add command, and verifies
   `<source>/<slug>/SKILL.md` exists. A nonzero exit, timeout, cancellation, or
   failed postcondition reports a capped, escaped source-name delta observed so
   far without deleting its entries.
3. The catalog model returns one outcome per source so one failure does not hide
   successful destinations.
4. The view rescans successful sources and selects the first installed skill.

### Update

1. The library model snapshots selected skills with updates and marks their IDs
   busy.
2. The CLI manager validates the source and installed directory, then returns
   `scopedUpdateUnsupported` without launching a process.
3. The model keeps the skill and update badge visible and presents the safe
   reinstall guidance.

### Remove

1. The destructive confirmation states that files will be removed from disk.
2. The CLI manager runs the agent-scoped remove command and verifies the skill
   directory no longer exists.
3. Successful IDs disappear and affected sources rescan; failures remain in the
   library and are summarized in an alert.

## Error handling and interaction state

The UI tracks IDs participating in a CLI mutation and disables duplicate
actions while they are active. No command output is written to the app log,
because it may include user-specific paths or remote content. User-facing
errors distinguish missing Node/npm tooling, unsupported destinations, unsafe
identifiers or symlinks, unavailable scoped update, launch failures, timeout or
cancellation (while disclosing unsupervised descendants), nonzero CLI exits, and
a command that exits zero without producing the expected filesystem result. For
every install failure after launch in the latter three categories, the error
reports at most ten sorted names observed since the prelaunch snapshot, escapes
control characters, and includes an omitted-name count. It does not claim a
final state or rollback because descendants may keep writing and preexisting
entries may have changed internally.

All multi-skill and multi-directory operations preserve partial success. The
alert names each failed skill or source rather than collapsing failures into a
generic error.

## Security and privacy boundary

The manager never invokes a shell and never interpolates remote or local text
into a command string. Repository components, slugs, installed directory names,
agent identifiers, executable locations, and target directories are validated
before launch. The child receives only the account home, an explicit executable
search path, basic locale/temp settings, npm non-interactive settings, and
telemetry opt-outs; unrelated process environment variables and credentials are
not inherited.

This change intentionally trades App Sandbox containment for official CLI
behavior while enabling Hardened Runtime. `npx` downloads and executes the
pinned npm package with the user's normal permissions. Product and contributor
documentation, plus the Discover detail, must state that requirement and trust
boundary. The required Security Reviewer gate is especially important for this
change.

## Testing

Swift Testing coverage will use an injected command runner and temporary home
directories. Tests will prove the exact argument vectors and environment,
Codex home override, source and identifier rejection before process launch,
nonzero exit, timeout, and cancellation reporting with escaped bounded entry
deltas, descendant-risk wording, symlink containment, filesystem postconditions
with unexpected-entry reporting, and install/update/remove partial-success
behavior in the app models. Tests will not contact npm,
skills.sh, GitHub, or a real user directory.

The full handoff gate remains `make check` on macOS. A Linux Swift container may
exercise the platform-light package tests, but it cannot replace Xcode's macOS
app build and app-test targets.
