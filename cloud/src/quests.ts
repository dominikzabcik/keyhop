import { Hono } from "hono";
import { apiUser } from "./auth";
import { type AppEnv, type Tool, TOOLS, addDays, today } from "./env";
import { currentSeason, seasonBoard, seasonOf, tierFor } from "./seasons";
import { streaks } from "./stats";

/**
 * Quests and badges. Like seasons, both are counted from the daily totals already stored: a quest is
 * a goal measured against those days, and a badge is a fact about them. Nothing is written, so they
 * can never disagree with the usage they came from, and they stay right when a day is re-synced.
 */

export interface Quest {
  key: string;
  name: string;
  note: string;
  /** "day" resets at midnight UTC, "week" over the last seven days. */
  period: "day" | "week";
  done: number;
  target: number;
  complete: boolean;
}

export interface Badge {
  key: string;
  name: string;
  note: string;
  earned: boolean;
  /** The day it was earned, for the ones that can name one. */
  day?: string;
}

interface DayRow {
  day: string;
  tool: Tool;
  tokens: number;
}

/** Every day this person has synced, one row per tool. */
async function dayRows(db: D1Database, userId: string): Promise<DayRow[]> {
  const { results } = await db
    .prepare("SELECT day, tool, SUM(tokens) AS tokens FROM daily_usage WHERE user_id = ? GROUP BY day, tool ORDER BY day")
    .bind(userId)
    .all<DayRow>();
  return results;
}

const byDay = (rows: DayRow[]) => {
  const days = new Map<string, { tokens: number; tools: Set<Tool> }>();
  for (const row of rows) {
    const entry = days.get(row.day) ?? { tokens: 0, tools: new Set<Tool>() };
    entry.tokens += row.tokens;
    if (row.tokens > 0) entry.tools.add(row.tool);
    days.set(row.day, entry);
  }
  return days;
};

const quest = (key: string, name: string, note: string, period: "day" | "week", done: number, target: number): Quest => ({
  key,
  name,
  note,
  period,
  done: Math.min(done, target),
  target,
  complete: done >= target,
});

/** Today's and this week's goals, with how far along they are. */
export function questsFrom(rows: DayRow[], reference = today()): Quest[] {
  const days = byDay(rows);
  const on = (day: string) => days.get(day) ?? { tokens: 0, tools: new Set<Tool>() };
  const todayEntry = on(reference);
  const yesterday = on(addDays(reference, -1));

  const week = Array.from({ length: 7 }, (_, back) => addDays(reference, -back));
  const lastWeek = Array.from({ length: 7 }, (_, back) => addDays(reference, -(back + 7)));
  const weekTools = new Set<Tool>();
  let weekTokens = 0;
  let weekActive = 0;
  for (const day of week) {
    const entry = on(day);
    weekTokens += entry.tokens;
    if (entry.tokens > 0) weekActive++;
    for (const tool of entry.tools) weekTools.add(tool);
  }
  const lastWeekTokens = lastWeek.reduce((sum, day) => sum + on(day).tokens, 0);

  return [
    quest("today", "Get going", "Use any tool today.", "day", todayEntry.tokens > 0 ? 1 : 0, 1),
    quest("two-tools", "Two tools", "Use two different tools today.", "day", todayEntry.tools.size, 2),
    quest(
      "beat-yesterday",
      "Beat yesterday",
      yesterday.tokens > 0 ? `Pass yesterday's ${Math.round(yesterday.tokens / 1000).toLocaleString("en-US")}K tokens.` : "Any tokens today beat an empty yesterday.",
      "day",
      Math.min(todayEntry.tokens, Math.max(yesterday.tokens, 1)),
      Math.max(yesterday.tokens, 1),
    ),
    quest("five-days", "Five days", "Use Keyhop on five days this week.", "week", weekActive, 5),
    quest("every-tool", "Every tool", "Use all four tools this week.", "week", weekTools.size, TOOLS.length),
    quest(
      "beat-last-week",
      "Beat last week",
      lastWeekTokens > 0 ? "Pass last week's total." : "Any tokens this week beat an empty one.",
      "week",
      Math.min(weekTokens, Math.max(lastWeekTokens, 1)),
      Math.max(lastWeekTokens, 1),
    ),
  ];
}

const badge = (key: string, name: string, note: string, earned: boolean, day?: string): Badge => ({ key, name, note, earned, day });

/** The first day, if any, where the running total passes a mark. */
function dayReaching(rows: DayRow[], target: number): string | undefined {
  const days = [...byDay(rows).entries()].sort(([a], [b]) => (a < b ? -1 : 1));
  let total = 0;
  for (const [day, entry] of days) {
    total += entry.tokens;
    if (total >= target) return day;
  }
  return undefined;
}

