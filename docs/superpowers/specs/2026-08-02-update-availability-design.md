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
3. Create a separate owner-only working directory and bounded, owner-only
   stdout file. Launch the exact pinned command directly, without a shell:

   ```text
   npx --yes --package skills@1.5.21 -- skills check --global --yes
   ```

4. Give the child only the existing scrubbed environment, but point `HOME`,
   `CODEX_HOME`, and `TMPDIR` into the disposable home. No real agent directory,
   package manager configuration, credential environment variable, or project
   lock is exposed.
5. Open the private stdout file before launch, stream through a bounded pipe,
   and parse the returned bytes without reopening a pathname the child could
   replace. One capture task exclusively reads and closes the nonblocking stdout
   descriptor. Caller cancellation cancels and awaits that task. After the direct
   process exits, allow one second to drain, then cancel and await the task and
   fail closed if an inherited writer still holds the pipe open. Reject oversized
   or non-UTF-8 output, unknown terminal controls, unknown or out-of-order lines,
   failure/skip/deletion diagnostics, duplicate names, names not present in the
   validated lock, or inconsistent found/update/summary counts.
6. Remove stdout, working directory, canonical lock, and the complete temporary
   home with `defer`, including launch failure, nonzero exit, timeout,
   cancellation, parse failure, and success paths.

The public `SkillUpdateAvailability` result returns two exact file-URL identity
sets. A version-3 global lock can represent
`--global --agent ... --copy` installs but records no per-agent destination list.
After the isolated-home probe validates a checked lock key, the manager therefore
projects it into all five deduplicated fixed locations under the resolved account
home: `.agents/skills` (shared by Global and Codex), `.claude/skills`,
`.cursor/skills`, `.copilot/skills`, and `.gemini/skills`; the update-available
subset is mapped through the same set. No lock or transcript field can choose a
custom path. A valid empty lock returns both sets empty without launching the
CLI; that means no installed URL was checked, not that every installed skill is
current.

The CLI may download repositories and install into the disposable home while
probing. Those writes are intentional and are deleted. It never receives a
path to a real skill installation.

## Model and UI behavior

`AgentSkill` gains `SkillUpdateStatus.unknown`, `.current`, and `.available`.
`updateStatus` remains optional for backward-compatible decoding, but nil means
only pre-probe/legacy state and permits the installed/available version fallback.
Once a probe starts, every skill receives an explicit status; `.unknown`
suppresses stale version-based update badges, and only `.available` reports an
update.

After restored sources finish scanning, `SkillLibraryModel` runs one update
check. It clears prior detection before awaiting and requires the returned
update-available URL set to be a subset of the checked set. It canonicalizes both
sets by resolving symlinks and standardizing directory semantics, stores that
normalized successful result, and groups installed skills by the same canonical
URL. In one main-actor update, a checked URL with exactly one installed match
becomes `.available` or `.current`; every other skill becomes `.unknown`.
Built-in agent installations discovered at an exact projected URL can therefore
receive status, while same-named custom-path copies cannot inherit a global lock
result. Empty or partial locks, unchecked URLs, and ambiguous duplicate physical
identities remain unknown. The result is current only when every installed skill
received a unique authoritative URL match; otherwise it is partial, so incomplete
coverage can never produce an all-current claim.
Cancellation and every error leave no positive update claims. Parser or CLI
errors are surfaced through the existing safe alert path; raw output and lock
contents are never logged or shown.

After a successful rescan, the model reapplies the normalized last result across
the complete replacement skill list. Covered skills retain authoritative state;
any newly discovered unchecked skill becomes `.unknown` and downgrades the
overall check state from current to partial.

The Updates Available empty state distinguishes checking, not checked, partial,
unavailable, and confirmed-current states. Partial state explains that some
skills remain unknown. It offers a manual retry whenever a check has not
produced a current result.

`SkillLibrarySorter` uses update availability as an invariant primary key.
Within the update and current partitions, it preserves the selected name,
date-added, or agent ordering and existing stable tie breakers. This makes the
result deterministic without overriding the user's chosen secondary order.

Each update row shows a compact `Update` label with the download symbol. The
text, shape, and symbol make the state independent of color, while the row's
explicit accessibility label continues to announce “Update available.”

## Testing

Focused Swift Testing coverage uses temporary directories. Parser, lock, and
model cases use injected command runners; descriptor lifecycle cases launch
short-lived local processes. Coverage includes the exact argument vector and
isolated environment, canonical lock mirroring, success/no-update parsing, malformed and injected
output, count/name mismatches, oversized input/output, nonzero exit,
cancellation, and cleanup. Real-process regressions cover successful capture,
the actual stdout byte limit, capture-task cancellation, and child replacement
of the output pathname. The cancellation regression waits for a child-created
readiness marker before cancelling. A macOS-only regression holds an inherited
stdout writer open and requires the one-second drain deadline to fail closed.
Model tests cover five-URL fixed-destination projection with Global/Codex
deduplication, separate checked/update URL sets, a Claude-versus-custom same-name
case, suppression of stale legacy version badges after incomplete checks, empty
and partial locks, canonical URL ambiguity, successful mapping, rescan
preservation and downgrade, cancellation, and fail-closed state. Sorter tests
prove update-first ordering for every sort choice and deterministic order within
both partitions.

The Windows implementation host has no Xcode or macOS runtime. A Swift 6.2 Linux
container can compile and exercise a focused SkillsCore harness, but the complete
package still encounters existing Linux-only Foundation API gaps and app/model/UI
tests require macOS. Those complete checks remain explicit QA gates on the
committed revision before any PR. Security Reviewer acceptance remains a separate
pending gate on that same revision.
