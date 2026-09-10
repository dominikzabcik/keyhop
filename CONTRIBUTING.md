# Contributing

Switchr is a small personal project, but issues and pull requests are welcome.

## Build and test

Requires macOS 14 or later and Xcode 16 or the Swift toolchain.

```bash
swift test                          # unit tests
swift build                         # debug build
./scripts/build-app.sh --install    # universal app, copied to Applications and opened
```

To try UI changes without your own accounts, use the preview flags. They show real windows with sample data and never touch your Keychain or logs:

```bash
.build/debug/Switchr --preview-menu cursor
.build/debug/Switchr --preview-insights
.build/debug/Switchr --preview-welcome
```

The rest of the command-line tools are listed at the top of `Sources/Switchr/App/DebugTools.swift`.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/Switchr/Providers` | One adapter per tool: read the login, apply one, sign out locally, fetch limits |
| `Sources/Switchr/Tracking` | Log readers, pricing, the usage database, budgets, forecasts and alerts |
| `Sources/Switchr/Core` | Account store, Keychain vault, updater, shell and HTTP helpers |
| `Sources/Switchr/UI` | Menu, Insights, welcome window, brand and controls |
| `scripts` | Build, art, pricing table and disk image settings |
| `Tests/SwitchrTests` | Unit tests |

## Conventions

- Match the code around you: small types, comments that explain why, no dead code.
- Parsing and pricing changes need a test in `Tests/SwitchrTests`.
- Refresh model prices with `python3 scripts/update-pricing.py`, and re-render art with `./scripts/render-art.sh` after changing `scripts/render-art.swift`.
- Never commit real tokens, account emails or logs, including in test fixtures and screenshots.

## Releases

Bump `VERSION`, add a section to `CHANGELOG.md`, commit, then push a `v<version>` tag. The Release workflow tests, builds and publishes the zip, disk image and checksums. The app's updater installs a release only when its checksum matches.
