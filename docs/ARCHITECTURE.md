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
library updates or removals pass through one serialized mutation boundary.

`SkillLibraryModel` coordinates configured sources, restoration, discovery,
selection, scoped search, and lifecycle results. Update and remove methods are
asynchronous, expose per-skill busy state, preserve failed items, and rescan disk
after successes. `SkillCatalogModel` owns the skills.sh leaderboard, search state,
and per-destination install outcomes. `SkillCatalogView` rescans each successful
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
- `SkillSourceStore` and atomic JSON persistence;
- filtering, search, and deterministic sorters;
- `SkillCatalogSearching` and the skills.sh client;
- `CatalogIdentifier` and `SkillInstallCommand` for untrusted catalog fields;
- `SkillManaging`, the injected install/update/remove boundary; and
- `SkillsCLIManager`, its actor-backed official-CLI implementation.

Tests use actors, in-memory fakes, and unique temporary directories. They never
operate on a developer's real skill folders.

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
and each invocation runs in a newly created owner-only empty directory. Exact
non-interactive forms are:

```text
npx --yes --package skills@1.5.21 -- skills add <repository> --skill <slug> --global --agent <agent> --copy --yes
npx --yes --package skills@1.5.21 -- skills remove <slug> --global --agent <agent> --yes
```

The official 1.5.21 update parser accepts `--global`, `--project`, `--yes`, and
positional skill names, but no `--agent`. Its global implementation reads shared
lock state and reinstalls through `add`, so a successful call cannot prove it
mutated only the selected source. The app validates the selected source and skill
then returns `scopedUpdateUnsupported` without launching a process. Reinstalling
from a reviewed source is the supported refresh path until upstream exposes an
agent-scoped contract.

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

The child environment is an allowlist: account home, the constructed executable
path, locale and temporary-directory settings, telemetry opt-outs, and explicit
npm/Git settings. npm is fixed to `https://registry.npmjs.org/`, lifecycle scripts
are disabled, online metadata is preferred, and user/global npm and Git
configuration are ignored. Unrelated variables and secrets are not forwarded.
Standard input, output, and error use the null device. A nonzero status becomes a
typed error without exposing unbounded CLI output. The runner has a five-minute
deadline, propagates task cancellation, sends termination first, and force-kills
the directly launched `npx` process after a one-second grace period if it is
still running. The liveness check and `SIGKILL` share one lock scope. Descendants
are not placed in a supervised process group and may continue after the direct
process exits; timeout and cancellation errors disclose this limit.

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

The production manager currently returns an explicit failure for every update,
so the model reports the upstream limitation and does not rescan on that path.
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

Configured source URLs are persisted in `sources.json` under Application Support.
The JSON store creates an owner-only directory and file (`0700`/`0600`). Existing
legacy bookmark data may still decode, but production composition no longer
creates or relies on security-scoped bookmarks. Rollbacks re-resolve sources by
stable `SkillSource.ID` after every `await`, never by a possibly stale array index.

The library title reports the selected scope and item count. Toolbar actions keep
discovery and Settings separate from sort/search controls. Static content uses
semantic backgrounds; Liquid Glass is reserved for interactive controls. Busy,
paused, scanning, and unavailable states use accessible text or labels rather
than color alone.

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
