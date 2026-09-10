# Security

Switchr handles login tokens for Claude Code, Cursor and Codex, so security reports are welcome.

## Reporting

Report vulnerabilities privately through [GitHub's private vulnerability reporting](../../security/advisories/new). Please don't open a public issue for them.

Never include real tokens, Keychain or keyring contents, `.credentials.json` or `auth.json` files in a report. If you need to show one, replace the secret values first.

## What Switchr stores

- **Saved logins:**
  - **macOS:** your login Keychain, service `dev.switchr.vault`, one item per account.
  - **Linux:** the Secret Service (GNOME Keyring or KWallet), or `0600` files in a `0700` folder when no keyring runs.
  - **Windows:** files encrypted with the Data Protection API for your user.
- **Account names and labels:** `accounts.json` in Switchr's data folder. This file holds no tokens.
- Nothing is sent anywhere except the providers' own usage and token-refresh endpoints, called with each account's own token, and GitHub for updates.

## Known trade-offs

- On macOS, Keychain writes pass the credential to `/usr/bin/security` as an argument, where other processes running as your user can briefly see it. `security -i` would avoid that, but it splits long input.
- On Linux and Windows, handing a login to a running Cursor passes its tokens to Cursor's executable as an argument, with the same brief visibility.
- On Linux without a keyring, and for the files Claude Code itself keeps on Linux and Windows, protection comes from file permissions and your user account rather than encryption.
- Releases aren't notarized or signed with a certificate. Every download has a SHA-256 in the release's `SHA256SUMS`, and every updater checks it. Build from source if you'd rather not run a prebuilt binary.
