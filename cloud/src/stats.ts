import { type Tool, TOOLS, addDays, today } from "./env";

export const PERIODS = {
  today: { label: "Today", days: 1 },
  week: { label: "7 days", days: 7 },
  month: { label: "30 days", days: 30 },
  all: { label: "All time", days: null },
} as const;
export type Period = keyof typeof PERIODS;

export const METRICS = {
  tokens: { label: "Tokens", column: "tokens" },
  cost: { label: "API value", column: "cost_micros" },
  requests: { label: "Requests", column: "requests" },
} as const;
export type Metric = keyof typeof METRICS;

export const isPeriod = (value: string | undefined): value is Period => !!value && value in PERIODS;
export const isMetric = (value: string | undefined): value is Metric => !!value && value in METRICS;

export interface Totals {
  tokens: number;
  costMicros: number;
  requests: number;
  tools: Record<Tool, number>;
}

export interface Entry extends Totals {
  rank: number;
  userId: string;
  login: string;
  name: string | null;
  avatarUrl: string | null;
  /** Whether the profile page can be opened by anyone. */
  public: boolean;
  activeDays: number;
}

function since(period: Period, reference: string): string {
  const days = PERIODS[period].days;
  return days === null ? "0000-00-00" : addDays(reference, -(days - 1));
}

const TOOL_SUMS = TOOLS.map((tool) => `SUM(CASE WHEN d.tool = '${tool}' THEN d.tokens ELSE 0 END) AS tool_${tool}`).join(", ");

type Row = {
  user_id: string;
  login: string;
  name: string | null;
  avatar_url: string | null;
  public: number;
  tokens: number;
  cost_micros: number;
  requests: number;
  active_days: number;
} & Record<`tool_${Tool}`, number>;

/**
 * Ranks people by what they used in a period. Without a team it lists only public profiles; for a
 * team it lists every member, since members agreed to see each other.
 */
export async function leaderboard(
  db: D1Database,
  options: {
    period: Period;
    metric: Metric;
    teamId?: string;
    limit?: number;
    reference?: string;
    /** First day to count, instead of the period's own start. Seasons use this. */
    from?: string;
    /** Last day to count. Days after it, like the rest of a month in progress, are left out. */
    until?: string;
  },
): Promise<Entry[]> {
  const column = METRICS[options.metric].column;
  const start = options.from ?? since(options.period, options.reference ?? today());
  // Conditions and their values are built together, so each ? has exactly one value.
  const where = ["d.day >= ?"];
  const values: string[] = [start];
  if (options.until) {
    where.push("d.day <= ?");
    values.push(options.until);
  }
  if (options.teamId) {
    where.push("d.user_id IN (SELECT user_id FROM team_members WHERE team_id = ?)");
    values.push(options.teamId);
  } else {
    where.push("u.public = 1");
  }
  const { results } = await db
    .prepare(
      `SELECT d.user_id, u.login, COALESCE(u.display_name, u.name) AS name, u.avatar_url, u.public, SUM(d.tokens) AS tokens, SUM(d.cost_micros) AS cost_micros,
       SUM(d.requests) AS requests, COUNT(DISTINCT CASE WHEN d.tokens > 0 THEN d.day END) AS active_days, ${TOOL_SUMS}
     FROM daily_usage d JOIN users u ON u.id = d.user_id
     WHERE ${where.join(" AND ")}
     GROUP BY d.user_id
     HAVING SUM(d.${column}) > 0
     ORDER BY SUM(d.${column}) DESC, u.login COLLATE NOCASE ASC
     LIMIT ${Math.min(Math.max(options.limit ?? 100, 1), 500)}`,
    )
    .bind(...values)
    .all<Row>();
  return results.map((row, index) => ({
    rank: index + 1,
    userId: row.user_id,
    login: row.login,
    name: row.name,
    avatarUrl: row.avatar_url,
    public: row.public === 1,
    tokens: row.tokens,
    costMicros: row.cost_micros,
    requests: row.requests,
    activeDays: row.active_days,
    tools: Object.fromEntries(TOOLS.map((tool) => [tool, row[`tool_${tool}`]])) as Record<Tool, number>,
  }));
}

