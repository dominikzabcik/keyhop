import { type Tool, TOOLS, addDays, today } from "./env";

export const PERIODS = {
  today: { label: "Today", days: 1 },
  week: { label: "7 days", days: 7 },
  month: { label: "30 days", days: 30 },
  all: { label: "All time", days: null },
} as const;
export type Period = keyof typeof PERIODS;

/**
 * What a board can be ranked by. `sort` is the expression it orders on, written against the two
 * sources a day comes from: `u` for what the day cost, `w` for what it produced.
 */
export const METRICS = {
  tokens: { label: "Tokens", sort: "COALESCE(u.tokens, 0)" },
  cost: { label: "API value", sort: "COALESCE(u.cost_micros, 0)" },
  requests: { label: "Requests", sort: "COALESCE(u.requests, 0)" },
  commits: { label: "Commits", sort: "COALESCE(w.commits, 0)" },
  lines: { label: "Lines", sort: "COALESCE(w.insertions, 0) + COALESCE(w.deletions, 0)" },
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

/** What came out of the days, next to what they cost. Zero for anyone who hasn't synced commits. */
export interface Work {
  commits: number;
  insertions: number;
  deletions: number;
  repos: number;
}

export interface Entry extends Totals, Work {
  rank: number;
  userId: string;
  login: string;
  name: string | null;
  avatarUrl: string | null;
  /** Whether the profile page can be opened by anyone. */
  public: boolean;
  /** Days with tokens or commits, since either one is a day someone worked. */
  activeDays: number;
}

function since(period: Period, reference: string): string {
  const days = PERIODS[period].days;
  return days === null ? "0000-00-00" : addDays(reference, -(days - 1));
}

const TOOL_SUMS = TOOLS.map((tool) => `SUM(CASE WHEN tool = '${tool}' THEN tokens ELSE 0 END) AS tool_${tool}`).join(", ");

type Row = {
  user_id: string;
  login: string;
  name: string | null;
  avatar_url: string | null;
  public: number;
  tokens: number;
  cost_micros: number;
  requests: number;
  commits: number;
  insertions: number;
  deletions: number;
  repos: number;
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
  const sort = METRICS[options.metric].sort;
  const start = options.from ?? since(options.period, options.reference ?? today());

  // The range is the same for every source, but each one is its own subquery, so the values are
  // pushed once per place the clause is used and stay in the order the statement reads them.
  const range = options.until ? "day >= ? AND day <= ?" : "day >= ?";
  const values: string[] = [];
  const forRange = () => {
    values.push(start);
    if (options.until) values.push(options.until);
  };

  // Usage and commits are counted apart and joined per person, so someone who only ever commits
  // still appears, and a board ranked by tokens is unchanged by the commits beside it.
  forRange();
  forRange();
  forRange();
  forRange();
  const membership = options.teamId ? "p.user_id IN (SELECT user_id FROM team_members WHERE team_id = ?)" : "people.public = 1";
  if (options.teamId) values.push(options.teamId);

  const { results } = await db
    .prepare(
      `WITH u AS (
         SELECT user_id, SUM(tokens) AS tokens, SUM(cost_micros) AS cost_micros, SUM(requests) AS requests, ${TOOL_SUMS}
         FROM daily_usage WHERE ${range} GROUP BY user_id
       ),
       w AS (
         SELECT user_id, SUM(commits) AS commits, SUM(insertions) AS insertions, SUM(deletions) AS deletions,
           COUNT(DISTINCT CASE WHEN commits > 0 THEN repo END) AS repos
         FROM daily_work WHERE ${range} GROUP BY user_id
       ),
       a AS (
         SELECT user_id, COUNT(*) AS days FROM (
           SELECT user_id, day FROM daily_usage WHERE ${range} AND tokens > 0
           UNION
           SELECT user_id, day FROM daily_work WHERE ${range} AND commits > 0
         ) GROUP BY user_id
       ),
       p AS (SELECT user_id FROM u UNION SELECT user_id FROM w)
       SELECT p.user_id, people.login, COALESCE(people.display_name, people.name) AS name, people.avatar_url, people.public,
         COALESCE(u.tokens, 0) AS tokens, COALESCE(u.cost_micros, 0) AS cost_micros, COALESCE(u.requests, 0) AS requests,
         COALESCE(w.commits, 0) AS commits, COALESCE(w.insertions, 0) AS insertions, COALESCE(w.deletions, 0) AS deletions,
         COALESCE(w.repos, 0) AS repos, COALESCE(a.days, 0) AS active_days,
         ${TOOLS.map((tool) => `COALESCE(u.tool_${tool}, 0) AS tool_${tool}`).join(", ")}
       FROM p
       JOIN users people ON people.id = p.user_id
       LEFT JOIN u ON u.user_id = p.user_id
       LEFT JOIN w ON w.user_id = p.user_id
       LEFT JOIN a ON a.user_id = p.user_id
       WHERE ${membership} AND ${sort} > 0
       ORDER BY ${sort} DESC, people.login COLLATE NOCASE ASC
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
    commits: row.commits,
    insertions: row.insertions,
    deletions: row.deletions,
    repos: row.repos,
    activeDays: row.active_days,
    tools: Object.fromEntries(TOOLS.map((tool) => [tool, row[`tool_${tool}`]])) as Record<Tool, number>,
  }));
}

export interface Profile {
  days: { day: string; tokens: number; costMicros: number; requests: number; commits: number }[];
  month: Totals & Work;
  allTime: Totals & Work;
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

  const work = await db
    .prepare(
      `SELECT day, SUM(commits) AS commits, SUM(insertions) AS insertions, SUM(deletions) AS deletions, COUNT(DISTINCT repo) AS repos
       FROM daily_work WHERE user_id = ? GROUP BY day ORDER BY day`,
    )
    .bind(userId)
    .all<{ day: string; commits: number; insertions: number; deletions: number; repos: number }>();

  const empty = (): Totals & Work => ({
    tokens: 0,
    costMicros: 0,
    requests: 0,
    commits: 0,
    insertions: 0,
    deletions: 0,
    repos: 0,
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

  // Repositories are counted over the whole window rather than summed per day, so a repository
  // touched on twenty days is still one repository.
  const monthStart = since("month", reference);
  const monthRepos = new Set<string>();
  const allRepos = new Set<string>();
  const commitsByDay = new Map<string, number>();
  for (const row of work.results) {
    commitsByDay.set(row.day, row.commits);
    allTime.commits += row.commits;
    allTime.insertions += row.insertions;
    allTime.deletions += row.deletions;
    if (row.day >= monthStart) {
      month.commits += row.commits;
      month.insertions += row.insertions;
      month.deletions += row.deletions;
    }
  }
  const repoRows = await db
    .prepare("SELECT DISTINCT day, repo FROM daily_work WHERE user_id = ? AND commits > 0")
    .bind(userId)
    .all<{ day: string; repo: string }>();
  for (const row of repoRows.results) {
    allRepos.add(row.repo);
    if (row.day >= monthStart) monthRepos.add(row.repo);
  }
  month.repos = monthRepos.size;
  allTime.repos = allRepos.size;

  // A day counts as active when it cost tokens or produced commits: either one is a day worked.
  const active = new Set(results.filter((row) => row.tokens > 0).map((row) => row.day));
  for (const [day, commits] of commitsByDay) if (commits > 0) active.add(day);
  const { current, longest } = streaks(active, reference);

  let weekRank: number | null = null;
  if (isPublic) {
    const board = await leaderboard(db, { period: "week", metric: "tokens", limit: 500, reference });
    weekRank = board.find((entry) => entry.userId === userId)?.rank ?? null;
  }

  const first = addDays(reference, -371);
  // A day the person only committed on has no usage row, so the two sets are merged before the year
  // is cut, and a commit-only day still shows up on the heatmap.
  const everyDay = new Set([...results.map((row) => row.day), ...commitsByDay.keys()]);
  const usageOf = new Map(results.map((row) => [row.day, row]));
  return {
    days: [...everyDay]
      .filter((day) => day >= first)
      .sort()
      .map((day) => ({
        day,
        tokens: usageOf.get(day)?.tokens ?? 0,
        costMicros: usageOf.get(day)?.cost_micros ?? 0,
        requests: usageOf.get(day)?.requests ?? 0,
        commits: commitsByDay.get(day) ?? 0,
      })),
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
