# Security

Switchr handles login tokens for Claude Code, Cursor and Codex, so security reports are welcome.

## Reporting

Report vulnerabilities privately through [GitHub's private vulnerability reporting](../../security/advisories/new). Please don't open a public issue for them.

Never include real tokens, Keychain contents or `auth.json` files in a report. If you need to show one, replace the secret values first.

## What Switchr stores

- Saved logins: your login Keychain, service `dev.switchr.vault`, one item per account.
- Account names and labels: `~/Library/Application Support/Switchr/accounts.json`. This file holds no tokens.
- Nothing is sent anywhere except the providers' own usage and token-refresh endpoints, called with each account's own token.

## Known trade-offs

- Keychain writes pass the credential to `/usr/bin/security` as an argument, where other processes running as your user can briefly see it. `security -i` would avoid that, but it splits long input.
- Releases are signed ad hoc, not notarized. Build from source if you'd rather not run a prebuilt binary.
