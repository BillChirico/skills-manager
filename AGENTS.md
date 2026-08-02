# AGENTS.md

This file is the source of truth for coding agents working in this repository.
Read it before making changes. Human contributors should follow the same
engineering constraints.

## Product

Skills Manager is a native macOS SwiftUI app for installing, updating,
removing, searching, and organizing agent skills across user-selected
directories. It should feel at home on macOS, remain accessible, and adopt
Liquid Glass without dropping the macOS 15 deployment target.

## Project structure

- `SkillsManager/` contains the app target and feature UI.
- `Packages/SkillsCore/` contains models and domain logic that do not depend on
  SwiftUI or AppKit.
- `Tests/SkillsManagerTests/` contains unit tests for app-only state.
- `project.yml` is the source of truth for `SkillsManager.xcodeproj`.
- `docs/ARCHITECTURE.md` records dependency boundaries and extension points.

Keep feature code together under `SkillsManager/Features/<FeatureName>`.
Promote code to `SkillsCore` only when it represents reusable domain behavior.

## Required commands

```sh
make generate   # regenerate the Xcode project after project.yml changes
make lint       # check Swift formatting without modifying files
make test       # run SkillsCore tests with Swift Package Manager
make build      # build the macOS app without code signing
make check      # regenerate, test, verify generated files, and build
```

Run the narrowest relevant command while iterating and `make check` before
hand-off when full Xcode is available. If Xcode is unavailable, run
`make generate` and `make test`, then state that limitation clearly.

## Swift conventions

- Use Swift 6 language mode and strict concurrency.
- Isolate UI-owned mutable state to `@MainActor`.
- Prefer value types that conform to `Sendable` for domain models.
- Keep filesystem, network, persistence, and time dependencies injectable.
- Never add AppKit or SwiftUI imports to `SkillsCore`.
- Use native SwiftUI controls and semantic colors before custom drawing.
- Inherit the user's macOS accent color. Do not add a global `AccentColor`
  asset or override the root scene's tint.
- Gate macOS 26-only Liquid Glass APIs with availability checks and retain a
  usable fallback for macOS 15 through 25.
- Reserve Liquid Glass for interactive controls; use semantic system
  backgrounds and separators for static Settings containers.
- Treat accessibility labels, keyboard access, empty states, and reduced motion
  as part of feature completion.
- Keep folder addition and the primary add/remove list in Settings. Route other
  entry points to the Settings scene instead of duplicating the folder picker;
  contextual relocation for unavailable sources may remain in the library.
- Suggest a standard agent location only while it exists on disk, and add it
  directly instead of reopening a picker the user already answered. Keep one
  generic picker action for every other folder rather than a per-agent list.
- Detect and configure every supported agent's standard directory that exists
  under the account home once per launch, in
  `SkillLibraryModel.restoreSources()`. Persist a folder the user removes as a
  durable exclusion so it does not reappear on the next launch, and clear that
  exclusion only when the same standard path is added back. Inject the account
  home and a directory-existence closure so tests never touch a developer's
  real home directory.
- Resolve the account home through `UserHomeDirectory`, never
  `FileManager.homeDirectoryForCurrentUser`, so suggestions, display paths, and
  CLI operations use one authoritative location. If account-home resolution
  fails, suppress home-based suggestions, picker defaults, and `~` abbreviation
  rather than substituting another directory.
- Keep Settings folder selection explicit: preserve a valid user selection,
  clear a stale one, and never auto-select the first row.
- Present paused, scanning, and unavailable folder states with text rather than
  opacity or icon-only cues. Keep row toggles and reconnect buttons separately
  operable by assistive technologies.
- Keep Discover visually prominent in the library toolbar and Settings as an
  icon-only utility.
- Send every folder add, enable, relocate, or remove mutation through
  `SkillLibraryModel` so persistence and rollback remain intact.
- Open Discover on the skills.sh download leaderboard, and order both the
  leaderboard and search results with `CatalogSkillSorter.byDownloads`. A search
  response arrives in relevance order, so skipping the sorter silently changes
  the ranking the product promises.

## Testing conventions

- Write new unit and integration tests with Swift Testing.
- Use XCTest only for UI tests, which Swift Testing does not support.
- Mirror production folders in test folders where practical.
- Keep tests deterministic, parallel-safe, and independent of real user files.
- Prefer `#require` for preconditions and `#expect` for behavior assertions.

## Project-file policy

Do not hand-edit `SkillsManager.xcodeproj/project.pbxproj`. Update `project.yml`,
run `make generate`, and commit both the specification and generated project.
Do not add third-party dependencies without documenting the reason in the pull
request and `docs/ARCHITECTURE.md` when the choice affects architecture.

## Security

The app intentionally ships without App Sandbox because its required backend is
an external Node/npm process that must reach supported agent directories. Do not
describe the app as sandboxed or add security-scoped bookmark behavior to imply
that the child process inherits a picker grant. Re-enabling App Sandbox requires
a separately reviewed helper architecture, not an entitlement exception. Keep
Hardened Runtime enabled for the app target even while App Sandbox is disabled.

Never log skill contents, tokens, credentials, the inherited environment, CLI
output, or user-specific absolute paths. Keep process standard input, output,
and error disconnected unless a separately reviewed UI securely presents a
bounded diagnostic.

