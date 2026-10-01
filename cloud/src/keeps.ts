import { today } from "./env";
import { activity } from "./stats";

/**
 * A keep is what a claimed day gives you. The streak still counts itself from tokens and commits.
 * Claiming is the moment you take that day's keep, and a longer run takes a rarer one.
 */

export interface Keep {
  key: string;
  name: string;
  note: string;
}

export interface KeepCount extends Keep {
  count: number;
}

export interface ClaimState {
  streak: number;
  /** Today already has tokens or a commit, so it counts and can be claimed. */
  active: boolean;
  claimed: boolean;
  /** The keep today would give, once the day counts. */
  today: Keep | null;
  keeps: KeepCount[];
}

const LADDER: { at: number; keep: Keep }[] = [
  { at: 100, keep: { key: "beacon", name: "Beacon", note: "A hundred days in a row." } },
  { at: 30, keep: { key: "flare", name: "Flare", note: "Thirty days in a row." } },
  { at: 7, keep: { key: "ember", name: "Ember", note: "Seven days in a row." } },
  { at: 3, keep: { key: "glow", name: "Glow", note: "Three days in a row." } },
  { at: 1, keep: { key: "spark", name: "Spark", note: "A day on the streak." } },
];

/** The keep a streak of this length opens. A quiet day has no keep. */
export function keepFor(streak: number): Keep {
  return (LADDER.find((step) => streak >= step.at) ?? LADDER[LADDER.length - 1]).keep;
}

async function dayCounts(db: D1Database, userId: string, day: string): Promise<boolean> {
  const usage = await db
    .prepare("SELECT 1 AS ok FROM daily_usage WHERE user_id = ? AND day = ? AND tokens > 0 LIMIT 1")
    .bind(userId, day)
    .first();
  if (usage) return true;
  const work = await db
    .prepare("SELECT 1 AS ok FROM daily_work WHERE user_id = ? AND day = ? AND commits > 0 LIMIT 1")
    .bind(userId, day)
    .first();
  return work !== null;
}

function collected(rows: { streak: number }[]): KeepCount[] {
  const counts = new Map<string, number>();
  for (const row of rows) {
    const keep = keepFor(row.streak);
    counts.set(keep.key, (counts.get(keep.key) ?? 0) + 1);
  }
  return [...LADDER].reverse().flatMap((step) => {
    const count = counts.get(step.keep.key) ?? 0;
    return count > 0 ? [{ ...step.keep, count }] : [];
  });
}

/** Whether today can be claimed, and the keeps already taken. */
export async function claimState(db: D1Database, userId: string, reference = today()): Promise<ClaimState> {
  const [lived, active, claimed, rows] = await Promise.all([
    activity(db, { userId }, reference),
    dayCounts(db, userId, reference),
    db.prepare("SELECT day FROM claims WHERE user_id = ? AND day = ?").bind(userId, reference).first(),
    db.prepare("SELECT streak FROM claims WHERE user_id = ?").bind(userId).all<{ streak: number }>(),
  ]);
  return {
    streak: lived.streak,
    active,
    claimed: claimed !== null,
    today: active ? keepFor(lived.streak) : null,
    keeps: collected(rows.results),
  };
}

/** Take today's keep. A day can be claimed once, and only after it has counted. */
export async function claimToday(
  db: D1Database,
  userId: string,
  reference = today(),
): Promise<{ state: ClaimState; opened: Keep | null; status: "opened" | "kept" | "quiet" }> {
  const before = await claimState(db, userId, reference);
  if (!before.active || !before.today) return { state: before, opened: null, status: "quiet" };
  if (before.claimed) return { state: before, opened: null, status: "kept" };
  const inserted = await db
    .prepare("INSERT INTO claims (user_id, day, streak) VALUES (?, ?, ?) ON CONFLICT (user_id, day) DO NOTHING")
    .bind(userId, reference, before.streak)
    .run();
  const state = await claimState(db, userId, reference);
  if ((inserted.meta.changes ?? 0) < 1) return { state, opened: null, status: "kept" };
  return { state, opened: before.today, status: "opened" };
}
