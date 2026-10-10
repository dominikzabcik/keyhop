# Keyhop

Keyhop tracks how much the AI coding tools on a machine are used, moves tools between saved logins before limits bite, and turns the measured work into a social layer (teams, seasons, a pet) at keyhop.app.

## Language

### Tools and logins

**Tool**:
One AI coding product Keyhop knows about (Claude Code, Cursor, Codex, Gemini CLI, OpenCode, Pi, Copilot, Windsurf, Codebuff, …).
_Avoid_: provider, agent, app

**Measured tool**:
A tool whose token usage Keyhop can read from local history. Only measured tools count toward totals, leaderboards and the pet.
_Avoid_: tracked tool

**Limits-only tool**:
A tool that exposes how full its windows are but leaves no complete token transcript. It shows limits but adds nothing to totals.

**Login**:
One saved sign-in for a tool that Keyhop can restore later. A tool uses exactly one login at a time.
_Avoid_: account, profile, credential

**Hop**:
Moving a tool from its current login to another saved one. Smart Hop is the recommended hop: the login with the most runway.
_Avoid_: switch, rotate

**Window**:
One rate-limit bucket of a login (5-hour, week, Opus, …) with a fill percentage and a reset time.
_Avoid_: quota, pool

**Runway**:
The forecast of when a window runs out at the current pace.

### Usage

**API value**:
What the measured usage would have cost at list API prices. An estimate, never the actual bill.
_Avoid_: cost, spend, price

**Work**:
Opt-in counting of the person's own git commits (merge commits excluded). Subjects are the opt-in sharing of commit subject lines.

**Task**:
A group of a day's commits that belong together, derived from their subjects by heuristic.

**Efficiency**:
Outcome per spend — the metric family (tokens per merged unit of work, cache-hit, streak) that ranks V2 seasons and leaderboards by default, in place of raw token volume.

### Cloud and social

**Link**:
The approval that ties a machine or phone to a keyhop.app user. A read link can see; only a write link can upload.
_Avoid_: pairing, connect

**Live layer**:
Short-interval usage aggregates that power live views (team day, leaderboard). Transient by definition: only daily totals are ever stored durably.

**Season**:
One UTC calendar month of ranked play, with tiers Bronze through Master.

**Division**:
The plan-based group a person competes in within a season, so peers on the same plan are ranked against each other.
_Avoid_: league

**Streak**:
Consecutive days with measured activity.

**Keep**:
A claimed streak day. Claiming is deliberate; the streak alone is not a keep.

**Team day**:
A team's per-day report: who worked, their tasks, repos and tokens. Each day is rewritten on sync so rebases are not counted twice.

**Pet**:
The one lifetime creature per linked person, computed from synced daily totals and never stored. Stages by lifetime tokens: Speck, Hatch (1M), Frame (50M), Bulk (500M), Mass (5B), Monument (25B). Tool mix sets the markings, streak the pose, commits the build.
_Avoid_: companion, buddy, mascot
