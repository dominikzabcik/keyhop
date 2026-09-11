<p align="center">
  <img src="docs/banner.png" alt="Switchr" width="100%">
</p>

<p align="center">
  Move Claude Code, Cursor or Codex onto another account in one click,<br>
  with every saved account's limits, usage and budget in view.
</p>

<p align="center">
  <a href="https://github.com/dominikzabcik/switchr/actions/workflows/ci.yml"><img src="https://github.com/dominikzabcik/switchr/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/dominikzabcik/switchr/releases/latest"><img src="https://img.shields.io/github/v/release/dominikzabcik/switchr?label=release&color=171717" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-171717" alt="MIT license"></a>
</p>

<p align="center">
  <sub>macOS 14+ app and menu bar · Linux tray on x86_64 and aarch64 · Windows 10 and 11 notification area</sub>
</p>

<p align="center">
  <img src="docs/dashboard.png" width="860" alt="The Switchr dashboard with sample accounts: today's tokens and API value, each tool's account in use with its limits, today by hour and the last 7 days">
</p>

<p align="center">
  <img src="docs/menu.png" width="300" alt="Switchr's Mac menu on the Claude tab: the account in use with its 5-hour and weekly limits, and another account to switch to">
</p>

## Install

**macOS and Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/dominikzabcik/switchr/main/install.sh | bash
```

**Windows** (PowerShell, no administrator rights needed)

```powershell
irm https://raw.githubusercontent.com/dominikzabcik/switchr/main/install.ps1 | iex
```

Both installers download the latest release and check its SHA-256 before installing anything. [Read install.sh](install.sh) or [install.ps1](install.ps1) before piping them into a shell.

| System | What the installer does | Or install it yourself |
| --- | --- | --- |
| macOS 14 or later | Installs Switchr into Applications, links the `switchr` command onto your PATH, and opens it. Files downloaded this way aren't flagged by Gatekeeper, so there's no security prompt. | `Switchr.dmg` from the [latest release](../../releases/latest), or `brew tap dominikzabcik/switchr https://github.com/dominikzabcik/switchr && brew install --cask switchr` |
| Fedora, RHEL | Installs the RPM with `dnf` | `sudo dnf install ./switchr-<version>-1.x86_64.rpm` |
| Debian, Ubuntu | Installs the DEB with `apt` | `sudo apt install ./switchr_<version>_amd64.deb` |
| Arch Linux | Installs the package with `pacman` | `sudo pacman -U switchr-<version>-1-x86_64.pkg.tar.zst`, or build the release's `switchr-bin` PKGBUILD with `makepkg -si` |
| Any other Linux | Installs the portable build into `~/.local`, without root. Set `SWITCHR_LOCAL=1` to choose this anywhere. | Unpack `switchr-<version>-linux-<arch>.tar.gz` and run `./install-local.sh` |
| Windows 10 and 11 | Installs into `%LOCALAPPDATA%\Programs\Switchr`, adds `switchr` to your PATH and the Start menu, and opens at sign-in. Windows on Arm runs the same build through its x64 emulation. | `scoop bucket add switchr https://github.com/dominikzabcik/switchr` then `scoop install switchr` |

Every Linux download runs on x86_64 and aarch64. The `switchr` binary is fully static, so it doesn't depend on your distribution's libraries. The tray uses GTK 3, AppIndicator and libnotify for Python, which the packages pull in.

<details>
<summary><b>macOS: installing from the disk image</b></summary>
<br>

Switchr isn't notarized, so macOS blocks the first launch from the disk image. Open **System Settings › Privacy & Security** and choose **Open Anyway**. If you launch Switchr straight from the disk image or from Downloads, it offers to move itself into Applications.

On first launch, a welcome window lists the logins Switchr found and turns on Open at login, then Switchr's window opens. Opening Switchr again from Applications, Spotlight or the Dock brings the window back; at login it starts quietly in the menu bar.

<p align="center">
  <img src="docs/welcome.png" width="420" alt="Switchr's welcome window listing the Claude Code, Cursor and Codex logins it found">
</p>

</details>

<details>
<summary><b>Linux: GNOME and the tray</b></summary>
<br>

With WebKitGTK for Python installed (the packages recommend it), **Open Switchr** shows the dashboard in its own window; otherwise it opens in a Chromium-based browser's app window or your default browser.

GNOME hides tray icons unless the **AppIndicator and KStatusNotifierItem Support** extension is on. Fedora and Ubuntu ship it (`gnome-shell-extension-appindicator`), and the packages recommend it. Turn it on in Extensions, then log out and back in. KDE Plasma, Cinnamon, Xfce, MATE and Budgie show the tray without it. `switchr doctor` tells you whether your desktop has a tray host.

