# Skills Manager

Skills Manager is a native macOS app for finding and managing the agent skills
stored on your machine.

The current product surface includes:

- a SwiftUI three-column library with smart groups, scoped search, multi-select,
  detail tabs, and recovery-focused empty states;
- persistent user-selected skill directories;
- one-click suggested locations for the shared `~/.agents/skills` folder, Claude
  Code, Codex, Cursor, Gemini, and GitHub Copilot, listed only while the folder
  exists, plus a picker for any other directory;
- per-directory agent assignments for Global, Claude Code, Codex, Cursor,
  Gemini, GitHub Copilot, and other tools;
- local `SKILL.md` discovery with stable skill identities across rescans;
- a skills.sh Discover window that opens on the catalog's most downloaded
  skills, ranks search results by download count, shows the download count on
  every row and in the detail view, links out to the skill's skills.sh page, and
  displays the page's install command with a copy action;
- installation into one or many supported agent directories through the official
  `skills` CLI;
- name, date-added, and agent sorting, with the agent and source shown on every
  skill row;
- real CLI-backed update and on-disk removal actions, plus controls for enabling,
  revealing, opening, and copying the path of a skill;
- directory rename, agent assignment, enable, rescan, reveal, and remove
  controls;
- a resizable Settings folder list with native plus/minus management controls,
  per-folder enabled toggles, unavailable-folder reconnect actions, agent-aware
  suggested locations, and non-destructive removal;
- a prominent Discover toolbar action, icon-only Settings access, and the
  standard Settings app-menu command;
- independent enabled and update-availability state for each skill;
- a reusable `SkillsCore` Swift package for discovery, persistence, models,
  filtering, search, catalog access, and shell-free CLI lifecycle operations;
- Swift Testing coverage for the core package and app state;
- an XcodeGen project specification and generated Xcode project; and
- contributor and AI-agent guidance.

The app deploys to macOS 15 and adopts Liquid Glass when running on macOS 26 or
newer, with a material-based fallback on earlier supported versions.

## Requirements

- macOS 15 or newer
- Xcode 26 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46 or newer
- Node.js 18 or newer with `npx` available through a standard installation path

Install XcodeGen with Homebrew:

```sh
brew install xcodegen
```

## Getting started

Generate the Xcode project, then open it:

```sh
make generate
open SkillsManager.xcodeproj
```

The generated project is committed so that a fresh clone can also be opened
immediately. Run `make generate` after changing `project.yml`.

## Validation

```sh
make test
make build
make check
```

`make test` exercises the standalone domain package and does not require the
full Xcode app. `make build` and the app unit tests require Xcode. Swift sources
are formatted with the `swift format` command included in the Swift toolchain;
run `make lint` for a non-mutating style check.

## Catalog browsing and installation

The Discover Skills window opens on the skills.sh all-time download leaderboard,
so the first screen is a ranked list rather than an empty search field. Typing
two or more characters switches to search, and both modes are ordered by
download count. Each row and the detail view show that count, and the detail
view links to the skill's page on skills.sh.

GitHub-backed results can be installed into one or many enabled, available
default agent directories. Skills Manager invokes the official `skills` CLI once
per selected directory and reports one outcome per directory, so one failure does
not stop the remaining installs. Successful installs are rescanned from disk and
selected in the library.

Update and remove actions use the same lifecycle boundary. Update invokes the
CLI, then rescans all available sources because the CLI can reconcile shared lock
state across agents. Remove deletes the successful skill directories from the
library and disk, rescans affected sources, and leaves failed selections visible.
Busy state prevents the same skill from receiving overlapping mutations.

### The install command

The detail view shows the `npx skills add …` command that skills.sh prints at the
top of a skill page, with a copy action. App actions execute the official CLI
directly as an executable plus argument vector; no shell parses the command and
no remote string becomes executable syntax. The app supplies the CLI's
non-interactive global, agent, and copy flags for installs, and the corresponding
official update and remove forms for existing skills.

Catalog owners, repository names, slugs, local directory names, and leading
options are validated before they can become process arguments. Dot-prefixed
installation slugs are rejected so a catalog entry cannot create a hidden
directory that discovery would skip. Lifecycle operations are limited to each
supported agent's standard directory. Custom directories remain discoverable
and readable but are not install, update, or remove targets.

The child process receives a minimal environment containing the account home,
the resolved `npx`/Node path, locale and temporary-directory settings, telemetry
opt-outs, and non-interactive npm settings. Unrelated parent variables and secrets
are not forwarded. Standard input and output are disconnected, and the app
verifies the expected `SKILL.md` or directory state after the CLI exits.

This boundary prevents shell injection; it does not make third-party code
trusted. `npx` may download and execute the npm-hosted `skills` package, and that
CLI downloads community-authored skill content. The app therefore ships without
App Sandbox so the child process can reach Node, the network, and supported agent
directories. Install only from sources you trust and review `SKILL.md` before an
agent uses it.

Text extracted from an installed `SKILL.md` is also untrusted. The library
renders its overview as non-interactive text, so Markdown destinations do not
become clickable links in the app. These presentation and download safeguards
limit specific attack paths; they do not verify a skill's publisher or make its
instructions safe. Review the installed manifest before an agent uses it.

## Directory access

Settings lists every configured skill folder. Its plus menu suggests each
supported agent’s standard user location — `Global — ~/.agents/skills`,
`Claude Code — ~/.claude/skills`, and the rest — and lists a suggestion only
while that folder exists on the account home, so the menu never offers a folder
you have not created. Choosing one adds it directly, with no picker step. A
single `Add Folder…` action below the suggestions opens the system picker for
any other directory.

`Global` and `Codex` both resolve to `~/.agents/skills`, the cross-agent
convention Codex also reads, so both suggestions appear when that folder exists.
Adding the second one re-selects the folder the first one configured instead of
listing it twice.

Direct add uses the account-home path. Empty library states open Settings rather
than duplicating the picker flow, and Settings includes an Add Folder action when
the list is empty. If the operating system cannot resolve the signed-in account's
home directory, Skills Manager suppresses home-based suggestions and picker
defaults instead of guessing, and lifecycle operations fail before launching a
process.

The app stores configured directory URLs in its application-support data and
ships without App Sandbox so the official CLI can perform lifecycle operations.
Settings opens without selecting a folder on the user's behalf. Each row can
pause or resume scanning, unavailable rows can reconnect through the system
picker, and paths under the home directory are abbreviated with `~`. Selecting a
directory row and using the minus control removes only the Skills Manager
configuration; selecting a skill and confirming Remove from Disk invokes the CLI
and deletes that skill directory. Path abbreviation is skipped when the account
home cannot be resolved.

## Repository layout

```text
SkillsManager/                  SwiftUI application target
  App/                          app entry point and shared app state
  Features/                     feature-oriented views
  Shared/                       reusable app-only presentation components
  Resources/                    asset catalogs
Packages/SkillsCore/            platform-light domain package and tests
Tests/SkillsManagerTests/       app-state unit tests
docs/                           architecture and engineering decisions
project.yml                     source of truth for the Xcode project
SkillsManager.xcodeproj/        generated, committed Xcode project
```

See [Architecture](docs/ARCHITECTURE.md) for dependency boundaries and planned
extension points. See [AGENTS.md](AGENTS.md) for repository conventions that
apply to both human and AI contributors.

## License

Skills Manager is available under the [MIT License](LICENSE).
