# Changelog

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
