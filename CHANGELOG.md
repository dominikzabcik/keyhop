# Changelog

## [0.7.0]

- Linux and Windows. Switchr now runs on every major desktop:
  - **Linux:** a tray menu with the same accounts, limits, switching, alerts and updates as the Mac app. It ships as an RPM for Fedora, a DEB for Debian and Ubuntu, and a package for Arch Linux. A portable build installs into `~/.local` on any other distribution, on x86_64 and aarch64.
  - **Windows 10 and 11:** a notification-area app with the same menu, toasts with a Switch button, and Open at sign-in. It installs per user with one PowerShell line, or through Scoop.
- The `switchr` command, on all three systems: `status`, `refresh`, `switch`, `add`, `rename`, `remove`, `usage`, `insights`, `budget`, `update`, `doctor` and `reset`, each with `--json` output. On macOS the app binary answers the same commands.
- `switchr insights` writes a self-contained Insights page and opens it in your browser: usage by account over time, API value, models, current limits and budgets, for today, 7 days, this month or 30 days.
- Saved logins stay in each system's own secret store:
  - **macOS:** the login Keychain.
  - **Linux:** the Secret Service (GNOME Keyring or KWallet), or private files when no keyring runs.
  - **Windows:** Data Protection API encryption for your user.
- `switchr update` installs a verified release. On Linux it installs through your package manager, or into `~/.local` for the portable build. On Windows it replaces the files in place.
- The Linux and Windows trays rename and remove accounts, set a monthly budget, and have switches for automatic usage checks, automatic updates and opening at sign-in. They tell you once when a new version is out.
- Arch Linux users can build the `switchr-bin` PKGBUILD, and each release carries winget manifests. Windows on Arm runs the x86_64 build.
- The one-line installer detects Linux and installs the matching package. On macOS it links the `switchr` command onto your PATH, as the new Homebrew cask does.
- `switchr status --sample` and `switchr insights --sample` show made-up accounts, for trying Switchr out and for screenshots.
- The switching rules are shared by every platform and covered by new tests, as are alerts, the command line, secret storage and the Insights page.

## [0.6.1]

- Checking for updates is now a visible button in the menu footer: it shows the version you have and checks right away. It's still in the "…" menu too.

## [0.6.0]

- Automatic updates. Switchr checks GitHub once a day and installs a new release in place, only after the download matches the release checksum and never during a switch. With automatic installs off, the menu shows an Update button.
- Settings in the menu's "…": automatic usage checks, update checks, automatic installs and Open at login.
- `Switchr --reset` removes every saved login, the usage database and preferences.
- VoiceOver labels for tabs, limits and account rows.
- The menu opens on a tool you use, even before your first switch.
- Limit forecast alerts wait until a limit is at least half used, so early estimates don't cry wolf.
- Dollar amounts use US formatting in every locale.
- The usage folder and database are readable only by you.
- Unit tests for pricing, log parsing, attribution, forecasts, budgets, Cursor's export and the updater. CI and releases run them.

## [0.5.0]

- Redesigned menu on the Switchr enamel. Tabs switch between Claude Code, Cursor and Codex, each with a live twin-track glyph.
- The account in use leads with large limit figures, bars drawn like the icon, and a "Runs out" time when a limit won't last.
- Other accounts are one-click rows that show the room left, marking the one with the most when you're running low.
- Adding an account plays the icon's hand-off animation while Switchr waits for the new login.
- A quieter footer, with Open at login and Quit moved into its menu.
- The Insights window uses the same enamel surface.

## [0.4.0]

- Usage tracking. Switchr reads Claude Code and Codex logs on your Mac and each Cursor account's usage export, prices every request at standard API rates, and credits it to the account that was in use at the time.
- Insights window with usage by account over time, models, budgets and current limits.
- Budgets per account or across all accounts, with notifications at 80% and 100%.
- Limit forecasts: each meter shows when the limit runs out at the recent rate. When the account in use is close to its limit, a notification offers a one-click switch to the saved account with the most room.
- Each account row shows today's tokens and spend.

## [0.3.0]

- App icon: two usage tracks handing off, on green-black enamel.
- Welcome window on first launch. It shows the logins it found, turns on Open at login, and moves Switchr into Applications when you run it from a download or disk image.
- One-line installer with checksum verification. It needs no Gatekeeper approval.
- Disk image with a drag-to-Applications layout.
- Releases are built by GitHub Actions from version tags.

## [0.2.0]

- Cursor switches accounts in place through its own login deep link, without restarting.
- Universal build for Apple silicon and Intel.

## [0.1.0]

- Menu bar switcher for Claude Code, Cursor and Codex, with live usage limits for every saved account.
