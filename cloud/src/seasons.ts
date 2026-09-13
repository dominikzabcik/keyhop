import { Hono } from "hono";
import { type Metric, type Entry, isMetric, leaderboard } from "./stats";
import { type AppEnv, addDays, today } from "./env";
import { teamForMember } from "./teams";

/**
 * Ranked seasons. A season is one calendar month in UTC, and a tier comes from the tokens someone
 * used inside it. Nothing is stored: every season, past or present, is counted from the daily totals,
 * so standings can never drift from the usage they came from.
 */

/** Keyhop's first ranked season. Months before this one aren't offered. */
export const FIRST_SEASON = "2026-09";

export interface Tier {
  key: string;
  name: string;
  /** 3, 2 or 1 inside a tier, counting up to the next one. Master has no divisions. */
  division: number | null;
  /** Tokens where this tier starts. */
  at: number;
}

/** Six tiers, each a step of roughly three times the one below it. */
const LADDER: { key: string; name: string; at: number }[] = [
  { key: "bronze", name: "Bronze", at: 0 },
  { key: "silver", name: "Silver", at: 250_000_000 },
  { key: "gold", name: "Gold", at: 1_000_000_000 },
  { key: "platinum", name: "Platinum", at: 3_000_000_000 },
  { key: "diamond", name: "Diamond", at: 8_000_000_000 },
  { key: "master", name: "Master", at: 20_000_000_000 },
];

export const TIERS = LADDER;

const ROMAN = ["", "I", "II", "III"];

export const tierLabel = (tier: Tier): string => (tier.division ? `${tier.name} ${ROMAN[tier.division]}` : tier.name);

/**
 * The tier for a season's tokens. Inside a tier the three divisions are spaced the way the tiers
 * themselves are, so each one is about the same amount of work as the last.
 */
export function tierFor(tokens: number): Tier {
  let index = 0;
  for (let i = LADDER.length - 1; i >= 0; i--) {
    if (tokens >= LADDER[i].at) {
      index = i;
      break;
    }
  }
  const tier = LADDER[index];
  const next = LADDER[index + 1];
  if (!next) return { key: tier.key, name: tier.name, division: null, at: tier.at };
  const floor = Math.max(tier.at, 1);
  const step = Math.pow(next.at / floor, 1 / 3);
  const second = floor * step;
  const third = floor * step * step;
  const division = tokens >= third ? 1 : tokens >= second ? 2 : 3;
  return { key: tier.key, name: tier.name, division, at: tier.at };
}

/** What it takes to reach the next division or tier, or null at the top. */
export function nextStep(tokens: number): { label: string; tokens: number } | null {
  const tier = tierFor(tokens);
  const index = LADDER.findIndex((entry) => entry.key === tier.key);
  const next = LADDER[index + 1];
  if (!next) return null;
  const floor = Math.max(tier.at, 1);
  const step = Math.pow(next.at / floor, 1 / 3);
  const marks: { label: string; at: number }[] = [
    { label: tierLabel({ ...tier, division: 2 }), at: floor * step },
    { label: tierLabel({ ...tier, division: 1 }), at: floor * step * step },
    { label: tierLabel(tierFor(next.at)), at: next.at },
  ];
  const target = marks.find((mark) => tokens < mark.at);
  return target ? { label: target.label, tokens: Math.ceil(target.at - tokens) } : null;
}

export const isSeason = (value: string | undefined): value is string =>
  !!value && /^\d{4}-\d{2}$/.test(value) && value >= FIRST_SEASON && value <= currentSeason();

/** The season a day belongs to, as YYYY-MM. */
export const seasonOf = (day: string): string => day.slice(0, 7);

export const currentSeason = (reference = today()): string => seasonOf(reference);

/** A season's first and last day, the last one capped at today for the season in progress. */
export function seasonRange(season: string, reference = today()): { from: string; to: string; over: boolean } {
  const from = `${season}-01`;
  const [year, month] = season.split("-").map(Number);
  const last = new Date(Date.UTC(year, month, 0)).toISOString().slice(0, 10);
  return { from, to: last <= reference ? last : reference, over: last < reference };
}

export function seasonLabel(season: string): string {
  const [year, month] = season.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, 1)).toLocaleDateString("en-US", { month: "long", year: "numeric", timeZone: "UTC" });
}

