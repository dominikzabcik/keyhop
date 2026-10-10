import { Hono } from "hono";
import { apiUser, apiWriter, uploadLimit } from "./auth";
import { type AppEnv, type Tool, addDays, now, today } from "./env";
import { parseUsage } from "./usage";

/**
 * The live layer: today's per-tool totals as the app last sent them, every minute or two. A row
 * replaces the one before it and is dropped once nobody refreshes it, so this is never history.
 * The days stay in daily_usage, on the hourly sync. Only the aggregates the daily upload already
 * carries travel here: nothing about a request, a session or a prompt.
 */

/** How long a reading counts as live. The app sends every minute or two. */
export const LIVE_FRESH_SECONDS = 180;
/** How long a stale reading is kept at all before the sweep drops it. */
export const LIVE_TTL_SECONDS = 600;

export interface LiveReading {
  day: string;
  tokens: number;
  costMicros: number;
  requests: number;
  cacheRead: number | null;
  tools: Partial<Record<Tool, number>>;
  updatedAt: number;
}

/** Checks a live upload: the daily shape, for today or the days beside it, in this user's own zone. */
export function parseLive(body: unknown, reference = today()): ReturnType<typeof parseUsage> {
  const parsed = parseUsage(body, reference);
  if ("error" in parsed) return parsed;
  const allowed = new Set([addDays(reference, -1), reference, addDays(reference, 1)]);
  for (const day of parsed.days) {
    if (!allowed.has(day.day)) return { error: `A live reading is for today, not ${day.day}.` };
  }
  return parsed;
}

/** What each of these people sent in the last few minutes, by person. Nothing older counts. */
export async function liveFor(db: D1Database, userIds: string[], reference = now()): Promise<Map<string, LiveReading>> {
  const readings = new Map<string, LiveReading>();
  if (userIds.length === 0) return readings;
  const marks = userIds.map(() => "?").join(", ");
  const { results } = await db
    .prepare(
      `SELECT user_id, tool, day, tokens, cost_micros, requests, cache_read, updated_at FROM live_usage
       WHERE updated_at > ? AND user_id IN (${marks})`,
    )
    .bind(reference - LIVE_FRESH_SECONDS, ...userIds)
    .all<{ user_id: string; tool: Tool; day: string; tokens: number; cost_micros: number; requests: number; cache_read: number | null; updated_at: number }>();
  for (const row of results) {
    const reading = readings.get(row.user_id) ?? { day: row.day, tokens: 0, costMicros: 0, requests: 0, cacheRead: null, tools: {}, updatedAt: 0 };
    reading.tokens += row.tokens;
    reading.costMicros += row.cost_micros;
    reading.requests += row.requests;
    if (row.cache_read !== null) reading.cacheRead = (reading.cacheRead ?? 0) + row.cache_read;
    reading.tools[row.tool] = (reading.tools[row.tool] ?? 0) + row.tokens;
    reading.updatedAt = Math.max(reading.updatedAt, row.updated_at);
    if (row.day > reading.day) reading.day = row.day;
    readings.set(row.user_id, reading);
  }
  return readings;
}

/** Drops readings nobody has refreshed. Runs on the hourly cron beside the limits sweep. */
export async function sweepLive(db: D1Database, reference = now()): Promise<number> {
  const result = await db.prepare("DELETE FROM live_usage WHERE updated_at <= ?").bind(reference - LIVE_TTL_SECONDS).run();
  return result.meta.changes ?? 0;
}

export const live = new Hono<AppEnv>();

/** The app sends where today stands. Each tool's row replaces the one before it. */
live.post("/api/live", apiUser, apiWriter, uploadLimit, async (c) => {
  const parsed = parseLive(await c.req.json().catch(() => null));
  if ("error" in parsed) return c.json(parsed, 400);
  const user = c.get("user")!;
  const at = now();
  const statements = parsed.days.map((d) =>
    c.env.DB.prepare(
      `INSERT INTO live_usage (user_id, tool, day, tokens, cost_micros, requests, cache_read, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT (user_id, tool) DO UPDATE SET day = excluded.day, tokens = excluded.tokens, cost_micros = excluded.cost_micros,
       requests = excluded.requests, cache_read = excluded.cache_read, updated_at = excluded.updated_at`,
    ).bind(user.id, d.tool, d.day, d.tokens, d.costMicros, d.requests, d.cacheRead, at),
  );
  if (statements.length > 0) await c.env.DB.batch(statements);
  return c.json({ saved: statements.length, fresh: LIVE_FRESH_SECONDS });
});