Serialize source-configuration mutations across their persistence commit or
rollback; MainActor isolation alone is reentrant across an `await`. Release that
mutation boundary before post-commit filesystem scans, and make each scan
revalidate the source ID, enabled state, and standardized directory URL after
discovery returns. When a source mutation rolls back, re-resolve its target by
`SkillSource.ID` and restore only that source's deltas; never replace whole
skill, state, or selection collections that ungated UI and scan work may have
changed during the save. Normalize a rolled-back `.scanning` source to
`.available`; the scan may have already exited after observing the transient
removal or relocation. Write source configuration to an owner-only temporary
file and set permissions before the atomic rename, so no fallible permission
step remains after the commit.

When the account home is available, the abbreviated `~/…` display path keeps the
account name off screen. Do not pass a raw absolute path to a tooltip, label, or
accessibility string that renders next to an available abbreviation.
`UserHomeDirectory` reads the account home from the password database. If that
lookup fails, leave persisted paths un-abbreviated instead of guessing.

### Remote catalog input

Never hand catalog text to a shell, `NSAppleScript`, or an interpolated command.
Lifecycle operations must go through `SkillsCLIManager`, which launches a
resolved `npx` executable with a separate, validated argument vector. Keep the
official non-interactive command forms covered by exact-argument tests. The copy
shown in Discover must disclose that `npx` can fetch and execute npm code and
that installed `SKILL.md` content must be reviewed before use.

Every field on `CatalogSkill` is untrusted. Route each one through
`CatalogIdentifier` before it becomes a URL path component
(`validatedPathComponent`) or a command argument (`validatedArgument`, which also
rejects a leading `-` so a slug cannot be read as a flag). A value that fails
validation makes the skill non-installable; it must not degrade into an
unvalidated fallback. Reject dot-prefixed installation slugs because the library
scanner skips hidden directories, while still allowing safe dot-prefixed
repository path components such as `.github`. Re-check installability at the
model boundary and again in `SkillsCLIManager`. Build `SkillInstallCommand` as a
program plus an argument vector, never as one interpolated string.

Only standard Global, Claude Code, Codex, Cursor, Gemini, and GitHub Copilot
directories are mutable. Validate the configured directory against the selected
agent's account-home-relative default before launching a process. Custom sources
remain discoverable and readable but must fail lifecycle operations with an
actionable error. Global and Codex both map to `~/.agents/skills`; pass the Codex
agent identifier and set `CODEX_HOME=~/.agents` so the official CLI targets that
shared location. Fail closed before process launch when `UserHomeDirectory`
cannot resolve the account home.

Node.js 22.20 or newer is required by the pinned CLI. Resolve `npx` only from
absolute, delimiter-safe entries in the parent `PATH` and documented common Node
version-manager locations; discard empty and relative inherited entries, and
never copy the parent `PATH` into the child. Put the resolved executable's
directory first, followed only by the fixed Homebrew and system directories
needed for Node and Git. Reject a non-absolute resolved executable directory or
one containing the `PATH` delimiter instead of splitting it into unintended
search locations. Child environments are allowlists: pass only the account home,
that constructed path, locale and temporary-directory values, telemetry
opt-outs, and explicit npm settings. Pin lifecycle execution to the reviewed
`skills@1.5.21` package from `https://registry.npmjs.org/`, disable npm lifecycle
scripts, ignore user/global npm configuration, and run from a fresh owner-only
empty directory so a local package cannot shadow the selected binary. Do not
forward unrelated parent variables, proxy credentials, tokens, or secrets.

The shared `SkillsCLIManager` must serialize install, update, and remove calls so
the CLI cannot race its own lock-file mutations. Every directly launched process
must have a finite deadline and stop promptly when its calling task is cancelled,
escalating to a forced stop after the grace period. Keep the liveness check and
`SIGKILL` in the same lock scope so a reaped pid cannot be reused between them.
User-facing errors must disclose that unsupervised descendant work may continue.
Reject symbolic links in every mutable source, skill, and manifest path before
launch and verify the boundary again afterward. A new install destination must
be absent before launch; afterward it must be a real direct-child directory
containing a regular, non-symbolic `SKILL.md`. Snapshot source entry names before
install. On a nonzero exit, timeout, cancellation, or failed postcondition,
report at most ten sorted names observed since that snapshot plus the omitted
count. Render each untrusted name with `String(reflecting:)` so control
characters are escaped, call the delta "observed so far" because descendants may
continue writing, and do not silently delete its entries. Do not claim this
name-only delta detects changes inside preexisting entries or provides rollback.
Remove requires the exact directory entry, including a dangling symlink, to be
absent after a zero exit status.

Upstream `skills@1.5.21` update accepts only global/project scope and skill-name
filters; it has no agent selector. Do not invoke it from a per-source app action,
because it can reconcile shared lock state outside the selected agent directory.
Fail closed with `scopedUpdateUnsupported` until a separately reviewed upstream
contract makes the mutation agent-scoped. Treat each selected skill or
destination as an independent outcome, preserve failures in the UI, and rescan
disk after successes. Removal confirmation must say that files are deleted;
never reuse the old non-destructive “Remove from Library” language for skill
removal.

Treat text extracted from an installed `SKILL.md` as untrusted presentation
input. Its library overview must remain non-interactive. Markdown styling may be
parsed only when every link attribute is stripped before rendering; never allow
a manifest-supplied destination to become clickable. Any intentional external
navigation must be a separately constructed, validated `https` action.

Catalog bodies must use the bounded streaming HTTP loader. Do not replace the
8 MiB streaming ceiling with a size check that runs only after `URLSession` has
buffered the response.

## Change checklist

1. Keep the change inside the existing dependency boundaries.
2. Format Swift with the checked-in `.swift-format` configuration.
3. Add or update focused tests for behavior.
4. Regenerate the Xcode project when its inputs change.
5. Run all checks available in the current environment.
6. Update documentation when commands, requirements, or architecture change.