</details>

## Use

| | |
| --- | --- |
| **Add an account** | Sign in to the tool as usual and Switchr saves the login. For another account, choose **Add account**: Switchr signs the tool out on this computer only, so the saved token stays valid, and saves the next login you make. |
| **Switch** | Click one of a tool's other accounts. Each shows how much of its tightest limit is used. On macOS, when the account in use runs low, the one with the most room is marked, and you can right-click an account to rename or remove it. |
| **Read the limits** | macOS shows the account in use with a large bar per limit, where a tick marks an even pace. On Linux and Windows, the menu shows each account's tightest limit and the icon shows the busiest account's two nearest limits. |
| **Rename, remove and budgets** | On macOS, right-click an account in the menu, or use Switchr's window, which also sets budgets. On Linux and Windows, use the tray's **Accounts** submenu to rename or remove an account, and **Set a budget** for a monthly budget across all accounts. |
| **Dashboard** | Switchr's window: Overview, Accounts, Usage (charts, activity, token mix, models), Budgets and Settings. On macOS, open Switchr from Applications or choose **Open Switchr** in the menu. Click the tray icon on Windows, choose **Open Switchr** in the Linux tray, or run `switchr dashboard` anywhere. |
| **Alerts** | A notification when a limit or budget is nearly used, with a **Switch** button that moves you to the saved account with the most room. |

Codex logins made with an API key aren't supported, only ChatGPT sign-ins.

### The `switchr` command

The same commands work on every system. On macOS, the installer and the Homebrew cask link the app binary onto your PATH as `switchr`; otherwise run `/Applications/Switchr.app/Contents/MacOS/Switchr` with the same arguments.

```text
switchr status [--refresh]              accounts, limits and today's usage
switchr switch work@studio.dev          move a tool to a saved account (email, name or ID)
switchr add cursor                      sign Cursor out here and save the next login
switchr rename work@studio.dev Work     give an account a name
switchr usage --range 30d --tool claude tokens and API value by account and model
switchr dashboard                       open Switchr's window: accounts, usage, budgets, settings
switchr insights --output usage.html    save the dashboard as one file you can share or keep
switchr budget set all 200 --period month
switchr update                          install the latest verified release
switchr doctor                          paths, secret storage and what Switchr can see
```

Add `--json` to any of them for scripts. `switchr status --sample` and `switchr dashboard --sample` show made-up accounts, for trying Switchr out or taking screenshots. `switchr help` lists everything.

## Usage tracking

Switchr keeps its own record of what every account uses.

| Source | What Switchr reads |
| --- | --- |
| Claude Code | `~/.claude/projects/**/*.jsonl`, one entry per response, with input, cache writes (5-minute and 1-hour), cache reads and output |
| Codex | `~/.codex/sessions/**/*.jsonl`, per-response usage records, or running totals in older sessions |
| Cursor | Each saved account's usage export from cursor.com, at most twice an hour |

- **Per account:** each request is credited to the account that was in use at that moment. Switchr records every switch, including logins you change outside it. Usage from before Switchr started goes to the tool's only saved account when there's one.
- **API value:** requests are priced at each provider's standard API rates, from a table generated from [models.dev](https://models.dev). Subscriptions don't bill per token, so API value measures how much use you get, not what you pay. Cursor's on-demand charges are shown separately as billed.
- **Budgets:** set one per account or across all accounts, per day, week or month, in the Budgets section of Switchr's window or with `switchr budget` anywhere. The Linux and Windows trays set a monthly budget across all accounts. Switchr notifies you at 80% and at 100%.
- **Forecasts:** Switchr samples each limit and projects when it runs out at the recent rate. Once a limit is half used and on track to run out before it resets, the alert offers the switch.

<p align="center">
  <img src="docs/dashboard-usage.png" width="860" alt="The dashboard's Usage section with sample data: tokens, API value, requests and cache share, a stacked chart by account, 26 weeks of activity, token mix, models and accounts">
</p>

## What a switch does

```mermaid
sequenceDiagram
    participant You
    participant Switchr
    participant Store as Keychain, Secret Service or DPAPI
    participant Tool as Claude Code, Cursor or Codex
    You->>Switchr: Click an account
    Switchr->>Tool: Read the current login
    Switchr->>Store: Save it first, so no login is ever lost
    Switchr->>Store: Load the chosen account
    Switchr->>Tool: Hand the login over
    Switchr->>Tool: Read back to confirm it's live
```

