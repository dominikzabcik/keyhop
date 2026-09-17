# Changelog

## [0.11.0]

- Your phone can tell you when a limit comes back. Turn on **Share limits** in Keyhop's window (or `keyhop cloud limits on`) and your computer sends where each account stands, so the iOS companion can show a live countdown and raise a notification the moment a nearly-spent account resets. It also reminds you on the season's last evening and while today's quests are still open. Every alert is scheduled on the phone itself against a moment already known, so nothing is pushed and no push service is involved. Sharing is off until you turn it on, it carries only how full an account is, when it resets and the name you typed for it, never an email or anything about what you asked, it keeps no history, and turning it off takes the readings off the website straight away.
- OpenCode and Pi join the tools Keyhop switches and the tools it can measure. Keyhop snapshots each tool's complete multi-provider `auth.json`, reads OpenCode's SQLite ledger without writing to it, and reads Pi's local JSONL sessions, including compaction and branch-summary usage. Exact provider-reported costs win over estimates, and copied Pi session branches are deduplicated.
- Codebuff joins account switching and limit checks. Keyhop swaps only its official `default` profile in `~/.config/manicode/credentials.json`, preserves unrelated settings, and reads exact credit, block and weekly counters from Codebuff's own APIs. Codebuff stays out of token totals because its durable local history records credits rather than complete model-token counts.
- GitHub Copilot and Windsurf join the tools Keyhop switches. Copilot moves through the GitHub CLI's own commands, since that is where its login already lives, so Keyhop never edits gh's files and never revokes a token. Windsurf swaps the login in `~/.codeium/config.json` and leaves the rest of that file alone. Neither writes complete local token history Keyhop can count; Keyhop now reads GitHub's reported Copilot quota and the active Windsurf profile's local limit cache, while refusing to attribute that cache to inactive accounts.
- Keyhop saves every GitHub account gh holds, not just the one in use, so a second Copilot account appears without signing out of the first. Adding one waits for an account Keyhop hasn't seen, and if gh isn't installed, Keyhop says so at once instead of waiting ten minutes for a login that can't arrive. `keyhop doctor` and Settings name the reason when a tool is present but can't be used.
- Account names shared with a phone are cleaned on the website and again on the phone: line breaks, escape sequences and bidi overrides are removed, so a label can't fake a notification.
- OpenCode usage is read by when a response finishes, not when it starts, so a long response that ends after a later one began is counted in full instead of being missed or stored half-done.
- Saved logins are written to disk owner-only from the first byte, rather than tightened a moment after the file exists.
- Keyhop identifies itself as Keyhop to GitHub and Codebuff. It no longer presents Copilot requests as coming from an editor, or a Codebuff CLI token as a browser session.
- The website has one header on every page, so signing in, your account and signing out are always in reach, and the home and download pages fit phones properly. The iOS companion shows Keyhop's mark hopping while it reads, moves its numbers and bars when they change, and follows your text size. Keyhop's window gives every tool its mark, gathers tools that aren't set up onto one line, and shows every wait the same way.
- "Every tool" and the "Full house" badge now count the six tools Keyhop can actually measure, so limit-only Copilot, Windsurf and Codebuff accounts do not make either impossible to finish.

## [0.10.0]

- Native Gemini CLI support joins Claude Code, Cursor and Codex across account discovery, switching, local token tracking, budgets, the dashboard, cloud leaderboards and MCP status. Keyhop follows Gemini CLI's own Google sign-in files, reads usage only from local transcripts and leaves API-key and Vertex AI setups untouched.
- The Keyhop website now has a complete product landing page, download guidance, SEO metadata, privacy and terms pages, clearer platform support and an honest roadmap for AI, MCP, mobile and future native integrations.
- The iOS companion reads your leaderboard, season, quests and badges through a revocable read-only link. It builds and runs from source in the simulator while App Store distribution and mobile alerts remain future work.
- Profiles can be edited and shared as cards, and the cloud client now has a dedicated request layer used by both desktop and mobile.
- Budgets use the amount a provider actually charged when an account reports it, rather than always estimating from API prices.

## [0.9.0]