/** The first day a streak of `length` days ended. */
function dayCompletingStreak(active: Set<string>, length: number): string | undefined {
  for (const day of [...active].sort()) {
    let run = 0;
    let cursor = day;
    while (active.has(cursor) && run < length) {
      run++;
      cursor = addDays(cursor, 1);
    }
    if (run >= length) return addDays(day, length - 1);
  }
  return undefined;
}

/** What this person's own history has earned them. `podium` comes from the season standings. */
export function badgesFrom(rows: DayRow[], podium: { top3: boolean; bestTier: string | null }, reference = today()): Badge[] {
  const days = byDay(rows);
  const active = new Set([...days.entries()].filter(([, entry]) => entry.tokens > 0).map(([day]) => day));
  const { longest } = streaks(active, reference);
  const allTime = [...days.values()].reduce((sum, entry) => sum + entry.tokens, 0);
  const allTools = [...days.entries()].find(([, entry]) => entry.tools.size === TOOLS.length);
  const biggest = [...days.entries()].sort(([, a], [, b]) => b.tokens - a.tokens)[0];
  const firstDay = [...active].sort()[0];

  return [
    badge("first-sync", "First light", "Synced a day of usage.", active.size > 0, firstDay),
    badge("streak-7", "Seven in a row", "A seven-day streak.", longest >= 7, dayCompletingStreak(active, 7)),
    badge("streak-30", "Thirty in a row", "A thirty-day streak.", longest >= 30, dayCompletingStreak(active, 30)),
    badge("streak-100", "A hundred in a row", "A hundred-day streak.", longest >= 100, dayCompletingStreak(active, 100)),
    badge("all-tools", "Full house", "Used Claude Code, Cursor, Codex and Gemini CLI in one day.", !!allTools, allTools?.[0]),
    badge("big-day", "Big day", "A billion tokens in a single day.", !!biggest && biggest[1].tokens >= 1_000_000_000, biggest?.[0]),
    badge("billion", "Billion", "A billion tokens all told.", allTime >= 1_000_000_000, dayReaching(rows, 1_000_000_000)),
    badge("ten-billion", "Ten billion", "Ten billion tokens all told.", allTime >= 10_000_000_000, dayReaching(rows, 10_000_000_000)),
    badge("climber", "Climber", "Reached Gold or above in a season.", podium.bestTier !== null, undefined),
    badge("podium", "Podium", "Finished a season in the top three.", podium.top3, undefined),
  ];
}

/** The best tier this person's months have earned, and whether any season put them in the top three. */
export async function seasonHonours(
  db: D1Database,
  userId: string,
  rows: DayRow[],
  reference = today(),
): Promise<{ top3: boolean; bestTier: string | null }> {
  const months = new Map<string, number>();
  for (const row of rows) {
    const month = seasonOf(row.day);
    months.set(month, (months.get(month) ?? 0) + row.tokens);
  }
  const order = ["bronze", "silver", "gold", "platinum", "diamond", "master"];
  let best: string | null = null;
  for (const tokens of months.values()) {
    const tier = tierFor(tokens);
    if (order.indexOf(tier.key) >= order.indexOf("gold") && (best === null || order.indexOf(tier.key) > order.indexOf(best))) {
      best = tier.key;
    }
  }
  // Only the standings can say where someone placed, so this asks for the seasons they actually played.
  let top3 = false;
  for (const month of [...months.keys()].sort().reverse().slice(0, 6)) {
    const board = await seasonBoard(db, { season: month, metric: "tokens", limit: 3, reference });
    if (board.some((entry) => entry.userId === userId && entry.rank <= 3)) {
      top3 = true;
      break;
    }
  }
  return { top3, bestTier: best };
}

/** Everything a profile needs: today's and this week's quests, and the badges earned so far. */
export async function questsAndBadges(db: D1Database, userId: string, reference = today()) {
  const rows = await dayRows(db, userId);
  const honours = await seasonHonours(db, userId, rows, reference);
  return {
    quests: questsFrom(rows, reference),
    badges: badgesFrom(rows, honours, reference),
    bestTier: honours.bestTier,
  };
}

/** One person's badges, for their profile. */
export async function profileBadges(db: D1Database, userId: string, reference = today()): Promise<Badge[]> {
  const rows = await dayRows(db, userId);
  return badgesFrom(rows, await seasonHonours(db, userId, rows, reference), reference);
}

/** One person's quests, for the season page and the app's window. */
export async function questsFor(db: D1Database, userId: string, reference = today()): Promise<Quest[]> {
  return questsFrom(await dayRows(db, userId), reference);
}

export const quests = new Hono<AppEnv>();

/** The signed-in person's quests and badges, for the app's window and the website. */
quests.get("/api/quests", apiUser, async (c) => {
  const user = c.get("user")!;
  const { quests: list, badges } = await questsAndBadges(c.env.DB, user.id);
  return c.json({
    season: currentSeason(),
    quests: list,
    badges: badges.map((entry) => ({ ...entry, day: entry.day ?? null })),
  });
});