| Tool | Where the login lives | How it takes the new one |
| --- | --- | --- |
| Claude Code | macOS: Keychain item `Claude Code-credentials`. Linux and Windows: `~/.claude/.credentials.json`. Only `claudeAiOauth` changes, so MCP tokens stay untouched, plus `oauthAccount` in `~/.claude.json`. | On macOS, Claude Code rereads its login every 30 seconds, so open sessions move over without a restart. Elsewhere new sessions use it; restart an open one with `claude --continue` if it stays on the old account. |
| Cursor | `cursorAuth/*` rows in `state.vscdb` (macOS `~/Library/Application Support/Cursor`, Linux `~/.config/Cursor`, Windows `%APPDATA%\Cursor`), plus `authInfo` in `~/.cursor/cli-config.json` | An open Cursor gets the tokens through its own login link (`cursor://cursorAuth`) and switches in place. A closed Cursor has its rows swapped directly. |
| Codex | `~/.codex/auth.json` (or `$CODEX_HOME`) | New runs use it straight away. A running session keeps its original account, so reopen it with `codex resume --last`. |

Tools rotate their tokens on their own, so Switchr re-saves the in-use login on every refresh. Limits are fetched with each account's own token. Switchr only refreshes tokens for accounts that aren't in use, so a running session never has its token rotated out from under it.

## Settings

| Setting | Default | macOS | Linux and Windows |
| --- | --- | --- | --- |
| Check usage every 5 minutes | On | **…** menu | **Check usage automatically** in the tray menu |
| Check for updates | On | Daily, **…** menu | Twice a day |
| Install updates automatically | On | **…** menu | Windows and the portable Linux build: **Install updates automatically** in the tray menu. Linux packages notify you instead, since installing needs your password. |
| Open at login | On with the installers | Welcome window and **…** menu | **Open at sign-in** in the tray menu |

The Linux tray keeps its settings in `~/.config/switchr/tray.json`, the Windows tray in `HKCU\Software\Switchr`. `switchr reset` removes both.

## Updates

Switchr updates from this repository's releases. A release without a checksum, or with one that doesn't match, is never installed.