/** Every season Keyhop has run, newest first. */
export function seasonList(reference = today()): string[] {
  const list: string[] = [];
  let season = currentSeason(reference);
  while (season >= FIRST_SEASON) {
    list.push(season);
    const [year, month] = season.split("-").map(Number);
    season = new Date(Date.UTC(year, month - 2, 1)).toISOString().slice(0, 7);
  }
  return list;
}

/** Days left in a season, counting today. Zero once it's over. */
export function daysLeft(season: string, reference = today()): number {
  const [year, month] = season.split("-").map(Number);
  const last = new Date(Date.UTC(year, month, 0)).toISOString().slice(0, 10);
  // The last day still counts as a day left: the season runs to the end of it.
  if (last < reference) return 0;
  let days = 0;
  let day = reference;
  while (day <= last) {
    days++;
    day = addDays(day, 1);
  }
  return days;
}

export interface Ranked extends Entry {
  tier: Tier;
}

/** A season's standings, each person with the tier their tokens earned. */
export async function seasonBoard(
  db: D1Database,
  options: { season: string; metric: Metric; teamId?: string; limit?: number; reference?: string },
): Promise<Ranked[]> {
  const reference = options.reference ?? today();
  const range = seasonRange(options.season, reference);
  const entries = await leaderboard(db, {
    period: "all",
    metric: options.metric,
    teamId: options.teamId,
    limit: options.limit,
    from: range.from,
    until: range.to,
    reference,
  });
  return entries.map((entry) => ({ ...entry, tier: tierFor(entry.tokens) }));
}

export interface Standing {
  season: string;
  label: string;
  /** Null when this person used nothing in the season, or isn't ranked. */
  rank: number | null;
  players: number;
  tokens: number;
  tier: Tier;
  next: { label: string; tokens: number } | null;
  daysLeft: number;
  over: boolean;
}

/** One person's place in a season. */
export async function standing(
  db: D1Database,
  userId: string,
  options: { season?: string; teamId?: string; reference?: string } = {},
): Promise<Standing> {
  const reference = options.reference ?? today();
  const season = options.season ?? currentSeason(reference);
  const board = await seasonBoard(db, { season, metric: "tokens", teamId: options.teamId, limit: 500, reference });
  const mine = board.find((entry) => entry.userId === userId);
  const tokens = mine?.tokens ?? 0;
  return {
    season,
    label: seasonLabel(season),
    rank: mine?.rank ?? null,
    players: board.length,
    tokens,
    tier: tierFor(tokens),
    next: nextStep(tokens),
    daysLeft: daysLeft(season, reference),
    over: seasonRange(season, reference).over,
  };
}

export const seasons = new Hono<AppEnv>();

/** The current season, or one that's finished, with the standings and the caller's own place. */
seasons.get("/api/season", async (c) => {
  const asked = c.req.query("season");
  if (asked && !isSeason(asked)) return c.json({ error: "That season hasn't run." }, 400);
  const season = asked ?? currentSeason();
  const metric = c.req.query("metric");
  const user = c.get("user");

  let teamId: string | undefined;
  const slug = c.req.query("team");
  if (slug) {
    if (!user) return c.json({ error: "Sign in to see a team's season." }, 401);
    const membership = await teamForMember(c.env.DB, slug, user.id);
    if (!membership) return c.json({ error: "You aren't in that team." }, 404);
    teamId = membership.team.id;
  }

  const board = await seasonBoard(c.env.DB, { season, metric: isMetric(metric) ? metric : "tokens", teamId });
  const mine = user ? board.find((entry) => entry.userId === user.id) : undefined;
  const range = seasonRange(season);
  return c.json({
    season,
    label: seasonLabel(season),
    daysLeft: daysLeft(season),
    over: range.over,
    you: user
      ? {
          rank: mine?.rank ?? null,
          tokens: mine?.tokens ?? 0,
          tier: tierFor(mine?.tokens ?? 0),
          next: nextStep(mine?.tokens ?? 0),
        }
      : null,
    players: board.length,
    entries: board.map((entry) => ({
      rank: entry.rank,
      login: entry.login,
      name: entry.name,
      avatarUrl: entry.avatarUrl,
      public: entry.public,
      tokens: entry.tokens,
      cost: entry.costMicros / 1_000_000,
      requests: entry.requests,
      activeDays: entry.activeDays,
      tools: entry.tools,
      tier: entry.tier,
      isYou: !!user && entry.userId === user.id,
    })),
  });
});
