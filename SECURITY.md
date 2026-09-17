# Security

Keyhop handles login tokens for supported AI coding tools, so security reports are welcome.

## Reporting

Report vulnerabilities privately through [GitHub's private vulnerability reporting](../../security/advisories/new). Please don't open a public issue for them.

Never include real tokens, Keychain or keyring contents, `.credentials.json` or `auth.json` files in a report. If you need to show one, replace the secret values first.

## What Keyhop stores

- **Saved logins:**
  - **macOS:** your login Keychain, service `app.keyhop.vault`, one item per account.
  - **Linux:** the Secret Service (GNOME Keyring or KWallet), or `0600` files in a `0700` folder when no keyring runs.
  - **Windows:** files encrypted with the Data Protection API for your user.
- **Account names and labels:** `accounts.json` in Keyhop's data folder. This file holds no tokens.
- Nothing is sent anywhere except the providers' own usage and token-refresh endpoints, called with each account's own token, GitHub for updates, and, only once you link a computer, Keyhop cloud for daily totals.
- **Keyhop cloud link:** `cloud.json` in Keyhop's data folder holds non-secret link metadata. Its app token is stored separately through the protected secret store, under service `app.keyhop.cloud`.

## The dashboard

`keyhop dashboard` serves Keyhop's window on 127.0.0.1, never on a network interface. The address it opens carries a random 256-bit session key. Every API request must send that key, with a loopback Host header (so a website can't reach it through DNS rebinding), and changes must be JSON requests from the same origin. The server stops 15 minutes after its last window closes. The key is visible to your own user in that window's address and, while the window opens, in a process list.

## Keyhop cloud

Leaderboards are opt-in. A device sends or reads nothing until you link it by approving a short code in the browser after signing in with GitHub.

- **Sent by a linked desktop:** tokens, API value and requests per tool per day. Never prompts, emails, account names, models or provider tokens. The iOS companion receives read-only profile, season, quest and standings data instead.
- **Stored by the service:** your GitHub id, login, name and avatar URL, those daily totals, and team memberships. Session and app tokens are kept only as SHA-256 hashes, and GitHub's own token is discarded after reading your public profile.
- **Stored by the iOS companion:** its separate read-only app token in Keychain, restricted to that device, plus your public Keyhop profile name and server in UserDefaults. Unlinking revokes the server session before removing both local records.
- **Visibility:** profiles are private until you make them public. Team members see each other's totals.
- **Removal:** `keyhop cloud logout` unlinks a computer. Deleting your account on the website removes everything it holds.
- **Integrity:** totals are reported by your own Keyhop, so a leaderboard is only as honest as its members. The service rejects impossible dates and implausible values.

## Known trade-offs

- On macOS, Keychain writes pass the credential to `/usr/bin/security` as an argument, where other processes running as your user can briefly see it. `security -i` would avoid that, but it splits long input.
- On Linux and Windows, handing a login to a running Cursor passes its tokens to Cursor's executable as an argument, with the same brief visibility.
- On Linux without a keyring, and for the files Claude Code itself keeps on Linux and Windows, protection comes from file permissions and your user account rather than encryption.
- Releases through v0.9.0 aren't notarized or certificate-signed. Publishing signs and notarizes when the required Apple and Windows credentials are configured. Every download also has a SHA-256 in `SHA256SUMS`, which every updater checks.
