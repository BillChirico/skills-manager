# Update Availability Design

## Goal

Show trustworthy update availability for installed skills without allowing the
pinned `skills@1.5.21` check path to mutate any real skill directory. Skills
with updates must be ordered before current skills for every user-selected sort
order and carry a visible, non-color-only, accessible indication.

## Upstream constraint

In `skills@1.5.21`, `check`, `update`, and `upgrade` all dispatch to the same
update implementation. A global check compares lock-file hashes and then runs
the add flow for every update it finds. Running that command with the account's
real home would therefore update real installations. The release also offers
no JSON output for this operation.

The feature consequently treats the CLI as a destructive probe and contains
it in a disposable home. This is an availability check only; the existing
agent-scoped update action remains fail-closed because the pinned CLI still
cannot target one configured agent directory.

## Isolation contract

`SkillsCLIManager.checkForUpdates()` serializes with all other CLI operations
and performs these steps:

1. Read only `~/.agents/.skill-lock.json`. Reject a symlink, non-regular file,
   oversized input, unsupported schema, unsafe skill name, malformed remote
   source metadata, or incomplete hash/path entry.
2. Decode schema version 3 and write a canonical lock containing only the
   validated update fields to a newly created owner-only temporary home.
3. Create a separate owner-only working directory. Launch the exact pinned
   command directly, without a shell:

   ```text
   npx --yes --package skills@1.5.21 -- skills check --global --yes
   ```

4. Give the child only the existing scrubbed environment, but point `HOME`,
   `CODEX_HOME`, and `TMPDIR` into the disposable home. No real agent directory,
   package manager configuration, credential environment variable, or project
   lock is exposed. Set `GIT_TERMINAL_PROMPT=0` so Git cannot request
   credentials interactively.
5. Capture stdout directly from an anonymous pipe into bounded memory. Create no
   `update-check.stdout` or other child-visible capture artifact. One capture
   task exclusively reads and closes the nonblocking stdout descriptor. Caller
   cancellation cancels and awaits that task. After the direct process exits,
   allow one second to drain, then cancel and await the task and fail closed if
   an inherited writer still holds the pipe open. Reject oversized or non-UTF-8
   output, unknown terminal controls, unknown or out-of-order lines,
   failure/skip/deletion diagnostics, duplicate names, names not present in the
   validated lock, or inconsistent found/update/summary counts.
6. Remove the working directory, canonical lock, and complete temporary home
   with `defer`, including launch failure, nonzero exit, timeout, cancellation,
   parse failure, and success paths.

The public `SkillUpdateAvailability` result returns two exact file-URL identity
sets. Version 3 records no per-agent destination identity, and
`skillFolderHash` describes remote-tree provenance rather than proving the local
contents or provenance of same-named copies. After the isolated-home probe
validates a checked lock key, the production manager therefore projects it only
to the resolved account home's `.agents/skills/<validated-name>` directory; the
update-available subset is mapped through the same layout. No lock or transcript
field can choose another path, and Claude, Cursor, Copilot, Gemini, and custom
copies remain outside the trustworthy identity boundary. A valid empty lock
returns both sets empty without launching the CLI; that means no installed URL
was checked, not that every installed skill is current.

The CLI may download repositories and install into the disposable home while
probing. Those writes are intentional and are deleted. It never receives a
path to a real skill installation.

## Model and UI behavior

`AgentSkill` gains `SkillUpdateStatus.unknown`, `.current`, and `.available`.
`updateStatus` remains optional for backward-compatible decoding, but nil means
only pre-probe/legacy state and permits the installed/available version fallback.
A completed or cleared probe gives unchecked skills an explicit `.unknown`
status, which suppresses stale version-based update badges; only `.available`
reports an update.

After restored sources finish scanning, `SkillLibraryModel` runs one update
check. It enters `.checking` without clearing the last trustworthy statuses or
update count. A successful result must keep the update URL set within the checked
set. The model canonicalizes both sets by resolving symlinks and standardizing
directory semantics, stores that normalized result, and groups installed skills
by the same canonical URL. In one main-actor replacement, a checked URL with
exactly one installed match becomes `.available` or `.current`; every other
skill becomes `.unknown`. Because the production result contains only
`.agents/skills` identities, same-named copies in all other agent and custom
paths cannot inherit a global lock result. Empty or partial locks, unchecked
URLs, and ambiguous duplicate physical identities remain unknown. The result is
current only when every installed skill received a unique authoritative URL
match; otherwise `.partial(checked:total:)` reports exact coverage. An empty
library returns to `.idle`, so zero checked out of zero never produces an
all-current claim.

