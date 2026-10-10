## Learned User Preferences

- Keep the Mac app and keyhop.app in parity: a capability on one surface belongs on the other, and every capability the product already has should be usable in the UI.

## Learned Workspace Facts

- Keyhop V2 (big-bang 2.0) is being built on the long-lived `v2` branch per the approved plan in `~/.claude/plans/pasted-content-id-7e83-cht-l-bych-prancy-floyd.md`: ~12 weeks, milestones M1 tracker core → M2 UI per `design/keyhop-v2/index.html` → M3 social + live cloud → M4 optimizer/coaching/growth → M5 parity + docs + launch. Cloud changes stay on `main` (backwards compatible, deployed continuously). Key decisions are recorded in `docs/adr/0001`–`0003` and the glossary in `CONTEXT.md`.

- This checkout is Keyhop (`github.com/dominikzabcik/keyhop`): a Swift macOS app (target `Keyhop`), the `keyhop` CLI, and the cloud site at keyhop.app. The directory is named switchr.
- Team day is `/t/<team>/day` (older days use `/day/YYYY-MM-DD`). Machines opt in with `keyhop work add`, `keyhop work on`, and `keyhop work subjects on`. Only commits the person authored count, merge commits are excluded, and each day is rewritten on sync so rebases are not counted twice. Task titles come from commit subjects. The Mac window shows the same day under Teams. The leaderboard ranks token spend.
- Usage in the window, CLI, JSON, and MCP groups by account, tool, and model. Token totals cover Claude Code, Cursor, Codex, Gemini CLI, OpenCode, and Pi. Copilot, Windsurf, and Codebuff expose limits only, because they do not leave a complete model-token transcript.
- Jev is the Typesafe screen review in CI. Its judgements are reported and do not fail the build.
- A linked account has one lifetime pet, computed from synced daily totals and not stored. Stages are Speck, Hatch (1M tokens), Frame (50M), Bulk (500M), Mass (5B), and Monument (25B). The dominant measured tool sets the markings, the streak sets the pose, and commits set the build. A public profile shares it at `/u/<login>/pet.svg`. The same shapes are painted on the profile, the team page, Overview, the Mac menu, and the iOS season screen. The status icon still shows limits.