- **macOS:** the app downloads `Switchr.zip`, checks it against `SHA256SUMS`, confirms the bundle inside is the expected version, swaps it in place and reopens. Click the version number in the menu's footer to check right away.
- **Linux:** `switchr update`, or **Update** in the tray, downloads the package for the way you installed Switchr and installs it with `dnf`, `apt` or `pacman` (asking for your password through `sudo` or your desktop's dialog). The tray tells you once when a new version is out. The portable build updates in `~/.local` without root, automatically when that setting is on.
- **Windows:** the tray installs a new release when nothing is in progress, replaces the files in place and restarts itself. `switchr update` does the same from a terminal. With Scoop, use `scoop update switchr`; the tray tells you when one is out.

## Privacy

There's no analytics and no telemetry. Switchr's network requests are:

- **Limits:** each provider's usage endpoint, called with that account's own token: `api.anthropic.com`, `chatgpt.com` and `cursor.com`.
- **Token refresh:** for accounts that aren't in use, the providers' own sign-in services: `platform.claude.com` and `auth.openai.com`.
- **Cursor usage export:** `cursor.com`, per saved Cursor account.
- **Updates:** `api.github.com` and `github.com`, for release information and downloads.

Everything else stays on your computer:

| | macOS | Linux | Windows |
| --- | --- | --- | --- |
| Saved logins | Login Keychain, service `dev.switchr.vault` | Secret Service (GNOME Keyring or KWallet) through `secret-tool`, or `0600` files in `~/.local/share/switchr/vault` when no keyring runs | Files encrypted with the Data Protection API for your user, in `%LOCALAPPDATA%\Switchr\vault` |
| Accounts and usage history | `~/Library/Application Support/Switchr` | `~/.local/share/switchr` | `%LOCALAPPDATA%\Switchr` |

The account list holds no tokens, and the data folder is readable only by you. `SWITCHR_DATA_DIR` moves it, and `SWITCHR_SECRET_STORE=file` uses private files instead of a keyring.

## Security notes

- On macOS, Keychain calls go through `/usr/bin/security`, so there are no access prompts. Writes pass the credential as an argument, where other processes running as your user can briefly see it. On Linux, logins reach `secret-tool` over stdin instead.
- The dashboard is served on 127.0.0.1 only, by the Mac app for its own window and by `switchr` elsewhere. Its window gets a random session key, every request must carry it, and requests from other websites or host names are refused. The `switchr` server stops 15 minutes after its last window closes.
- On macOS, the Cursor login link travels through Launch Services and never appears in a process list. On Linux and Windows it's passed to Cursor's own executable as an argument, where other processes running as your user can briefly see it.
- Releases aren't notarized or code-signed with a certificate. Every download is listed with its SHA-256 in the release's `SHA256SUMS`. Build from source if you'd rather not run a prebuilt binary.
- The endpoints are the private ones the tools call themselves, so a provider update can break Switchr. If that happens, [open an issue](../../issues/new/choose). Report vulnerabilities privately, as described in [SECURITY.md](SECURITY.md).

## Uninstall

First remove the saved logins, usage history and settings, if you want them gone: `switchr reset` (on macOS, `/Applications/Switchr.app/Contents/MacOS/Switchr reset`). Then:

| System | Remove the app |
| --- | --- |
| macOS | Quit Switchr from the **…** menu and delete `/Applications/Switchr.app`, or `brew uninstall --cask switchr` |
| Fedora, RHEL | `sudo dnf remove switchr` |
| Debian, Ubuntu | `sudo apt remove switchr` |
| Arch Linux | `sudo pacman -R switchr` |
| Portable Linux | Delete `~/.local/bin/switchr`, `~/.local/bin/switchr-tray`, `~/.config/autostart/dev.switchr.Switchr.desktop`, and `dev.switchr.Switchr.*` in `~/.local/share/applications`, `~/.local/share/metainfo` and `~/.local/share/icons/hicolor/*/apps` |
| Windows | `& ([scriptblock]::Create((irm https://raw.githubusercontent.com/dominikzabcik/switchr/main/install.ps1))) -Uninstall`, or `scoop uninstall switchr` |

Your tools stay signed in with whatever account was last in use.

## Development

```bash
swift test                            # unit tests, on macOS, Linux and Windows
./scripts/build-app.sh --install      # macOS: universal app, copied to Applications and opened
./scripts/build-app.sh --release      # macOS: plus Switchr.zip, Switchr.dmg and SHA256SUMS
./scripts/package-linux.sh            # Linux: static binary, tarball, RPM, DEB and Arch package
./scripts/package-windows.ps1         # Windows: switchr.exe, switchr-tray.exe and the runtime in a zip
python3 scripts/render-manifests.py   # Scoop, AUR and winget manifests from a release's SHA256SUMS
python3 scripts/update-pricing.py     # refresh model prices from models.dev
./scripts/render-art.sh               # re-render the icons for every system, the disk image background and the banner
```

The Linux build needs Swift 6.3.3 with the matching [static Linux SDK](https://www.swift.org/documentation/articles/static-linux-getting-started.html) and [nfpm](https://nfpm.goreleaser.com). The Windows build needs the Swift toolchain for Windows. See [CONTRIBUTING.md](CONTRIBUTING.md) for the code layout, the macOS debug flags and conventions.

## Releasing

1. Bump `VERSION`, `AppVersion.number` in `Sources/Switchr/Core/Version.swift`, and add a matching section to `CHANGELOG.md`.
2. Commit, then tag and push: `git tag v$(cat VERSION) && git push origin v$(cat VERSION)`.

The [Release workflow](.github/workflows/release.yml) tests and builds on macOS, Linux (x86_64 and aarch64) and Windows, publishes every download with one `SHA256SUMS` and the AUR PKGBUILD, and commits the Scoop, AUR and winget manifests for the release. Run it by hand first for a dry run that builds everything and publishes nothing.

[CI](.github/workflows/ci.yml) tests every push on all three systems. It installs the Linux packages on Fedora, Ubuntu, Debian and Arch Linux (and on Fedora and Ubuntu for aarch64), builds the PKGBUILD with `makepkg`, runs both installers from the fresh build, uninstalls on Windows, and captures the Linux and Windows trays with sample data.

## Terms and trademarks

Switchr moves between accounts you already have, such as a personal login and a work login. It doesn't give any account more usage than its plan includes. Using several accounts to get around one plan's limits can break a provider's terms, so read the terms for each service you use ([Anthropic](https://www.anthropic.com/legal/consumer-terms), [Cursor](https://cursor.com/terms-of-service), [OpenAI](https://openai.com/policies/row-terms-of-use/)) and use Switchr within them. Only save accounts that are yours: providers such as Anthropic don't allow sharing a login. If you'd rather Switchr make no requests on a timer, turn off **Check usage every 5 minutes** on macOS or **Check usage automatically** in the Linux and Windows trays.

Switchr is an independent project. It isn't affiliated with, endorsed by or sponsored by Anthropic, Anysphere or OpenAI. Claude, Claude Code, Cursor, Codex and OpenAI are trademarks of their owners, and their logos appear only to identify each tool.

## License

[MIT](LICENSE). Provider marks come from [Simple Icons](https://simpleicons.org), model prices from [models.dev](https://models.dev), and Linux and Windows builds include [SQLite](https://sqlite.org), which is in the public domain. See [`NOTICE`](NOTICE).