Cancellation clears prior positives and returns to idle. A missing global lock
quietly produces `.unavailable`; missing Node.js/`npx` or a manager without
lifecycle support quietly produces `.unsupported`. Those normal absence states
do not open a modal alert. Malformed input, failed execution, timeout, or invalid
output clears prior positives, becomes unavailable, and uses the existing safe
alert path. Raw output and lock contents are never logged or shown.

After a successful rescan, the model reapplies the normalized last result across
the complete replacement skill list. Covered skills retain authoritative state;
any newly discovered unchecked skill becomes `.unknown` and downgrades the
overall check state from current to partial.

The library toolbar always exposes `Check for Updates` with Command-R. During a
check, the control shows a spinner and a visible Cancel action while previously
confirmed update rows remain visible. The Updates Available empty state also
shows progress and cancellation when appropriate, and distinguishes checking,
not checked, counted partial, unsupported, unavailable, and confirmed-current
states. Partial copy reports the number checked out of the total, and normal
absence states offer appropriate retry or Node.js guidance.

`SkillLibrarySorter` uses update availability as an invariant primary key.
Within the update and current partitions, it preserves the selected name,
date-added, or agent ordering and existing stable tie breakers. This makes the
result deterministic without overriding the user's chosen secondary order.

Each update row shows a compact, non-action `Update` indicator. Its text, fill,
and stroke make the state independent of color, while the row's explicit
accessibility label continues to announce “Update available.” An explicit
unknown row displays `Not checked` and announces that its status was not checked.
Row, detail, context-menu, and multi-select update surfaces are all inert
`Reinstall Required` guidance; users must reinstall from a trusted source because
the pinned CLI cannot safely scope an update to one agent directory. On the
transition out of checking, VoiceOver receives a completion announcement with
the update count and partial coverage when applicable. Update-driven row
reordering uses a value-scoped animation that is disabled under Reduce Motion.

The launch-time check remains automatic and network-capable. There is no consent
prompt or preference to disable it. Security finding 2 remains a residual Low
risk pending a product decision; this design does not claim that opt-in or an
opt-out was implemented.

## Testing

Focused Swift Testing coverage uses temporary directories. Parser, lock, and
model cases use injected command runners; descriptor lifecycle cases launch
short-lived local processes. Coverage includes the exact argument vector and
isolated environment, `GIT_TERMINAL_PROMPT=0`, canonical lock mirroring,
success/no-update parsing, malformed and injected output, count/name mismatches,
oversized input/output, nonzero exit, cancellation, and cleanup. Real-process
regressions cover successful in-memory capture, absence of an output artifact,
the actual stdout byte limit, and capture-task cancellation. The cancellation
regression waits for a child-created readiness marker before cancelling. A
macOS-only regression holds an inherited stdout writer open and requires the
one-second drain deadline to fail closed. Model tests cover one-URL Global
projection, separate checked/update URL sets, other-agent and custom same-name
isolation, preserved badges while checking, counted partial coverage, quiet
missing-lock and missing-runtime states, empty-library handling, suppression of
stale legacy version badges, canonical URL ambiguity, successful mapping,
rescan preservation and downgrade, cancellation, and fail-closed state. Sorter
tests prove update-first ordering for every sort choice and deterministic order
within both partitions; macOS QA remains responsible for toolbar, VoiceOver,
contrast, keyboard, cancellation, and reduced-motion validation.

The Windows implementation host has no Xcode or macOS runtime. A Swift 6.2 Linux
container can compile and exercise a focused SkillsCore harness, but the complete
package still encounters existing Linux-only Foundation API gaps and app/model/UI
tests require macOS. Those complete checks remain explicit QA gates on the
committed revision before any PR. Security Reviewer acceptance remains a separate
pending gate on that same revision.
