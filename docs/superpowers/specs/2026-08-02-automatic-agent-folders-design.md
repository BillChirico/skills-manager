# Automatic Agent Folders Design

## Goal

When Skills Manager starts, it automatically configures every supported standard
agent skills directory that already exists under the signed-in account home. A
folder the user removes stays removed across later launches, while manually
adding that folder again opts it back into the library.

## Behavior

- Discovery runs once as part of `SkillLibraryModel.restoreSources()`.
- Only real directories at a supported agent's standard location are eligible.
- Persisted sources win over automatic candidates and are never duplicated.
- Global and Codex both map to `~/.agents/skills`; URL de-duplication keeps one
  source and the existing `SkillAgent.allCases` order assigns it to Global.
- Automatic additions are persisted before scanning and do not change the
  sidebar selection.
- Removing a standard location adds its normalized URL to a durable exclusion
  set in the same atomic write that removes the source.
- Removing a custom folder does not add an exclusion.
- Manually adding an excluded standard location clears its exclusion in the same
  atomic write that restores the source.
- An unavailable account home or a standard location that is not a directory is
  ignored without an error.

## Persistence

`SkillSourceConfiguration` groups configured sources and excluded automatic
directory URLs. `SkillSourceStore` gains configuration load/save requirements
with source-only default implementations so existing conformers remain valid.
`JSONSkillSourceStore` writes the configuration as one owner-only JSON document,
making source removal and opt-out atomic. The store applies owner-only
permissions to a same-directory temporary file before atomically renaming it,
so a failed pre-commit step leaves the last good configuration intact. It
continues decoding the legacy top-level source array and preserves exclusions
when callers use the source-only API.

The normalized configured URLs are removed from the exclusion set during
restore. This repairs an inconsistent or manually edited configuration in favor
of the explicit configured source.

## App Integration

`SkillLibraryModel` receives the account home and a directory-existence closure.
Production composition supplies `UserHomeDirectory.current` and the existing
directory check. Tests inject deterministic paths and never inspect real user
folders.

The model derives standard locations from `SkillAgent`, filters them by disk
existence and exclusions, then merges them with restored sources. Existing
bookmark restoration remains unchanged for legacy records.

## Error Handling

Automatic additions use the existing restore error surface. A configuration
load or save failure reports `Unable to Restore Directories` and never claims an
unpersisted automatic source. Source-configuration mutations are serialized
across the persistence commit or rollback so a failing operation cannot restore
state over a later successful mutation. Rollback applies only the failed
source's deltas so unrelated scan and UI changes survive. The boundary is
released before scans, which revalidate the source after discovery before
publishing results. If rollback follows an invalidated in-flight scan, the
restored source becomes available instead of remaining permanently scanning.

## Testing

Swift Testing regressions cover:

- configuration round-tripping, legacy-array decoding, exclusion preservation,
  missing-file defaults, and owner-only permissions;
- adding only existing standard directories during restore;
- Global/Codex URL de-duplication and persisted-source de-duplication;
- durable removal across a fresh model instance;
- manual re-add clearing the opt-out;
- custom removal not creating an opt-out; and
- rollback of source and exclusion state after a failed save;
- serialized overlapping mutations and delta rollback that preserves unrelated
  UI/scan state while normalizing invalidated scans; and
- failed commits preserving the last good owner-only file without temp leaks.

## Documentation

The README, architecture guide, and agent guides must describe startup
auto-detection, durable opt-out, the combined persistence schema, and the rule
that tests inject filesystem checks rather than reading a developer's home.
