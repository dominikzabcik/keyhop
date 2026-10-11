import { Hono } from "hono";
import { apiUser, apiWriter, uploadLimit } from "./auth";
import { type AppEnv, type Division, type Tool, TOOLS, addDays, isDivision, now, today, toolList } from "./env";

export interface UsageDay {
  day: string;
  tool: Tool;
  tokens: number;
  costMicros: number;
  requests: number;
  /** Tokens read back from a prompt cache, when the app counted them. */
  cacheRead: number | null;
}

// Generous ceilings that still keep a typo or a broken client off the leaderboard.
const MAX_TOKENS_PER_DAY = 50_000_000_000;
const MAX_COST_PER_DAY = 50_000;
const MAX_REQUESTS_PER_DAY = 1_000_000;
const MAX_DAYS = 400;
/**
 * What a token can plausibly be worth at list prices, in dollars per million: a cached read of the
 * cheapest model at the floor, the dearest reasoning model's output at the ceiling. A day priced
 * outside this band was not counted by Keyhop's own price table.
 */
const MIN_DOLLARS_PER_MILLION = 0.001;
const MAX_DOLLARS_PER_MILLION = 1000;

/**
 * Checks an upload from the app: one entry per day and tool, within the last 400 days, and each
 * day's numbers consistent with each other, so a hand-made upload cannot buy a place on the board.
 */
export function parseUsage(body: unknown, reference = today()): { days: UsageDay[]; division?: Division } | { error: string } {
  const list = (body as { days?: unknown } | null)?.days;
  if (!Array.isArray(list)) return { error: "Send { days: [...] }." };
  const rawDivision = (body as { division?: unknown }).division;
  if (rawDivision !== undefined && !isDivision(typeof rawDivision === "string" ? rawDivision : undefined)) {
    return { error: "Division must be free, pro or max." };
  }
  if (list.length > MAX_DAYS * TOOLS.length) return { error: "Too many days at once." };
  const earliest = addDays(reference, -MAX_DAYS);
  const latest = addDays(reference, 1);
  const seen = new Set<string>();
  const days: UsageDay[] = [];
  for (const raw of list) {
    const entry = raw as Record<string, unknown>;
    const day = entry?.day;
    const tool = entry?.tool;
    if (typeof day !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(day) || Number.isNaN(Date.parse(`${day}T00:00:00Z`))) {
      return { error: "Each day needs a date like 2026-09-11." };
    }
    if (addDays(day, 0) !== day) return { error: `${day} isn't a real date.` };
    if (day < earliest || day > latest) return { error: `${day} is outside the last ${MAX_DAYS} days.` };
    if (typeof tool !== "string" || !(TOOLS as readonly string[]).includes(tool)) return { error: `Tool must be ${toolList()}.` };
    const tokens = entry.tokens;
    const cost = entry.cost;
    const requests = entry.requests;
    if (!isCount(tokens, MAX_TOKENS_PER_DAY) || !isCount(requests, MAX_REQUESTS_PER_DAY)) {
      return { error: `Tokens and requests for ${day} must be whole numbers in range.` };
    }
    if (typeof cost !== "number" || !Number.isFinite(cost) || cost < 0 || cost > MAX_COST_PER_DAY) {
      return { error: `API value for ${day} must be between 0 and ${MAX_COST_PER_DAY} dollars.` };
    }
    // A request with tokens is at least one token. A feed that counts no requests sends zero, and that is allowed.
    if (tokens > 0 && requests > tokens) return { error: `Requests for ${day} don't fit its tokens.` };
    if (tokens === 0 && cost > 0) return { error: `API value for ${day} needs tokens behind it.` };
    if (tokens > 0 && cost > 0) {
      const perMillion = (cost / tokens) * 1_000_000;
      if (perMillion < MIN_DOLLARS_PER_MILLION || perMillion > MAX_DOLLARS_PER_MILLION) {
        return { error: `API value for ${day} doesn't match its tokens at any list price.` };
      }
    }
    const cacheRead = entry.cacheRead ?? null;
    if (cacheRead !== null && (!isCount(cacheRead, MAX_TOKENS_PER_DAY) || cacheRead > tokens)) {
      return { error: `Cache reads for ${day} must be a whole number no larger than its tokens.` };
    }
    const key = `${day}|${tool}`;
    if (seen.has(key)) return { error: `${tool} on ${day} appears twice.` };
    seen.add(key);
    days.push({ day, tool: tool as Tool, tokens, costMicros: Math.round(cost * 1_000_000), requests, cacheRead });
  }
  return rawDivision === undefined ? { days } : { days, division: rawDivision as Division };
}

function isCount(value: unknown, max: number): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= max;
}

export const usage = new Hono<AppEnv>();

/** The app sends its daily totals; each day and tool replaces what was there. */
usage.post("/api/usage", apiUser, apiWriter, uploadLimit, async (c) => {
  const parsed = parseUsage(await c.req.json().catch(() => null));
  if ("error" in parsed) return c.json(parsed, 400);
  const user = c.get("user")!;
  const at = now();
  const statements = parsed.days.map((d) =>
    c.env.DB.prepare(
      `INSERT INTO daily_usage (user_id, day, tool, tokens, cost_micros, requests, cache_read, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT (user_id, day, tool) DO UPDATE SET tokens = excluded.tokens, cost_micros = excluded.cost_micros,
       requests = excluded.requests, cache_read = excluded.cache_read, updated_at = excluded.updated_at`,
    ).bind(user.id, d.day, d.tool, d.tokens, d.costMicros, d.requests, d.cacheRead, at),
  );
  if (parsed.division) statements.push(c.env.DB.prepare("UPDATE users SET division = ? WHERE id = ?").bind(parsed.division, user.id));
  for (let start = 0; start < statements.length; start += 100) {
    await c.env.DB.batch(statements.slice(start, start + 100));
  }
  return c.json({ saved: parsed.days.length });
});
