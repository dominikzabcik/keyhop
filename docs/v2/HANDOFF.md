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
  TOOLS/LIMIT_TOOLS split). It is in this branch's history too. **Deployment to keyhop.app has
  NOT happened**: a push of main starts CI and a production deploy that waits for the owner's
  approval, and a stale waiting run blocks later ones.

Verification that passed before the handoff: `swift test` (211), `cd cloud && npm test` (86)
plus typecheck, and a live two-machine `keyhop merge` smoke test via `KEYHOP_DATA_DIR`.

## Everything travels in this branch

`design/keyhop-v2/index.html` (the **binding** M2 design direction), `AGENTS.md`,
`reports/` + `research_notes/` (the gap analysis M1 was built from), `docs/v2/PLAN.md` and this
file are all committed here. The owner's previously uncommitted pet/dashboard work is the
"WIP:" commit; nothing of the old machine's working tree is left behind.

## Open threads, in order

1. **Client upload filter:** `CloudSync.cloudAcceptedTools` in
   `Sources/Keyhop/Cloud/Cloud.swift` keeps the new tools out of uploads until migration 0013
   is deployed. Lift it (and decide how new tools join the server's MEASURED_TOOLS, pet and
   quests) only after the deploy is confirmed.
2. **Pre-flight before M3:** confirm the Cloudflare account is on a paid plan — D1 hard-fails
   on Workers Free since 2026-09-01, and the live layer adds query volume.
3. **M2** (UI per `design/keyhop-v2/index.html`): finish or land the WIP commit's direction
   first — it touches the same files M2 rewrites (DashboardPage.swift above all).
4. **Deferred from M1:** `keyhop run <account>` + directory→account mapping (own design block:
   per-account credential materialisation via CLAUDE_CONFIG_DIR/CODEX_HOME); feeds skipped on
   evidence grounds (Antigravity protobuf, Droid/Hermes session totals, Copilot shutdown
   rollups — verify Copilot's `session-store.db` `assistant_usage_events` on a real install);
   Codex `account/rateLimits/read` app-server surface; Claude's usage credits and Agent SDK
   pool lack vendor schemas.
5. **M3–M5** per `docs/v2/PLAN.md`: efficiency + divisions + anti-cheat + transient live layer
   (aggregates only, `show-data`), then optimizer/coaching/growth, then tray/iOS/CLI parity,
   docs, GitHub Discussions, launch.

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
