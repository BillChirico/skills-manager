# Folder Settings Review Follow-up Implementation Plan

**Goal:** Resolve the four blocking and eight polish findings from the
post-merge folder Settings review without changing existing folder data or
behavior.

**Architecture:** Keep `SkillLibraryModel` and `SkillSource` as the source of
truth. Refine app-layer selection and row presentation, then connect native
SwiftUI controls to the model's existing enable, relocate, add, and remove
operations.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Testing, XcodeGen, macOS
15 deployment target with guarded macOS 26 styling.

## Review contract

- [x] Discover is prominent; Settings is an icon-only utility.
- [x] Settings opens without auto-selecting a row and clears stale selection.
- [x] Disabled rows retain readable contrast and show `Paused` as icon + text.
- [x] Rows provide an accessible enabled Toggle and unavailable rows provide
  `Reconnect…`.
- [x] Settings uses grouped Form sections without a redundant large title.
- [x] The folder footer uses the semantic separator color and safe direction.
- [x] The static list container uses semantic background, not Liquid Glass.
- [x] Paths abbreviate the home directory and trim trailing slashes.
- [x] Healthy-row status checkmarks are removed.
- [x] The skills.sh catalog uses a native trailing Link layout.
- [x] The empty state includes an Add Folder action menu.
- [x] The Settings window is resizable with minimum and ideal dimensions.

## Test-driven implementation

1. Update Swift Testing selection cases to require no default selection and
   stale-selection clearing. Run focused tests and observe the old fallback
   fail.
2. Add row-presentation tests for abbreviated paths, status text and symbols,
   reconnect visibility, and accessible state descriptions. Run focused tests
   and observe the missing presentation type fail.
3. Implement the smallest selection and presentation values that pass those
   tests.
4. Refine the toolbar and Settings UI, wiring Toggle and reconnect actions to
   existing model operations.
5. Update README, architecture, and agent guidance with the final behavior.

## Verification and handoff

1. Run formatter/lint, package tests in a task-specific scratch directory, app
   tests, project-generation verification, and an unsigned app build.
2. Launch with isolated Application Support data and exercise selection,
   Toggle, reconnect, add, and remove behavior.
3. Capture light and dark Settings screenshots while the Settings window is
   key.
4. Record every finding and any deferral in the design-audit report.
5. Push the tested follow-up branch. Request QA and Security review and do not
   open a pull request until both approve.
