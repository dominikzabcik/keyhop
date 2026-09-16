import { Hono } from "hono";
import { apiUser, apiWriter } from "./auth";
import { type AppEnv, type Tool, TOOLS, now, toolList } from "./env";

/**
 * Where a person stands against their providers' limits, so a linked phone can count down to the
 * next reset without ever holding a provider login.
 *
 * Two things keep this narrow. It is opt-in: a computer sends nothing until limit sharing is turned
 * on. And it is current state only: every upload replaces the last one, a row older than a day is
 * treated as gone, and no history is kept, so there is nothing here to look back through.
 */

export interface LimitRow {
  /** Opaque per-account key from the computer. Stable across uploads, meaningless off this row. */
  accountKey: string;
  tool: Tool;
  /** Only a label a person typed for the account. Emails and account names are never sent. */
  label: string | null;
  windowLabel: string;
  usedPercent: number;
  /** Unix seconds, or null for a window whose provider does not say when it turns over. */
  resetsAt: number | null;
}

/** A reading stops counting once it is this old: the computer it came from has gone quiet. */
export const LIMIT_TTL_SECONDS = 24 * 3600;

const MAX_ENTRIES = 80;
const MAX_KEY = 64;
const MAX_LABEL = 40;
const MAX_WINDOW = 16;
/** A reset further out than this is a broken clock, not a monthly window. */
const MAX_AHEAD_SECONDS = 120 * 86400;

/** Checks an upload from a computer: one entry per account and window, all of it current. */
export function parseLimits(body: unknown, reference = now()): { limits: LimitRow[] } | { error: string } {
  const list = (body as { limits?: unknown } | null)?.limits;
  if (!Array.isArray(list)) return { error: "Send { limits: [...] }." };
  if (list.length > MAX_ENTRIES) return { error: "Too many limits at once." };
  const seen = new Set<string>();
  const limits: LimitRow[] = [];
  for (const raw of list) {
    const entry = raw as Record<string, unknown>;
    const accountKey = entry?.accountKey;
    if (typeof accountKey !== "string" || !/^[A-Za-z0-9_-]{1,64}$/.test(accountKey)) {
      return { error: `Each account key must be up to ${MAX_KEY} letters, digits, dashes or underscores.` };
    }
    const tool = entry?.tool;
    if (typeof tool !== "string" || !(TOOLS as readonly string[]).includes(tool)) {
      return { error: `Tool must be ${toolList()}.` };
    }
    const windowLabel = typeof entry?.windowLabel === "string" ? entry.windowLabel.trim() : "";
    if (!windowLabel || windowLabel.length > MAX_WINDOW) {
      return { error: `Each window needs a name of up to ${MAX_WINDOW} characters.` };
    }
    const label = typeof entry?.label === "string" ? entry.label.trim().slice(0, MAX_LABEL) : "";
    const usedPercent = entry?.usedPercent;
    if (typeof usedPercent !== "number" || !Number.isFinite(usedPercent) || usedPercent < 0 || usedPercent > 100) {
      return { error: `Used percent for ${windowLabel} must be between 0 and 100.` };
    }
    const resetsAt = entry?.resetsAt ?? null;
    if (resetsAt !== null) {
      if (typeof resetsAt !== "number" || !Number.isInteger(resetsAt)) return { error: `Reset time for ${windowLabel} must be whole seconds.` };
      if (resetsAt < reference - LIMIT_TTL_SECONDS || resetsAt > reference + MAX_AHEAD_SECONDS) {
        return { error: `Reset time for ${windowLabel} is outside the window this can hold.` };
      }
    }
    const key = `${accountKey}|${windowLabel}`;
    if (seen.has(key)) return { error: `${windowLabel} appears twice for one account.` };
    seen.add(key);
    limits.push({
      accountKey,
      tool: tool as Tool,
      label: label || null,
      windowLabel,
      usedPercent: Math.round(usedPercent * 10) / 10,
      resetsAt: resetsAt as number | null,
    });
  }
  return { limits };
}

interface StoredRow {
  account_key: string;
  tool: Tool;
  label: string | null;
  window_label: string;
  used_percent: number;
  resets_at: number | null;
  updated_at: number;
}

/** What the phone reads: the readings still current, soonest reset first. */
export async function currentLimits(db: D1Database, userId: string, reference = now()) {
  const { results } = await db
    .prepare("SELECT account_key, tool, label, window_label, used_percent, resets_at, updated_at FROM account_limits WHERE user_id = ? AND updated_at > ?")
    .bind(userId, reference - LIMIT_TTL_SECONDS)
    .all<StoredRow>();
  const limits = results
    .map((row) => ({
      accountKey: row.account_key,
      tool: row.tool,
      label: row.label,
      windowLabel: row.window_label,
      usedPercent: row.used_percent,
      resetsAt: row.resets_at,
    }))
    // A window that never says when it turns over sits after the ones that do.
    .sort((a, b) => (a.resetsAt ?? Infinity) - (b.resetsAt ?? Infinity) || b.usedPercent - a.usedPercent);
  const updatedAt = results.reduce((latest, row) => Math.max(latest, row.updated_at), 0);
  return { limits, updatedAt: updatedAt || null };
}

export const limits = new Hono<AppEnv>();

/** The computer sends where it stands. Each upload replaces the one before it. */
limits.post("/api/limits", apiUser, apiWriter, async (c) => {
  const parsed = parseLimits(await c.req.json().catch(() => null));
  if ("error" in parsed) return c.json(parsed, 400);
  const user = c.get("user")!;
  const at = now();
  const statements = [
    c.env.DB.prepare("DELETE FROM account_limits WHERE user_id = ?").bind(user.id),
    ...parsed.limits.map((limit) =>
      c.env.DB.prepare(
        `INSERT INTO account_limits (user_id, account_key, tool, label, window_label, used_percent, resets_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(user.id, limit.accountKey, limit.tool, limit.label, limit.windowLabel, limit.usedPercent, limit.resetsAt, at),
    ),
  ];
  await c.env.DB.batch(statements);
  return c.json({ saved: parsed.limits.length });
});

/** The phone reads it. A read-only link is enough, the way the season and quests are. */
limits.get("/api/limits", apiUser, async (c) => {
  const user = c.get("user")!;
  return c.json(await currentLimits(c.env.DB, user.id));
});

/** Turning limit sharing off takes the readings with it, right away. */
limits.delete("/api/limits", apiUser, apiWriter, async (c) => {
  const user = c.get("user")!;
  await c.env.DB.prepare("DELETE FROM account_limits WHERE user_id = ?").bind(user.id).run();
  return c.body(null, 204);
});
