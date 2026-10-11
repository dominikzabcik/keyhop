import { type Tool, TOOLS, TOOL_NAMES, today } from "./env";
import { streaks } from "./stats";
import { tierFor, tierLabel } from "./seasons";

/**
 * A year, wrapped: what one person used and shipped across it, from the daily totals. Counted on
 * request, never stored, like everything else on a profile.
 */
export interface Wrapped {
  year: number;
  /** Whether the year is still running; a running year is wrapped up to today. */
  running: boolean;
  from: string;
  until: string;
  tokens: number;
  costMicros: number;
  requests: number;
  activeDays: number;
  longestStreak: number;
  commits: number;
  insertions: number;
  deletions: number;
  repos: number;
  tools: Record<Tool, number>;
  topTool: { tool: Tool; name: string; share: number } | null;
  biggestDay: { day: string; tokens: number } | null;
  /** The best month's tokens, and the tier it would have been. */
  bestMonth: { month: string; tokens: number; tier: string } | null;
}

export function yearBounds(year: number, reference = today()): { from: string; until: string; running: boolean } {
  const from = `${year}-01-01`;
  const end = `${year}-12-31`;
  return { from, until: end < reference ? end : reference, running: end >= reference };
}

export async function wrapped(db: D1Database, userId: string, year: number, reference = today()): Promise<Wrapped> {
  const { from, until, running } = yearBounds(year, reference);
  const [days, tools, work, months, workDays] = await Promise.all([
    db
      .prepare("SELECT day, SUM(tokens) AS tokens FROM daily_usage WHERE user_id = ? AND day >= ? AND day <= ? GROUP BY day")
      .bind(userId, from, until)
      .all<{ day: string; tokens: number }>(),
    db
      .prepare(
        "SELECT tool, SUM(tokens) AS tokens, SUM(cost_micros) AS cost_micros, SUM(requests) AS requests FROM daily_usage WHERE user_id = ? AND day >= ? AND day <= ? GROUP BY tool",
      )
      .bind(userId, from, until)
      .all<{ tool: Tool; tokens: number; cost_micros: number; requests: number }>(),
    db
      .prepare(
        `SELECT COALESCE(SUM(commits), 0) AS commits, COALESCE(SUM(insertions), 0) AS insertions, COALESCE(SUM(deletions), 0) AS deletions,
           COUNT(DISTINCT CASE WHEN commits > 0 THEN repo END) AS repos, COUNT(DISTINCT CASE WHEN commits > 0 THEN day END) AS days
         FROM daily_work WHERE user_id = ? AND day >= ? AND day <= ?`,
      )
      .bind(userId, from, until)
      .first<{ commits: number; insertions: number; deletions: number; repos: number; days: number }>(),
    db
      .prepare("SELECT substr(day, 1, 7) AS month, SUM(tokens) AS tokens FROM daily_usage WHERE user_id = ? AND day >= ? AND day <= ? GROUP BY 1 ORDER BY 2 DESC LIMIT 1")
      .bind(userId, from, until)
      .first<{ month: string; tokens: number }>(),
    db
      .prepare("SELECT DISTINCT day FROM daily_work WHERE user_id = ? AND day >= ? AND day <= ? AND commits > 0")
      .bind(userId, from, until)
      .all<{ day: string }>(),
  ]);

  const byTool = Object.fromEntries(TOOLS.map((tool) => [tool, 0])) as Record<Tool, number>;
  let tokens = 0;
  let costMicros = 0;
  let requests = 0;
  for (const row of tools.results) {
    byTool[row.tool] = row.tokens;
    tokens += row.tokens;
    costMicros += row.cost_micros;
    requests += row.requests;
  }
  const active = new Set(days.results.filter((row) => row.tokens > 0).map((row) => row.day));
  for (const row of workDays.results) active.add(row.day);
  const lived = streaks(active, until);
  const top = (TOOLS as readonly Tool[]).map((tool) => ({ tool, tokens: byTool[tool] })).sort((a, b) => b.tokens - a.tokens)[0];
  const biggest = [...days.results].sort((a, b) => b.tokens - a.tokens)[0];
  return {
    year,
    running,
    from,
    until,
    tokens,
    costMicros,
    requests,
    activeDays: active.size,
    longestStreak: lived.longest,
    commits: work?.commits ?? 0,
    insertions: work?.insertions ?? 0,
    deletions: work?.deletions ?? 0,
    repos: work?.repos ?? 0,
    tools: byTool,
    topTool: top && top.tokens > 0 ? { tool: top.tool, name: TOOL_NAMES[top.tool], share: Math.round((top.tokens / tokens) * 100) } : null,
    biggestDay: biggest && biggest.tokens > 0 ? { day: biggest.day, tokens: biggest.tokens } : null,
    bestMonth: months && months.tokens > 0 ? { month: months.month, tokens: months.tokens, tier: tierLabel(tierFor(months.tokens)) } : null,
  };
}

