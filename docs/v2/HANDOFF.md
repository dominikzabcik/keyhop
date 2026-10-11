# Keyhop V2 — handoff (2026-10-10)

Work continues on another machine from this branch. A fresh agent should read this, then
`docs/v2/PLAN.md` (the approved M1–M5 plan with M1 status), `CONTEXT.md`, `docs/adr/0001`–`0003`
and `AGENTS.md`, before touching anything.

## Where things stand

The V2 program (big-bang 2.0 on this long-lived `v2` branch, ~12 weeks) was planned, approved
and started on 2026-10-10. **M1 (tracker core) is essentially done**; M2 (UI rebuild) is next.

- `v2` (this branch, rebased onto main): decisions/glossary → FSEvents LogWatch →
  credential-override detection → multi-machine merge folder → seven new measured-only tools
  (13 token sources) → opt-in auto-hop before a limit → the owner's WIP pet/dashboard commit.
- `main` carries cloud migration 0013 (`042b2ab`, widens daily_usage's tool CHECK,
  TOOLS/LIMIT_TOOLS split) and, since 2026-10-10 16:29 UTC, `4158a86`: MEASURED_TOOLS is all
  thirteen tools (pet lineage with a colour and name per tool, quest "Four tools" replaces
  "Every tool", Full house badge = five tools in one day, tool rows padded to six). Both are in
  this branch's history. **Deployment to keyhop.app has NOT happened** (checked 2026-10-10
  16:22 UTC: the deploy run for `042b2ab` was still `waiting` for the owner's approval): a push
  of main starts CI and a production deploy that waits for approval, and a stale waiting run
  blocks later ones. Approving the newest run deploys both commits.

Verification that passed before the handoff: `swift test` (211), `cd cloud && npm test` (86)
plus typecheck, and a live two-machine `keyhop merge` smoke test via `KEYHOP_DATA_DIR`.
On the Linux box the whole suite runs too (Swift 6.3.3 toolchain, Playwright Chromium): as of
2026-10-11, `swift test` 209, window + CLI e2e 30, cloud 98, site e2e 32, app and CLI checks 16 screens clean.

## Everything travels in this branch

`design/keyhop-v2/index.html` (the **binding** M2 design direction), `AGENTS.md`,
`reports/` + `research_notes/` (the gap analysis M1 was built from), `docs/v2/PLAN.md` and this
file are all committed here. The owner's previously uncommitted pet/dashboard work is the
"WIP:" commit; nothing of the old machine's working tree is left behind.

## Open threads, in order

1. **Client upload filter:** `CloudSync.cloudAcceptedTools` in
   `Sources/Keyhop/Cloud/Cloud.swift` keeps the new tools out of uploads until migration 0013
   is deployed. Lift it only after the deploy is confirmed (a successful "Deploy cloud" run for
   `4158a86` or later on main). The server side is done: `4158a86` on main.
2. **Pre-flight before M3:** confirm the Cloudflare account is on a paid plan — D1 hard-fails
   on Workers Free since 2026-09-01, and the live layer adds query volume.
3. **M2** (UI per `design/keyhop-v2/index.html`) — in progress, on `v2` since 2026-10-10:
   - Landed: the WIP's home shell (252 px sidebar, Limits board, account tree, status bar,
     home composer, night field) with its dead code removed; the pet's commit blocks moved in
     front of the creature (`cloud/scripts/pet-sample.mjs` regenerates `CloudPet.sample`);
     a **day field** (`theme` in the appearance: night/day/auto, status-bar switch, Settings →
     Appearance → Field; every overlay tint reads `--on`, see `Dashboard/Page/DashboardStyles.swift`);
     the leaderboard mix bar covers all thirteen measured tools; the page split into
     `Sources/Keyhop/Dashboard/Page/` (styles, shell, one script per section).
   - keyhop.app got the same day field on `main` (system setting plus a header switch kept in
     localStorage; the night scenes mount at a quarter strength by day).
   - Still open in M2: the Mac menu bar (numbers in the menu-bar text, outage badge, live
     ticker) and the WKWebView chrome following a live theme switch — both need a Mac to build
     and verify (`AppWindow.swift` only reads the saved theme at launch); a Rams/design review
     of each screen (no review skill was available here); the sketch's "Day" section (this
     computer's commits today) is not in the window — the team day lives under Teams.
   - How to verify here: `swift build && swift test`, `npm run test:e2e` (window + CLI),
     `cd checks && node run.mjs --app`, and `.shots/shot-app.mjs night|day` (untracked helper)
     for screenshots of every section.
