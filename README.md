# Skills Manager

Skills Manager is a native macOS app for finding and managing the agent skills
stored on your machine.

The current product surface includes:

- a SwiftUI three-column library with smart groups, scoped search, multi-select,
  detail tabs, and recovery-focused empty states;
- persistent user-selected directories backed by security-scoped bookmarks;
- suggested user skill locations for Claude Code, Codex, Cursor, Gemini, and
  GitHub Copilot, while retaining a picker for custom directories;
- per-directory agent assignments for Claude Code, Codex, Cursor, Gemini,
  GitHub Copilot, and other tools;
- local `SKILL.md` discovery with stable skill identities across rescans;
- a skills.sh Discover window that opens on the catalog's most downloaded
  skills, ranks search results by download count, shows the download count on
  every row and in the detail view, links out to the skill's skills.sh page, and
  displays the page's install command with a copy action;
- installation into one or many configured directories from a single download;
- name, date-added, and agent sorting, with the agent and source shown on every
  skill row;
- right-click actions for updating, enabling, revealing, opening, copying the
  path of, and removing a skill;
- directory rename, agent assignment, enable, rescan, reveal, and remove
  controls;
- a resizable Settings folder list with native plus/minus management controls,
  per-folder enabled toggles, unavailable-folder reconnect actions, agent-aware
  suggested locations, and non-destructive removal;
- a prominent Discover toolbar action, icon-only Settings access, and the
  standard Settings app-menu command;
- independent enabled and update-availability state for each skill;
- a reusable `SkillsCore` Swift package for discovery, persistence, models,
  filtering, search, catalog access, and safe package installation;
- Swift Testing coverage for the core package and app state;
- an XcodeGen project specification and generated Xcode project; and
- contributor and AI-agent guidance.

The app deploys to macOS 15 and adopts Liquid Glass when running on macOS 26 or
newer, with a material-based fallback on earlier supported versions.

## Requirements

- macOS 15 or newer
- Xcode 26 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46 or newer

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

GitHub-backed results can be installed into one or many enabled, available agent
directories. Selecting several directories downloads the package once and copies
it into each of them; one directory's failure does not stop the others, and the
per-directory outcome is reported. Installation downloads only the selected skill
directory, validates every relative path, caps package size and file count,
stages the files before moving them into place, and never replaces an existing
directory.

### The install command

The detail view shows the same `npx skills add …` command that skills.sh prints
at the top of a skill page, with a copy action for running it yourself.

Skills Manager **displays** that command; it never executes it. Installing from
the app performs the command's work natively: it downloads the same files over
HTTPS and copies them into the directories you selected. Skills are copied as
data and are not executed during installation. Installed skills are instructions
that an agent may later follow with that agent's own permissions, so review
`SKILL.md` before allowing an agent to use one. Two reasons installation is not a
shell invocation:

- `npx` fetches and runs arbitrary remote code, which would turn a catalog entry
  into local code execution.
- The app is sandboxed and writes only through user-selected directory grants,
  which a spawned CLI would neither inherit nor respect.

The command is rebuilt locally from validated catalog fields rather than scraped
from the remote page, so the text on screen cannot contain shell metacharacters.
Dot-prefixed installation slugs are rejected so a catalog entry cannot create a
hidden directory that Skills Manager's scanner would skip.

## Directory access

Settings lists every configured skill folder. Its plus menu includes each
supported agent’s standard user location, including `~/.agents/skills` for
Codex and `~/.claude/skills` for Claude Code, along with custom locations.
Choosing a suggestion opens the system directory picker at that location; the
app remains sandboxed, so the user must confirm the folder before Skills
Manager can scan it. Empty library states open Settings rather than duplicating
this picker flow. Settings itself includes an Add Folder action when the list is
empty.

Confirmed directories are opened as security-scoped resources before the app
creates and stores their bookmarks. This keeps the initial scan and access after
relaunch covered by the same user grant. Settings opens without selecting a
folder on the user's behalf. Each row can pause or resume scanning, unavailable
rows can reconnect through the system picker, and paths under the home directory
are abbreviated with `~`. Selecting a row and using the minus control removes
only the Skills Manager configuration after confirmation; the folder and its
files remain on disk.

## Repository layout

```text
SkillsManager/                  SwiftUI application target
  App/                          app entry point and shared app state
  Features/                     feature-oriented views
  Shared/                       reusable app-only presentation components
  Resources/                    asset catalogs
  Support/                      entitlements and target support files
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
