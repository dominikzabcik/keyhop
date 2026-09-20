# Contributing

Keyhop is a small personal project, but issues and pull requests are welcome.

## Build and test

```bash
swift test      # unit tests, plus the menu read back off its own pixels, on macOS, Linux and Windows
swift build     # debug build
```

Every screen is walked by `checks/`: each page of the website and each section of Keyhop's window at
three widths, every control pressed, and every reading command run. See `checks/README.md`.

```bash
cd checks && npm install && npx playwright install chromium
node run.mjs            # the website, the window and the commands
node run.mjs --review   # and ask Jev what it thinks of what each screen says
```

| System | Needs | Packages |
| --- | --- | --- |
| macOS | macOS 14 or later, Xcode 16 or the Swift toolchain | `./scripts/build-app.sh --install` builds the universal app, copies it to Applications and opens it |
| Linux | Swift 6.3.3 and its [static Linux SDK](https://www.swift.org/documentation/articles/static-linux-getting-started.html), plus [nfpm](https://nfpm.goreleaser.com) for packages | `./scripts/package-linux.sh` (or `--no-packages` for the tarball only) |
| Windows | The Swift toolchain for Windows and Visual Studio's C++ tools | `./scripts/package-windows.ps1` |

To try the Mac UI without your own accounts, use the preview flags. They show real windows with sample data and never touch your Keychain or logs:

```bash
.build/debug/Keyhop --preview-menu cursor
.build/debug/Keyhop --preview-window usage
.build/debug/Keyhop --preview-welcome
```

The rest of the Mac debug tools are listed at the top of `Sources/Keyhop/App/DebugTools.swift`.

The tray menus can be checked on any system from sample data, which holds no real logins:

```bash
keyhop status --sample --json > sample.json
python3 packaging/linux/keyhop-tray --print-menu sample.json   # the Linux menu
.build/debug/KeyhopTray --print-menu sample.json               # the Windows menu
keyhop dashboard --sample                                      # the dashboard, with made-up accounts
```

With `--status-file sample.json`, the real trays show that data without running `keyhop`, and `--show-menu` or `--show-dialog` open the menu or a prompt for screenshots. CI captures both trays this way.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/Keyhop/Providers` | One adapter per tool: read the login, apply one, sign out locally, fetch limits |
| `Sources/Keyhop/Core` | `AccountService` (the switching rules every platform shares), secret stores, releases, platform paths, shell and HTTP helpers, and the Mac account store and updater |
| `Sources/Keyhop/Tracking` | Log readers, pricing, the usage database, budgets, forecasts and alert rules |
| `Sources/Keyhop/CLI` | The `keyhop` command, its JSON documents and sample data |
| `Sources/Keyhop/Dashboard` | The local dashboard: a small loopback HTTP server, its JSON API and access checks, and the page itself |
| `Sources/Keyhop/UI` | The Mac menu, the window that hosts the dashboard, the welcome window, design tokens and controls |
| `Sources/Keyhop/Cloud` | Linking to Keyhop cloud, its client, and the hourly sync of daily totals |
| `cloud` | Keyhop cloud itself: a Cloudflare Worker with D1 for GitHub sign-in, teams, leaderboards and profiles. See [cloud/README.md](cloud/README.md) |
| `Sources/KeyhopTray` | The Windows tray app; its menu model builds and runs everywhere |
| `Sources/CSQLite` | The SQLite amalgamation, used on Linux and Windows |
| `packaging/linux` | The Linux tray, desktop entry, AppStream metadata, nfpm description and `~/.local` installer |
| `packaging/windows`, `packaging/icons` | The Windows icon and the app icon at every size |
| `Casks`, `bucket` | The Homebrew cask and the Scoop manifest |
| `scripts` | Build, packaging, art, pricing table and disk image settings |
| `Tests/KeyhopTests` | Unit tests, and the menu bar panel read back off its own pixels |
| `checks/` | Every screen walked in a browser, every command run, and Jev's read on what they say |
| `ios/UITests` | The phone's screens, driven in a simulator |

The Linux and Windows trays only talk to `keyhop ... --json`. When you change a JSON document in `Sources/Keyhop/CLI/Reports.swift`, add fields rather than renaming them, or update both trays in the same change.

## Conventions

- Match the code around you: small types, comments that explain why, no dead code.
- Platform differences live behind `#if os(...)` in the smallest place that needs them.
- Parsing, pricing and switching changes need a test in `Tests/KeyhopTests`.
- Refresh model prices with `python3 scripts/update-pricing.py`, and re-render art with `./scripts/render-art.sh` after changing `scripts/render-art.swift`.
- Never commit real tokens, account emails or logs, including in test fixtures and screenshots.

## Releases

Bump `VERSION` and `AppVersion.number`, add a section to `CHANGELOG.md`, and commit. Run the Release workflow by hand for a dry run, then push a `v<version>` tag. The workflow checks the three agree, tests and builds on every system, publishes all downloads with one `SHA256SUMS`, and commits the Scoop, AUR and winget manifests that `scripts/render-manifests.py` writes. Every updater installs a release only when its checksum matches.
