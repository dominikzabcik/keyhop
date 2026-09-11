# Switchr cloud

Leaderboards, teams and public profiles for Switchr. It runs as one Cloudflare Worker with a D1 database, and serves both the website and the API the app uses.

## What it stores

| Table | Holds |
| --- | --- |
| `users` | GitHub id, login, name and avatar URL, and whether the profile is public (off until the person turns it on) |
| `sessions` | SHA-256 hashes of browser session tokens and linked-app tokens. Never the tokens |
| `device_links` | Codes waiting to be approved, for 10 minutes |
| `daily_usage` | Tokens, API value and requests per day per tool (`claude`, `cursor`, `codex`) |
| `teams`, `team_members`, `team_invites` | Teams, who's in them and invite links, which expire after 7 days |

No prompts, emails, account names, models or GitHub tokens are stored. Deleting an account in Settings removes all of it.

## How the app links

1. Switchr calls `POST /api/device/start` and shows the code it gets back.
2. You open `/link?code=…`, sign in with GitHub, check the code and approve.
3. Switchr polls `POST /api/device/token` and receives its own token, then sends daily totals to `POST /api/usage` about once an hour.

Browser sessions and app tokens are separate: neither works in the other's place. Changes made with a browser session must come from the site's own pages.

## Develop

```bash
cd cloud
npm install
cp .dev.vars.example .dev.vars   # DEV_LOGIN=true lets you sign in at /auth/dev?login=alice
npm run dev                      # applies migrations to a local database, serves http://localhost:8787
node scripts/seed-local.mjs      # made-up people, a year of usage and a team
npm test                         # runs inside the Workers runtime
npm run typecheck
```

Point a local Switchr at it with `SWITCHR_CLOUD_URL=http://localhost:8787 switchr cloud login`. Use `SWITCHR_DATA_DIR` to keep that link away from your real data.

## Deploy

1. Sign in to Cloudflare: `npx wrangler login`.
2. Create the database: `npx wrangler d1 create switchr`, and put the `database_id` it prints into `wrangler.jsonc`.
3. Create a GitHub OAuth app at github.com/settings/developers, with the callback URL `https://<your host>/auth/github/callback`.
4. Store its credentials: `npx wrangler secret put GITHUB_CLIENT_ID`, then `npx wrangler secret put GITHUB_CLIENT_SECRET`.
5. `npm run deploy` applies the migrations and publishes the Worker.
6. Set `Cloud.defaultServer` in `Sources/Switchr/Cloud/Cloud.swift` to the site's address, and release the app. Until then, the app hides leaderboards.

Never set `DEV_LOGIN` in production. The development login also refuses any host other than localhost.
