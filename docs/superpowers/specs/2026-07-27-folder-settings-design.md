# Folder Management Settings Design

> **Review note:** The post-merge interaction and visual refinements are
> specified in
> `2026-07-27-folder-settings-review-followup-design.md`. That follow-up
> supersedes this document where selection, toolbar hierarchy, row state, or
> Settings presentation differ.

## Goal

Move folder addition into Settings and give users a native macOS folder list
with plus and minus controls, without changing persisted sources,
security-scoped bookmarks, scanning, or existing sidebar behavior.

## Product behavior

- The library toolbar's primary action is Discover. Settings remains available
  as an icon-only `gearshape` utility and through the app menu. The library no
  longer presents an Add Directory menu.
- Empty library states open Settings instead of presenting another add menu.
- Settings lists every configured folder with its name, assigned agent,
  abbreviated path, enabled Toggle, and readable availability state.
- The plus control presents the existing agent-aware suggested and custom
  location menu, then opens the system directory picker.
- The minus control is disabled until a row is selected. Removing a selected
  folder requires confirmation and states that files remain on disk.
- Existing sidebar actions, including relocation and removal, remain available
  so established workflows are not removed.

## Architecture

`SkillLibraryModel` remains the single source of truth. `SettingsView` calls its
existing `addSource(at:agent:)` and `removeSource(_:)` methods, so bookmark
creation, persistence, rollback, scanning, selection, and security-scope
lifetime keep their current semantics.

`FolderSettingsSelection` is a small app-layer value that keeps the list
selection valid as folders are restored, added, or removed. It preserves an
explicit selection while that source exists and clears it when the source
disappears. It never selects a row on the user's behalf.

The reusable agent directory menu moves from the library feature into the
settings feature because Settings becomes its only caller. The library keeps a
directory importer only for relocating unavailable sources.

No model schema, storage path, bookmark format, package dependency, target, or
project-generation input changes.

## Visual and interaction design

The Settings window uses a grouped native `Form`, one selectable folder list,
and joined plus/minus controls in the list footer. Folder rows use semantic
system colors, full-strength names, and icon-plus-text exception states.

The folder panel uses semantic control and separator colors. On macOS 26 and
newer Liquid Glass is reserved for interactive controls; macOS 15 through 25
retain native control styling. Toggles and reconnect actions remain distinct
VoiceOver elements, and the window has flexible minimum and ideal dimensions.

## Error handling and data safety

- Picker cancellation makes no model change.
- Add errors use the existing "Unable to Add Folder" alert path.
- Remove errors use the existing "Unable to Remove Folder" alert path.
- Removal is transactional in `SkillLibraryModel`: persistence failure restores
  sources, skills, source state, and selection.
- Successful removal releases only the removed folder's security-scoped access.
- Opening Settings also requests source restoration; the model's existing
  one-time guard prevents duplicate restoration when both scenes appear.

## Testing and verification

- Keep the existing add, bookmark, recovery, and transactional-removal tests.
- Add Swift Testing coverage for folder-selection reconciliation before
  implementing that state.
- Run formatting, package tests, app tests, generated-project verification, and
  an unsigned build where the installed Xcode toolchain permits them.
- Launch the app with isolated Application Support data, open Settings, add a
  harmless test folder through the picker, remove it with confirmation, and
  capture the final Settings state for visual review.