4. **Deferred from M1:** `keyhop run <account>` + directory→account mapping (own design block:
   per-account credential materialisation via CLAUDE_CONFIG_DIR/CODEX_HOME); feeds skipped on
   evidence grounds (Antigravity protobuf, Droid/Hermes session totals, Copilot shutdown
   rollups — verify Copilot's `session-store.db` `assistant_usage_events` on a real install);
   Codex `account/rateLimits/read` app-server surface; Claude's usage credits and Agent SDK
   pool lack vendor schemas.
5. **M3** (social layer + live cloud) — built 2026-10-10 evening:
   - `main` (`da30a59`, `d66f312`): migration 0014 (`cache_read`, `users.division`,
     `live_usage`), efficiency = commits per million tokens as the default metric, cache hit,
     plan divisions (free/pro/max) with a division filter and a person's season place inside
     their division, upload verification (requests fit tokens, list-price band, cache reads fit
     tokens), `POST`/`DELETE /api/live` with a TTL sweep, live team day. 93 cloud tests, site e2e 32.
   - `v2`: `cacheRead` and `division` ride the daily upload; opt-in live sharing
     (`keyhop cloud live on|off`, Settings → Cloud → Live, every 90 s after a refresh);
     `keyhop cloud show-data` and Settings → Cloud → "What this computer sends" print the exact
     payloads; the window's leaderboard has Efficiency/Cache hit metrics and a division picker;
     the team day shows a live dot; the season shows the division.
   - Still open: iOS season screen could name the division (needs a Mac); the live leaderboard
     "right now" view (the live rows feed only the team day today); divisions are reported by the
     app from plan names (`CloudSync.division`), so a login whose plan Keyhop can't read ranks
     among everyone.
6. **M4** (optimizer, coaching, growth) — built 2026-10-11:
   - `v2`: **Plans** (`keyhop plans`, window section after Budgets): each login's plan priced at
     list (`Core/PlanPrices.swift`, October 2026 prices) against the month's API value and the
     week's window peaks from the limit samples, with a standing and advice. **Coach**
     (`keyhop coach [optimize|compare|yield]`, window section after Plans): cache hit and
     premium-model share per tool with findings, this month against last per tool and model
     (the digest now carries `previousByProvider`/`previousByModel`), tokens and API value per
     commit and per merge from the counted repositories (`GitWork.merges`).
   - `main`: team **digests** to Slack/Discord (migration 0015 `digest_url`/`digest_hour`, team
     page form, `POST /api/teams/:slug/digest`, posted by the hourly cron at the chosen UTC
     hour, only to hooks.slack.com/discord.com webhooks, the saved URL never shown back);
     **Wrapped** (`/u/:login/wrapped[/:year]`, linked from the profile); widgets gain
     `efficiency` and `cache` metrics.
   - Still open: a share card for the pet/season beyond the existing `card.svg`/`pet.svg`;
     the window's Teams section has no digest form yet (website only); Coach's premium
     threshold is $15/M output and the cache finding needs 1M context tokens, both in
     `Core/Coach.swift`.
7. **M5** (parity, support, launch) — built 2026-10-11, as far as this Linux box allows:
   - Done: MCP `keyhop_plans` and `keyhop_coach`; Settings → App & Privacy → Help card (docs,
     Discussions, issues, doctor); keyhop.app `/docs` guide and footer links; landing copy for
     2.0; `docs/ROADMAP.md` (both branches); issue chooser points to Discussions and the
     roadmap; README rewritten for 2.0; CHANGELOG `2.0.0 — unreleased`; the tray says
     "Hopping".
   - Needs a Mac or the owner: the iOS redesign (no build here); the Mac menu bar work from
     M2; enabling GitHub Discussions in the repository settings; the 2.0 release itself
     (screenshots from `checks/report/screens`, the landing's download links); approving the
     pending "Deploy cloud" runs on main (migrations 0013, 0014, 0015 are all unapplied in
     production until then), and only after that lifting `CloudSync.cloudAcceptedTools`.
   - Deferred, in the roadmap: `keyhop run <account>` with a folder-to-account mapping (needs
     per-login config folders, log ingest from them and Keychain checks on a Mac); the Linux
     and Windows tray in the 2.0 visual language (its menus are native; the window it opens
     is the same 2.0 page).

## Working agreements to respect

- Cloud/D1 changes land on `main`, backwards compatible, deployed continuously (ADR-0001); the
  app big-bang stays on `v2`, rebased onto main regularly.
- Production deploys wait for the owner's explicit approval.
- Seasons/leaderboards pivot to efficiency with verification (ADR-0002); the live layer sends
  aggregates only (ADR-0003).
- Commits end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

## Suggested skills for the next agent

Call the Skill tool for these when the matching work starts (availability may differ per host):
- `deslop` — after each feature lands (the owner runs it as a habit).
- `impeccable` or `frontend-design` + `web-design-guidelines` — M2, building to the sketch.
- `wrangler` — deploying migration 0013 and the M3 live layer.
- `code-review` — before merging milestones; `pr` — for the eventual 2.0 PR.
- `resolving-merge-conflicts` — rebases of `v2` onto main.
