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

4. Give the child only the existing scrubbed environment, but point `HOME` and
   `CODEX_HOME` into the disposable home. No real agent directory, package
   manager configuration, credential environment variable, or project lock is
   exposed.
5. After a zero exit, reject oversized or non-UTF-8 output, unknown terminal
   controls, unknown lines, failure/skip/deletion diagnostics, duplicate names,
   names not present in the validated lock, or inconsistent found/update/summary
   counts. Return only the validated set of updated skill directory names.
6. Remove stdout, working directory, canonical lock, and the complete temporary
   home with `defer`, including launch failure, nonzero exit, timeout,
   cancellation, parse failure, and success paths.

The CLI may download repositories and install into the disposable home while
probing. Those writes are intentional and are deleted. It never receives a
path to a real skill installation.

## Model and UI behavior

`AgentSkill` gains optional detected availability so existing decoded values
remain compatible. A non-nil detection result is authoritative; legacy
installed/available version comparison remains a fallback only when no check
has run.

After restored sources finish scanning, `SkillLibraryModel` runs one update
check. It clears prior detection before awaiting, applies the returned set to
all matching installation directory names in one main-actor update, and records
whether the result is current or unavailable. Cancellation and every error
leave no positive update claims. Parser or CLI errors are surfaced through the
existing safe alert path; raw output and lock contents are never logged or
shown.

The Updates Available empty state distinguishes checking, not checked,
unavailable, and confirmed-current states. It offers a manual retry when a
check has not produced a current result.

`SkillLibrarySorter` uses update availability as an invariant primary key.
Within the update and current partitions, it preserves the selected name,
date-added, or agent ordering and existing stable tie breakers. This makes the
result deterministic without overriding the user's chosen secondary order.

Each update row shows a compact `Update` label with the download symbol. The
text, shape, and symbol make the state independent of color, while the row's
explicit accessibility label continues to announce “Update available.”

## Testing

Focused Swift Testing coverage uses temporary directories and injected command
runners only. It covers the exact argument vector and isolated environment,
canonical lock mirroring, success/no-update parsing, malformed and injected
output, count/name mismatches, oversized input/output, nonzero exit,
cancellation, and cleanup. Model tests cover successful mapping and fail-closed
state. Sorter tests prove update-first ordering for every sort choice and
deterministic order within both partitions.

The Windows implementation host has no Swift or Xcode toolchain. Static checks
and diff review can run here, but compilation, all Swift tests, and the macOS UI
check remain explicit QA gates on the committed revision before any PR.
