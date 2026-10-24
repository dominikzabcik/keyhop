# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

(The Mac app window renders an HTML page served over loopback; keyhop.app shares the language. The iOS app and the menu-bar item are separate surfaces styled after the window, not the other way round.)

## Users

Developers who pay for several AI coding tools at once (Claude Code, Codex, Cursor, Copilot, Gemini CLI, OpenCode, …) and run them daily. Situation: mid-work, a tool's subscription limit is about to run out. Job: keep working without interruption, know what each login has left, and know what today's work cost in tokens.

## Product Purpose

Keyhop watches every tool's limits and token usage locally, and hops the active login to another account before a limit stops the work. Success for the owner: linked users and active teams. The product is public and free forever; no monetization is planned.

## Positioning

The only tool that combines the four camps of the market (CLI usage analyzers, menu-bar limit meters, account switchers, leaderboards) in one product. The switcher is the part competitors cannot truthfully copy: Keyhop performs the hop, not just the measurement.

## Operating Context

Runs as a Mac menu-bar app with a window, plus the `keyhop` CLI and keyhop.app (Cloudflare Workers + D1). Reads tools' local JSONL/SQLite transcripts (13 token sources) and credential stores; hops rewrite login files. Real-time via FSEvents. Multi-machine merge over a synced folder. Cloud sync is aggregates-only by confirmed decision (ADR-0003).

## Capabilities and Constraints

- Tools split into switchable (adapters, hops) and measured-only (usage history only).
- Terminology is binding per CONTEXT.md: Tool, Login (never "account" in UI), Hop, Window, Runway, Keep, Live layer.
- Mac app and keyhop.app stay in capability parity (AGENTS.md rule).
- **Confirmed scope decision (2026-10-24): the window cuts to the core — limits + hop + usage.** Coach, Plans, Budgets, Leaderboard, Season, Teams, Profile leave the window or hide behind quiet links; they return only if the user asks.
- Gamification, when surfaced at all, ranks efficiency, not token volume (ADR-0002).

## Brand Commitments

- Name: Keyhop. Existing mark: "K" glyph; no other binding visual assets survive.
- **The owner rejected the incumbent look (Coss Blue dark-SaaS dashboard) and all four 2026-10-24 prototype directions as generic. The replacement world must read unique, not like an AI-generated dashboard.**
- Binding taste references volunteered by the owner: opencode.ai / TUI aesthetics, and Linear / Raycast product minimalism. Inspiration, not a clone.
- Voice: plain, short, tool-like. The UI answers "can I keep working?" before it shows anything else.

## Evidence on Hand

- Real data shapes: logins with percent left and reset times, per-tool/per-model token totals and API-price values, call counts, cache-hit rates, commits per tokens. Sample truthful figures live in `design/keyhop-v2/canvas/` shots.
- Competitor research (2026-10): ccusage, codeburn, CodexBar, claude-swap, tokscale/viberank; "tokenmaxxing" backlash motivates efficiency framing.
- No testimonials, no press; do not fabricate any.

## Product Principles

1. Answer first: the surface states whether work can continue before any metric.
2. The hop is the hero interaction; everything else supports it.
3. Fewer things, finished: a capability absent from the window beats one half-shown.
4. Numbers the user can trust: show what tools report, never guessed figures presented as fact.
5. Local-first and private: live detail stays on the machine; the cloud sees aggregates.