- Smart Hop names the account with the most runway for each tool. It scores every saved account on the room left on its tightest limit (three quarters of the score), how much of its budget is left (one quarter), a bonus when that limit resets within twelve hours, and a penalty when recent use projects an early run-out. `keyhop recommend [--tool <tool>]` prints it with the reason, the menu and the tray point at it, and a limit alert now names an account that still has room instead of only warning you.
- Keyhop speaks MCP, so a coding agent can read its own runway. `keyhop mcp` serves three tools over stdio: `keyhop_status` (saved and active accounts, limits, budgets, alerts and recommendations), `keyhop_usage` (cached token, request and API value history by range and tool) and `keyhop_recommendation` (the best current account). All three are read-only, and none of them can see prompts or source code.
- Quests in Keyhop's window. The Leaderboard section shows today's and this week's goals with their progress, the same six the website counts.
- Your leaderboard token moves out of `cloud.json` into the system secret store, alongside your provider logins.
- Linking a computer is rate limited on the website: ten starts and thirty checks a minute.

## [0.8.0]

- Switchr is now **Keyhop**, at [keyhop.app](https://keyhop.app). The app, the `keyhop` command and the website carry a new mark: a stem, the joint that makes it a K, and two arms, with the upper one hopped clear. In the menu bar those two arms fill as your two nearest limits do. This is a clean break: Keyhop keeps its own data folder and saved logins, so add your accounts once and sign in to the leaderboard again with `keyhop cloud login`.
- Leaderboards at [keyhop.app](https://keyhop.app/leaderboard). Link Keyhop with GitHub (Settings in Keyhop's window, or `keyhop cloud login`) to join a global leaderboard, create teams with invite links, and get a public profile with a year of activity and streaks. Keyhop sends daily totals per tool, about once an hour, and nothing else. The Leaderboard section in Keyhop's window shows your rank and who's just ahead of you.
- `keyhop cloud login`, `status`, `sync`, `open` and `logout`.
- Ranked seasons. Every calendar month is a season, and the tokens you use in it place you on a ladder of six tiers, from Bronze to Master, each with three divisions. The season page shows the standings, what the next division costs and how many days are left, and finished seasons stay readable. Your tier also shows on your profile and in Keyhop's Leaderboard section.
- Backdrops: illustrated scenes behind Keyhop's window and the website. Leaves sway on their stems with a few drifting down, Dunes turns a desert world's horizon under the stars, Orbit floats a ringed planet, Arcade races pixel runners along a ridge of pixel hills, and Picture shows any image you choose. Every motion is GPU-friendly, so they stay smooth, and they hold still with reduced motion. Pick a scene, its opacity and where it shows in **Settings › Appearance**.
- On a Mac, the whole of Keyhop's window is glass: it sits on a blurred view of your desktop, and every panel, tab and button is a light tint over it. **Window opacity** and **Blur** in Settings › Appearance set how much, up to a solid window.
- Overview opens on today's tokens, set large, with a pixel runner hopping along it while a refresh runs. The stat cards gain your streak.

## [0.7.1]

- Keyhop opens as an app on macOS. Launching it from Applications, Launchpad, Spotlight or the Dock opens Keyhop's window: Overview, Accounts, Usage, Budgets and Settings, served by the app itself. It has a Dock icon while the window is open and goes back to the menu bar when it closes. Started at login or relaunched by an automatic update, it stays in the menu bar.
- The menu's footer has **Open Keyhop**, and `keyhop dashboard` on a Mac opens the app's window instead of a browser.
- One design everywhere. The menu, the welcome window, the app icon, the menu bar icon and the Linux and Windows tray icons now use the dashboard's neutral look and its pixel mark. In the menu bar and the trays, the mark's two rows fill as your two nearest limits do.
- The window and the menu share one account list, so a rename or removal in one is never undone by the other.
- The separate Insights window is gone; its charts are in the window's Usage section. `keyhop insights` opens Usage, and `--output` still saves the page as one file.

## [0.7.0]

- Linux and Windows. Keyhop now runs on every major desktop:
  - **Linux:** a tray menu with the same accounts, limits, switching, alerts and updates as the Mac app. It ships as an RPM for Fedora, a DEB for Debian and Ubuntu, and a package for Arch Linux. A portable build installs into `~/.local` on any other distribution, on x86_64 and aarch64.
  - **Windows 10 and 11:** a notification-area app with the same menu, toasts with a Switch button, and Open at sign-in. It installs per user with one PowerShell line, or through Scoop.
- The `keyhop` command, on all three systems: `status`, `refresh`, `switch`, `add`, `rename`, `remove`, `usage`, `dashboard`, `insights`, `budget`, `update`, `doctor` and `reset`, each with `--json` output. On macOS the app binary answers the same commands.
- The Keyhop dashboard, a clean app window with Overview, Accounts, Usage, Budgets and Settings: switch, add, rename and remove accounts, usage charts, a 26-week activity grid with streaks, token mix, models, budgets with their monthly pace, update checks and the tools Keyhop found. `keyhop dashboard` serves it on 127.0.0.1 only, behind a random session key. The Windows tray opens it on a click and the Linux tray from its menu. `keyhop insights --output` saves it as one file.
- Saved logins stay in each system's own secret store:
  - **macOS:** the login Keychain.
  - **Linux:** the Secret Service (GNOME Keyring or KWallet), or private files when no keyring runs.
  - **Windows:** Data Protection API encryption for your user.
- `keyhop update` installs a verified release. On Linux it installs through your package manager, or into `~/.local` for the portable build. On Windows it replaces the files in place.
- The Linux and Windows trays rename and remove accounts, set a monthly budget, and have switches for automatic usage checks, automatic updates and opening at sign-in. They tell you once when a new version is out.
- Arch Linux users can build the `keyhop-bin` PKGBUILD, and each release carries winget manifests. Windows on Arm runs the x86_64 build.
- The one-line installer detects Linux and installs the matching package. On macOS it links the `keyhop` command onto your PATH, as the new Homebrew cask does.
- `keyhop status --sample` and `keyhop dashboard --sample` show made-up accounts, for trying Keyhop out and for screenshots.
- The switching rules are shared by every platform and covered by new tests, as are alerts, the command line, secret storage and the dashboard's server and access checks.

## [0.6.1]

- Checking for updates is now a visible button in the menu footer: it shows the version you have and checks right away. It's still in the "…" menu too.

## [0.6.0]

- Automatic updates. Keyhop checks GitHub once a day and installs a new release in place, only after the download matches the release checksum and never during a switch. With automatic installs off, the menu shows an Update button.
- Settings in the menu's "…": automatic usage checks, update checks, automatic installs and Open at login.
- `Keyhop --reset` removes every saved login, the usage database and preferences.
- VoiceOver labels for tabs, limits and account rows.
- The menu opens on a tool you use, even before your first switch.
- Limit forecast alerts wait until a limit is at least half used, so early estimates don't cry wolf.
- Dollar amounts use US formatting in every locale.
- The usage folder and database are readable only by you.
- Unit tests for pricing, log parsing, attribution, forecasts, budgets, Cursor's export and the updater. CI and releases run them.

## [0.5.0]

- Redesigned menu on the Keyhop enamel. Tabs switch between Claude Code, Cursor and Codex, each with a live twin-track glyph.
- The account in use leads with large limit figures, bars drawn like the icon, and a "Runs out" time when a limit won't last.
- Other accounts are one-click rows that show the room left, marking the one with the most when you're running low.
- Adding an account plays the icon's hand-off animation while Keyhop waits for the new login.
- A quieter footer, with Open at login and Quit moved into its menu.
- The Insights window uses the same enamel surface.

## [0.4.0]

- Usage tracking. Keyhop reads Claude Code and Codex logs on your Mac and each Cursor account's usage export, prices every request at standard API rates, and credits it to the account that was in use at the time.
- Insights window with usage by account over time, models, budgets and current limits.
- Budgets per account or across all accounts, with notifications at 80% and 100%.
- Limit forecasts: each meter shows when the limit runs out at the recent rate. When the account in use is close to its limit, a notification offers a one-click switch to the saved account with the most room.
- Each account row shows today's tokens and spend.

## [0.3.0]

- App icon: two usage tracks handing off, on green-black enamel.
- Welcome window on first launch. It shows the logins it found, turns on Open at login, and moves Keyhop into Applications when you run it from a download or disk image.
- One-line installer with checksum verification. It needs no Gatekeeper approval.
- Disk image with a drag-to-Applications layout.
- Releases are built by GitHub Actions from version tags.

## [0.2.0]

- Cursor switches accounts in place through its own login deep link, without restarting.
- Universal build for Apple silicon and Intel.

## [0.1.0]

- Menu bar switcher for Claude Code, Cursor and Codex, with live usage limits for every saved account.
