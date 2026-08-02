# skills.sh CLI Lifecycle Design

## Goal

Make the official `skills` CLI, launched through `npx`, the production backend
for installing, updating, and removing skills. A successful app action must
represent a successful on-disk mutation, not only an in-memory state change.

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
- `npx` discovery from the GUI process path and common Node installation paths;
- a scrubbed child environment with telemetry disabled;
- direct `Process` execution without a shell; and
- post-command checks for the expected manifest or removed directory.

The same manager instance is injected into `SkillCatalogModel` and
`SkillLibraryModel`. Its actor isolation serializes lock-file mutations even
when separate UI scenes initiate work.

The official non-interactive commands are:

```text
npx --yes skills add <repository-url> --skill <slug> --global --agent <agent> --copy --yes
npx --yes skills update <skill-directory-name> --global --yes
npx --yes skills remove <skill-directory-name> --global --agent <agent> --yes
```

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
2. For each selected source, the CLI manager validates the target, launches the
   official add command, and verifies `<source>/<slug>/SKILL.md` exists.
3. The catalog model returns one outcome per source so one failure does not hide
   successful destinations.
4. The view rescans successful sources and selects the first installed skill.

### Update

1. The library model snapshots selected skills with updates and marks their IDs
   busy.
2. The CLI manager runs one update command per selected skill and verifies its
   manifest remains present.
3. Because the CLI lock can link one skill to several agents, the model rescans
   every enabled, available source after successful updates.
4. Successful skills clear their cached `availableVersion`; failed skills stay
   visible with their update badge and are summarized in an alert.

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
identifiers, launch failures, nonzero CLI exits, and a command that exits zero
without producing the expected filesystem result.

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
behavior. `npx` downloads and executes npm package code with the user's normal
permissions. Product and contributor documentation, plus the Discover detail,
must state that requirement and trust boundary. The required Security Reviewer
gate is especially important for this change.

## Testing

Swift Testing coverage will use an injected command runner and temporary home
directories. Tests will prove the exact argument vectors and environment,
Codex home override, source and identifier rejection before process launch,
nonzero exit propagation, filesystem postconditions, and install/update/remove
partial-success behavior in the app models. Tests will not contact npm,
skills.sh, GitHub, or a real user directory.

The full handoff gate remains `make check` on macOS. A Linux Swift container may
exercise the platform-light package tests, but it cannot replace Xcode's macOS
app build and app-test targets.