export interface Profile {
  days: { day: string; tokens: number; costMicros: number; requests: number }[];
  month: Totals;
  allTime: Totals;
  activeDays: number;
  streak: number;
  longestStreak: number;
  weekRank: number | null;
}

/** One person's history: a year of days, 30-day and all-time totals, streaks and weekly rank. */
export async function profile(db: D1Database, userId: string, isPublic: boolean, reference = today()): Promise<Profile> {
  const { results } = await db
    .prepare(
      `SELECT day, SUM(tokens) AS tokens, SUM(cost_micros) AS cost_micros, SUM(requests) AS requests FROM daily_usage
       WHERE user_id = ? GROUP BY day ORDER BY day`,
    )
    .bind(userId)
    .all<{ day: string; tokens: number; cost_micros: number; requests: number }>();
  const tools = await db
    .prepare(
      `SELECT tool, SUM(tokens) AS tokens, SUM(cost_micros) AS cost_micros, SUM(requests) AS requests,
         SUM(CASE WHEN day >= ? THEN tokens ELSE 0 END) AS month_tokens,
         SUM(CASE WHEN day >= ? THEN cost_micros ELSE 0 END) AS month_cost,
         SUM(CASE WHEN day >= ? THEN requests ELSE 0 END) AS month_requests
       FROM daily_usage WHERE user_id = ? GROUP BY tool`,
    )
    .bind(since("month", reference), since("month", reference), since("month", reference), userId)
    .all<{ tool: Tool; tokens: number; cost_micros: number; requests: number; month_tokens: number; month_cost: number; month_requests: number }>();

  const empty = (): Totals => ({
    tokens: 0,
    costMicros: 0,
    requests: 0,
    tools: Object.fromEntries(TOOLS.map((tool) => [tool, 0])) as Record<Tool, number>,
  });
  const month = empty();
  const allTime = empty();
  for (const row of tools.results) {
    allTime.tokens += row.tokens;
    allTime.costMicros += row.cost_micros;
    allTime.requests += row.requests;
    allTime.tools[row.tool] = row.tokens;
    month.tokens += row.month_tokens;
    month.costMicros += row.month_cost;
    month.requests += row.month_requests;
    month.tools[row.tool] = row.month_tokens;
  }

  const active = new Set(results.filter((row) => row.tokens > 0).map((row) => row.day));
  const { current, longest } = streaks(active, reference);

  let weekRank: number | null = null;
  if (isPublic) {
    const board = await leaderboard(db, { period: "week", metric: "tokens", limit: 500, reference });
    weekRank = board.find((entry) => entry.userId === userId)?.rank ?? null;
  }

  const first = addDays(reference, -371);
  return {
    days: results
      .filter((row) => row.day >= first)
      .map((row) => ({ day: row.day, tokens: row.tokens, costMicros: row.cost_micros, requests: row.requests })),
    month,
    allTime,
    activeDays: active.size,
    streak: current,
    longestStreak: longest,
    weekRank,
  };
}

/** Days in a row with usage. The current streak may end yesterday, since today isn't over. */
export function streaks(active: Set<string>, reference: string): { current: number; longest: number } {
  let current = 0;
  let day = active.has(reference) ? reference : addDays(reference, -1);
  while (active.has(day)) {
    current++;
    day = addDays(day, -1);
  }
  let longest = 0;
  for (const start of active) {
    if (active.has(addDays(start, -1))) continue;
    let length = 0;
    let cursor = start;
    while (active.has(cursor)) {
      length++;
      cursor = addDays(cursor, 1);
    }
    longest = Math.max(longest, length);
  }
  return { current, longest };
}
