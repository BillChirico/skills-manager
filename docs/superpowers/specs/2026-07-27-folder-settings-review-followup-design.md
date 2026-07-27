# Folder Settings Review Follow-up Design

## Status

Approved for implementation from the Application Designer's blocking and
polish review, as directed by the Chief of Staff. This document is the visual,
interaction, accessibility, and regression contract for the follow-up branch.

## Goals

- Make Discover the primary library-toolbar action and reduce Settings to an
  icon-only utility action.
- Open Settings with no selected folder, preserve an explicit selection while
  it remains valid, and clear it when its source disappears.
- Make paused and unavailable folder states readable without lowering the
  contrast of the entire row.
- Expose accessible, native row controls for enabling a folder and reconnecting
  an unavailable folder.
- Bring Settings back to native macOS form hierarchy, spacing, resizing,
  separators, links, and empty-state behavior.
- Preserve every existing source identity, bookmark, storage location, scan
  path, sidebar action, and on-disk folder.

## Interaction design

### Library toolbar

Discover uses the prominent toolbar treatment because it is the primary
content action. Settings is a plain, icon-only gear utility. Both retain
tooltips and explicit accessibility labels.

### Selection

`FolderSettingsSelection.reconcile(with:)` never invents a selection. A
populated list can remain unselected, an existing selected source remains
selected, and a selection is cleared when that source is removed. A successful
user-initiated add may explicitly select the newly added source.

### Folder rows

Rows present the source name at full semantic foreground strength. Paths use
`~` for the current home directory and omit a trailing slash. Healthy enabled
rows have no decorative status checkmark. Exceptions use icon-and-text labels:
`Paused` for a disabled source and `Missing` for an unavailable source.

Each row owns a labeled native Toggle for the enabled state. An unavailable row
also owns a `Reconnect…` button that opens the existing security-scoped folder
picker and calls the existing relocation path. The Toggle remains a distinct
accessibility control. Because macOS merges a secondary button into a selectable
list row, that Toggle also exposes the same source-specific reconnect operation
as a named accessibility action, keeping the action directly operable by
VoiceOver.

### Settings layout

Settings uses a grouped `Form` with native sections rather than a redundant
large title. The folder list is a semantic background card; Liquid Glass is
reserved for interactive chrome such as the native plus/minus control group.
Its footer separator uses the macOS semantic separator color.

The empty folder state includes its own Add Folder menu. The catalog is a
native trailing `Link` row. The window has minimum and ideal dimensions but no
fixed size, allowing user resizing.

## Data and error behavior

The follow-up introduces no storage or bookmark schema changes. Toggle and
reconnect actions call `SkillLibraryModel` methods so persistence, rollback,
security-scoped access, scanning, and error reporting retain their existing
semantics. Picker cancellation is a no-op. Remove continues to delete only the
source record, never the user's files.

## Accessibility and appearance

- Do not use blanket row opacity to communicate state.
- Status is never icon-only; visible text and a meaningful accessibility label
  are required.
- Toggle and reconnect controls have source-specific labels. The Toggle remains
  independently focusable and an unavailable row mirrors Reconnect as a named
  accessibility action on that control.
- Use semantic system foregrounds, backgrounds, and separator colors in both
  light and dark appearances.
- Visual verification must capture the Settings window while it is the key
  window in both light and dark appearances so active selection and focus
  treatments are reviewed.

## Regression and acceptance coverage

Swift Testing locks selection reconciliation and pure row presentation,
including path abbreviation, paused state, unavailable state, reconnect
availability, and accessibility descriptions. Repository checks, package
tests, app tests, an unsigned build, and hands-on macOS verification must pass.

All four blocking findings and all eight polish findings are in scope. There
are no planned deferrals. The branch is pushed for QA and Security review
without opening a pull request; a pull request may be opened only after both
required reviews approve it.
