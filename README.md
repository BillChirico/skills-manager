# Skills Manager

Skills Manager is a native macOS app for finding and managing the agent skills
stored on your machine. The long-term product surface includes installing,
updating, removing, searching, and organizing skills across user-selected
directories.

This repository currently contains the first production-oriented scaffold:

- a SwiftUI macOS app with a three-column library shell;
- a reusable `SkillsCore` Swift package for models and domain logic;
- macOS sandbox entitlements for user-selected skill directories;
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
