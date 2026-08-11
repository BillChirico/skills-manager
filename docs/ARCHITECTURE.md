# Architecture

Skills Manager is a modular native macOS application with a small dependency
surface:

```text
SwiftUI app (SkillsManager)
        │
        ▼
domain package (SkillsCore)
        │
        ├── skills.sh HTTP catalog
        ├── local filesystem and JSON persistence
        └── direct Process invocation of npx skills
```

`SkillsCore` imports neither SwiftUI nor AppKit. Domain behavior is independently
testable, background operations stay behind protocols, and the package can be
reused outside the app.

## App layer

`SkillsManager/App` owns process composition and main-actor observable state.
`SkillsManager/Features` groups user-facing capabilities. Views do not perform
network, filesystem, persistence, or process work directly.

`SkillsManagerApp` creates one `SkillsCLIManager` and injects that same actor into
the catalog and library models. Sharing the instance ensures catalog installs and
library availability checks, updates, or removals pass through one serialized
operation boundary.

`SkillLibraryModel` coordinates configured sources, restoration, discovery,
selection, scoped search, update availability, and lifecycle results. Update and
remove methods are asynchronous, expose per-skill busy state, preserve failed
items, and rescan disk after successes. Restoration also detects every supported
agent's standard directory that already exists under the account home, merges
new candidates with persisted sources and their durable removal exclusions,
publishes the reconciled configuration in memory, and attempts an atomic
normalization save without making scanning depend on that save succeeding. Once
all restored-source scans finish, the model automatically performs one serialized
availability check. It receives exact checked Global-directory URL identities
separately from the update-available subset, canonicalizes them, and applies
authoritative state only to unique installed-URL matches in one main-actor
update; see
[Automatic agent-folder detection](#automatic-agent-folder-detection) and
[Update availability isolation](#update-availability-isolation).
The library toolbar also exposes a persistent manual check through Command-R and
a cancellable progress state. Consent behavior for the automatic network-capable
launch-time check remains an unresolved product decision; Security finding 2
records this as a residual Low risk.
`SkillCatalogModel` owns the skills.sh leaderboard, search state, and
per-destination install outcomes. `SkillCatalogView` rescans each successful
destination and selects the installed skill.

Settings owns folder add, configuration removal, enablement, relocation, and
reconnect presentation. `AgentDirectorySuggestion` resolves standard agent paths
against `UserHomeDirectory` and only offers directories that exist. Folder
configuration removal remains non-destructive; skill removal is a distinct,
explicitly destructive CLI action.

## Domain layer

`Packages/SkillsCore` owns:

- `SkillSource` and `SkillAgent`, including standard account-home-relative paths;
- `AgentSkill` and stable source-relative identities;
- `SkillDiscovering` and the local `SKILL.md` scanner;
- `SkillSourceStore` and atomic JSON persistence of the combined source and
  automatic-folder-exclusion configuration, including legacy-array decoding;
- filtering, search, and deterministic sorters;
- `SkillCatalogSearching` and the skills.sh client;
- `CatalogIdentifier` and `SkillInstallCommand` for untrusted catalog fields;
- `SkillManaging`, the injected availability/install/update/remove boundary; and
- `SkillsCLIManager`, its actor-backed official-CLI implementation.

Tests use actors, in-memory fakes, and unique temporary directories. They never
operate on a developer's real skill folders.

## Automatic agent-folder detection

`SkillLibraryModel.restoreSources()` runs once per model instance. After
restoring persisted sources and resolving legacy bookmarks, it derives standard
candidate directories from `SkillAgent.allCases` against the injected account
home. Source identity uses a canonical directory key that resolves symbolic
links, standardizes the path, and applies directory semantics while preserving
each source's user-selected URL for display and access. Persisted aliases with
the same key are coalesced on load, keeping the first source. Only candidates the
injected `directoryExists` closure reports as existing directories and whose key
is not already covered by a persisted source or durable exclusion are added.
Global and Codex both resolve to `~/.agents/skills`; canonical de-duplication
keeps the first `SkillAgent.allCases` match, so the folder is assigned to Global.

Removing a source whose directory matches a standard location adds that
canonical directory key to `excludedAutomaticDirectoryURLs` in the same atomic
save that removes the source, so the folder stays out of the library across
later launches even when another path aliases it. Removing a custom folder never
creates an exclusion. Manually adding the same physical standard directory —
through the picker or the Settings suggestion menu — clears its exclusion in the
same save that (re)adds the source. Restoration canonicalizes persisted
exclusions and drops any exclusion represented by a configured source.

The restored, coalesced sources and reconciled exclusions are published in
memory before their normalization save is attempted. A failed save is reported
without discarding those sources or preventing their scans. Any later successful
source mutation persists the complete in-memory configuration. Automatic
sources are appended and sorted without moving the current sidebar selection.

Tests inject `homeDirectory` and `directoryExists` with deterministic fakes;
production composition supplies `UserHomeDirectory.current` and a real
filesystem check. No automatic-detection test reads a developer's actual home
directory.

## Catalog discovery

The skills.sh client uses `/api/search` for queries of at least two characters
and `/api/skills/all-time/{page}` for the download leaderboard. The leaderboard
omits the `id` returned by search, so the client composes it from `source` and
`skillId` and drops incomplete entries.

Both responses have an 8 MiB streaming ceiling before JSON decoding. The
production loader stops consuming an oversized body rather than checking only
after `URLSession` buffers it. Callers retain decoding-boundary checks so a test
or alternate loader cannot bypass the policy.

`CatalogSkillSorter.byDownloads` applies the product's download ranking in the
app model. Ties fall back to name and identifier. Leaderboard and search state
remain separate, so clearing search returns to the session-cached leaderboard.

## Official CLI lifecycle

Node.js 22.20 or newer and `npx` are runtime requirements for the pinned CLI.
The manager resolves `npx` from absolute, delimiter-safe entries in the parent
`PATH`, common Homebrew and system paths, Volta, mise, asdf, nvm, and fnm
locations. Empty and relative inherited entries are discarded. The child does
not inherit that `PATH`: the resolved executable's directory leads a new list
containing only fixed Homebrew and system directories, so an `npx` script can
find its sibling `node` without exposing unrelated executables. A resolved
executable directory that is non-absolute or contains the `PATH` delimiter is
rejected before launch.

The manager launches `Process` directly. The executable URL and argument vector
remain separate, and no operation uses a shell. Package selection is explicit,
and each invocation runs in a newly created owner-only empty working directory.
The exact non-interactive mutation forms are:

```text
npx --yes --package skills@1.5.21 -- skills add <repository> --skill <slug> --global --agent <agent> --copy --yes
npx --yes --package skills@1.5.21 -- skills remove <slug> --global --agent <agent> --yes
```

The exact availability probe is:

```text
npx --yes --package skills@1.5.21 -- skills check --global --yes
```

The official 1.5.21 implementation routes `check`, `update`, and `upgrade` to the
same update handler. The handler accepts `--global`, `--project`, `--yes`, and
positional skill names but no `--agent`; its global path reads shared lock state
and reinstalls through `add`. It also has no JSON output mode. A successful call
against the account home therefore cannot prove it only observed state or
mutated one selected source. The per-skill app action validates its source and
skill, then returns `scopedUpdateUnsupported` without launching a process.
Reinstalling from a reviewed source is the supported refresh path until upstream
exposes an agent-scoped mutation contract.

### Update availability isolation

`SkillsCLIManager.checkForUpdates()` treats the upstream command as a destructive
probe and shares the manager's FIFO operation gate with install, update, and
remove. Its only real-home input is `~/.agents/.skill-lock.json`; it never scans
another agent directory or a project lock. The reader rejects a symlink anywhere
from the resolved account home through the lock, any non-regular lock, any lock
greater than 1 MiB, JSON other than schema version 3, and more than 10,000 skill
entries.
Each retained entry must have a safe installation directory name, one of the
reviewed `github`, `gitlab`, or `git` source types, semantically matching HTTPS
source metadata without credentials, query, or fragment, a safe relative path
ending in `SKILL.md`, a 40- or 64-character ASCII hexadecimal folder hash, and
bounded non-control metadata. Entries grouped under one source must agree on
source type, URL, and ref because upstream uses the group's first entry.

The validated value is decoded into a closed schema and re-encoded with sorted
keys. Unrecognized root or entry fields are therefore omitted rather than copied
into the probe. The manager creates a fresh `0700` disposable home, a canonical
`.agents/.skill-lock.json` at `0600`, and a separate `0700` working directory.
It creates no stdout file. The normal environment allowlist points `HOME`,
`CODEX_HOME`, and `TMPDIR` into the disposable home and sets
`GIT_TERMINAL_PROMPT=0`. No real skill installation path, project lock,
user/global package-manager configuration, inherited credential, or unrelated
parent variable reaches the child. The reviewed upstream path directs repository
downloads and installations under the disposable home and receives no explicit
real skill path. This is process configuration, not a filesystem sandbox; the
security document records the remaining ambient-access risk.

The process runner creates an anonymous stdout pipe and gives one detached
capture task sole ownership of reading and closing its nonblocking read
descriptor. That task drains directly into bounded memory while the child
executes and enforces a 256 KiB ceiling; crossing it requests termination and
fails closed. There is no `update-check.stdout` or other child-visible capture
artifact. No other task closes the reader, avoiding a descriptor-reuse race.
Caller cancellation cancels and awaits the capture task. After the direct
process exits, the runner allows one second for the pipe to reach EOF, then
cancels and awaits the capture task and fails closed if an inherited descendant
writer kept it open. Standard input and error remain disconnected.

After a zero exit and successful drain, the runner returns the bounded in-memory
bytes. The manager requires UTF-8, removes only the exact ANSI sequences present
in the reviewed transcript, and then accepts in order either:

- one header, every expected lock source exactly once, and the all-current line;
  or
- one header, every expected source, positive found and summary counts, and one
  matching `Updating` and `Updated` pair for every returned lock skill name.

Any unknown terminal control or line, unexpected or duplicate source/name,
failure/skip/deletion diagnostic, inconsistent count, or partial transcript is
an error; raw output is neither logged nor presented. The public
`SkillUpdateAvailability` result carries URL identities, not bare names. For each
validated lock key produced by the isolated-home probe, the manager constructs
only the resolved account home's
`.agents/skills/<validated-name>` file URL. Version 3 records no per-agent
destination identity, and `skillFolderHash` describes the source's remote tree;
it does not prove the local contents or provenance of a same-named copy in
Claude, Cursor, Copilot, Gemini, or a custom folder. The manager returns the
Global URL set as `checkedSkillDirectoryURLs` and maps the parser's subset
through the same layout as `updateAvailableSkillDirectoryURLs`; neither lock
metadata nor transcript text can choose another directory. The model then
resolves symlinks, standardizes directory semantics, rechecks the subset
relationship, and intersects those identities with installations actually
discovered at the same canonical URLs before storing the normalized result. An
empty validated lock returns both sets empty without launching `npx`; it does not
assert that installed skills are current.
Deferred cleanup covers the working directory, canonical lock, and complete
disposable home after success, launch failure, nonzero exit, timeout,
cancellation, and parse failure.

Focused real-process regressions exercise successful bounded capture, the actual
stdout ceiling, pipe-only capture without a working-directory artifact, and
capture-task cancellation. The cancellation regression waits for a child-created
readiness marker instead of assuming a fixed delay means the subprocess launched.
A macOS-only regression covers the requirement that an inherited writer cannot
hold the drain open beyond the one-second deadline.

Supported mappings are:

| App source | Standard directory | CLI agent | Additional environment |
| --- | --- | --- | --- |
| Global | `~/.agents/skills` | `codex` | `CODEX_HOME=~/.agents` |
| Codex | `~/.agents/skills` | `codex` | `CODEX_HOME=~/.agents` |
| Claude Code | `~/.claude/skills` | `claude-code` | — |
| Cursor | `~/.cursor/skills` | `cursor` | — |
| GitHub Copilot | `~/.copilot/skills` | `github-copilot` | — |
| Gemini | `~/.gemini/skills` | `gemini-cli` | — |

Before launch, the configured URL must exactly match the selected agent's
standard directory. Existing components from the account home through the
source, skill, and manifest may not be symbolic links. Installed skills must be
real direct children of the source directory, and their directory names must
pass catalog argument validation. Custom sources remain discoverable and
readable but lifecycle changes return an actionable unsupported-source error. If
the account home cannot be resolved, lifecycle operations fail closed before
resolving `npx` or launching a process.

The child environment is an allowlist: the applicable real or disposable home,
the constructed executable path, locale and temporary-directory settings,
telemetry opt-outs, and explicit npm/Git settings. npm is fixed to
`https://registry.npmjs.org/`, lifecycle scripts are disabled, online metadata
is preferred, user/global npm and Git configuration are ignored, and
`GIT_TERMINAL_PROMPT=0` disables interactive credential prompts. Unrelated
variables and secrets are not forwarded. Install and remove send standard input,
output, and error to the null device. The isolated availability probe keeps input
and error disconnected and captures only bounded pipe output as described above. A
nonzero status becomes a typed error without exposing raw CLI output. The runner
has a five-minute deadline, propagates task cancellation, sends termination
first, and force-kills the directly launched `npx` process after a one-second
grace period if it is still running. The liveness check and `SIGKILL` share one
lock scope. Descendants are not placed in a supervised process group and may
continue after the direct process exits; timeout and cancellation errors
disclose this limit.

Postconditions cannot be satisfied by stale state. Install requires the exact
destination entry to be absent before launch and snapshots the source's entry
names. After a zero status, the expected destination must be a real direct-child
directory and `SKILL.md` must be a regular, non-symbolic file. A nonzero exit,
timeout, cancellation, or failed install postcondition computes the source-name
delta observed at that point. The error renders at most ten sorted names with
`String(reflecting:)`, includes an omitted-name count, and leaves the entries on
disk for inspection. "Observed so far" is intentionally not a final state:
unsupervised descendants or concurrent writers may add entries later, and the
snapshot cannot identify modifications inside entries that already existed or
provide rollback. Remove requires the directory entry to be absent, including a
dangling symbolic link, and the source boundary is revalidated after the process
exits. A private FIFO operation gate prevents actor reentrancy while the process
runner is awaited, so lock-file mutations cannot overlap.

## Lifecycle state and partial success

One selected destination or skill is one outcome. Catalog installation continues
after a destination failure. Library update and removal likewise continue after
an individual failure and present a concise combined error.

`AgentSkill.updateStatus` uses the explicit `SkillUpdateStatus` values
`.unknown`, `.current`, and `.available`. The property remains optional only so
pre-probe and previously encoded values can use installed/available version
comparison as a compatibility fallback. A completed or cleared probe assigns
explicit `.unknown` to unchecked skills; `hasUpdate` then returns false even
when stale legacy version fields differ. Only `.available` produces an update
indicator.

After restoration finishes scanning every enabled source,
`SkillLibraryModel.refreshUpdateAvailability()` marks the check as running,
but preserves the last trustworthy statuses, update count, and normalized result
while awaiting `SkillManaging`. It normalizes a successful result's file URLs to
symlink-resolved, standardized directory identities, requires the update set to
remain a subset of the checked set, stores the normalized result, and replaces
all statuses in one reconciled array. A checked URL with exactly one installed
match becomes `.available` when it is in the update subset and `.current`
otherwise. Because the production manager returns only Global URLs, same-named
installations in every other agent or custom path remain `.unknown`; multiple
model entries for one canonical physical URL are likewise ambiguous and remain
unknown.

The state becomes current only when every installed skill received one of those
unique authoritative URL matches; otherwise a successful probe is partial. This
state carries checked and total counts, preventing an empty or incomplete lock
from producing “All Skills Are Up to Date.” An empty library returns to idle
rather than treating zero checked out of zero as current.
After every successful source rescan, the model reapplies the normalized last
result across the complete replacement skill list. Existing covered skills keep
their current/available status, while a newly discovered unchecked skill becomes
unknown and immediately downgrades current to counted partial. Cancellation
clears prior positives and returns to idle. A missing global lock quietly becomes
unavailable, while missing Node.js/`npx` or an absent lifecycle manager quietly
becomes unsupported; neither opens a modal alert. Malformed input, execution
failure, timeout, or invalid output clears prior positives, marks availability
unavailable, and uses the existing safe alert path.

`SkillLibrarySorter` treats `hasUpdate` as an invariant first key. The user's
name, newest-date, or agent/source selection remains the secondary order inside
the update and current partitions; relative path and then source ID provide the
stable final tie breakers. An update row shows the text `Update` with a filled
and stroked status treatment and includes `Update available` in its combined
accessibility label, so the state does not depend on color or imply a button.
Explicit unknown rows display `Not checked`. The persistent toolbar control
starts a check with Command-R; while checking it presents a spinner and Cancel control without
hiding prior trustworthy update rows. The Updates Available empty state
distinguishes idle, checking, counted partial, current, unsupported, and
unavailable results. Partial copy reports `checked` and `total`, and idle,
partial, unsupported, and unavailable states offer appropriate retry or Node.js
guidance. A completion transition posts a VoiceOver announcement containing the
update count and partial coverage when applicable. Update-driven reordering uses
a state-scoped animation and disables it when Reduce Motion is enabled.

The production manager currently returns an explicit failure for every update,
so row, detail, context-menu, and multi-select update surfaces are all inert
`Reinstall Required` guidance rather than actions. They direct users to reinstall
from a trusted source, and the model does not launch or rescan on that path.
Removal immediately drops only successful IDs, then rescans sources that share
the affected directory. Failed removals stay visible and selected. Views disable
conflicting actions and show progress while IDs are in `mutatingSkillIDs`.

## Trust boundaries

Every `CatalogSkill` field is remote input. `CatalogIdentifier` restricts URL
components and process arguments to `[A-Za-z0-9._-]`, caps length, rejects empty
and relative-path segments, and rejects leading options. Installation directory
names also reject a leading dot so discovery cannot lose a newly installed
hidden skill. Invalid results remain browsable but are not installable, with no
unvalidated fallback.

`SkillInstallCommand` reconstructs the command displayed by skills.sh from
validated fields. The app may copy it or use its split argument vector as the
validated base of a lifecycle invocation; it never evaluates the display string.

Installed manifests are untrusted presentation input. The library strips link
attributes from Markdown-derived overview text, so a manifest cannot create an
interactive destination in app chrome. Separately constructed external links
must remain validated HTTPS actions.

Direct arguments and a scrubbed environment prevent shell injection and secret
leakage. Lifecycle execution is pinned to `skills@1.5.21`, published from the
signed upstream `v1.5.21` tag at commit
`7cb7db64dc1201052dea305e508a2fc490f7e5e2`; its npm tarball integrity is recorded
in `docs/SECURITY.md`. These controls do not independently authenticate npm
registry responses, the locally resolved `npx` executable, transitive runtime
dependencies, or skill publishers. The pinned CLI still installs community
content. The UI and README disclose this boundary and direct users to review
`SKILL.md`.

## Platform, filesystem, and visual policy

The deployment target is macOS 15. Liquid Glass is availability-gated to macOS
26 and newer; earlier releases receive semantic material fallbacks. The app has
no global accent-color asset or root tint, so native controls inherit the user's
accent color.

Skills Manager intentionally ships with `ENABLE_APP_SANDBOX=NO` and
`ENABLE_HARDENED_RUNTIME=YES`. An external Node/npm child needs executable,
network, and standard-agent-directory access, and it would inherit an App
Sandbox that dynamic picker grants cannot reliably broaden. Hardened Runtime
retains code-signing and runtime integrity protections that are compatible with
the external process design. Reintroducing App Sandbox requires a separately
designed and reviewed helper boundary.

Configured source URLs and durable automatic-folder exclusions are persisted
together as one `SkillSourceConfiguration` document in `sources.json` under
Application Support, written atomically so a source removal and its exclusion
land in the same write. The JSON store tightens the directory to `0700`, writes
an owner-only `0600` temporary file, and atomically renames it only after every
fallible permission step succeeds; a thrown save therefore never follows an
already-committed configuration. It still decodes a legacy top-level source
array into an empty exclusion set.

Source-configuration mutations are serialized across their persistence commit
or rollback because MainActor methods are reentrant at an `await`. The boundary
is released before post-commit filesystem scans so Settings actions do not wait
for discovery. A scan re-resolves its source after discovery and publishes only
when the ID still exists with the same standardized URL and enabled state.
Failure rollback restores only the affected source, skills, state, and exclusion
deltas, preserving unrelated scan results and UI selection made during the
save. A rolled-back `.scanning` state becomes `.available` because the scan was
invalidated while the source was absent or relocated. Existing legacy bookmark
data may still decode, but production composition no longer creates or relies
on security-scoped bookmarks.

The library title reports the selected scope and item count. Toolbar actions keep
discovery and Settings separate from sort/search controls. Static content uses
semantic backgrounds; Liquid Glass is reserved for interactive controls. Busy,
paused, scanning, and unavailable states use accessible text or labels rather
than color alone. Update availability likewise uses visible text and remains
part of the row's explicit accessibility label without implying an update
action.

## CI and unsigned DMG distribution

`.github/workflows/ci.yml` retains one ordered validation job for pull requests
and pushes to `main`. Both event types regenerate the project, test, lint, and
exercise the packaging scripts with controlled tool fakes. Only a successful
push to `main` continues through a real unsigned Release archive, mounted-image
validation, and artifact upload. Keeping those steps in the same job makes the
existing checks a direct gate on distribution without duplicating runner setup.

`scripts/build-unsigned-dmg.sh` owns the `xcodebuild archive` contract and DMG
layout. It builds with `CODE_SIGNING_ALLOWED=NO` in a private temporary workspace,
copies the app as `Skills Manager.app`, adds the `/Applications` shortcut, and
writes only the requested DMG output. `scripts/verify-unsigned-dmg.sh` owns the
consumer-visible image contract: `hdiutil verify`, a read-only mount, executable
and property-list checks, absence of the bundle signature directory, exact
shortcut validation, and detach. `make packaging-test`, `make dmg`, and
`make verify-dmg` are the stable contributor and CI interfaces.

The uploaded `SkillsManager-unsigned.dmg` is a 30-day workflow artifact, not a
signed release. The workflow contains no Apple credentials and has read-only
repository permissions. Future Developer ID signing belongs after archive
creation; notarization and ticket stapling belong after the signed DMG is
created and before its final validation/upload. Adding either is a separate
release-architecture and security review, not an implicit extension of the
unsigned script.

## Project generation

`project.yml` is authoritative and `SkillsManager.xcodeproj` is committed for
onboarding. Do not hand-edit `project.pbxproj`. Change the specification, run
`make generate`, and commit the regenerated project.

## Planned extension points

1. Add bounded, privacy-reviewed diagnostics for CLI failures without logging
   process environments or skill contents.
2. Evaluate a signed helper/XPC architecture if App Sandbox becomes a product
   requirement.
3. Add authenticated or alternate registry adapters behind existing protocols.
4. Add UI automation with XCTest for destructive confirmation and partial-failure
   workflows.
