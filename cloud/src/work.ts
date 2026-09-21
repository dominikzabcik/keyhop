import { Hono } from "hono";
import { apiUser, apiWriter, uploadLimit } from "./auth";
import { type AppEnv, addDays, now, today } from "./env";

/**
 * How long an unfinished index is believed. A computer part-way through reports every sync, so a
 * row older than this belongs to an app that has stopped, and saying "still indexing" about it
 * would be worse than saying nothing.
 */
export const INDEX_TTL_SECONDS = 6 * 3600;

/**
 * Commits, as the other half of a day. Usage says what a day cost; this says what came out of it.
 *
 * Everything here is counted on the person's own computer and sent as finished totals: one row per
 * day and repository, and optionally the subject lines behind them. An upload states a whole day
 * for a whole repository and replaces what was stored, so re-syncing a day that was rebased,
 * amended or squashed corrects it instead of adding to it.
 */

export interface WorkCommit {
  sha: string;
  subject: string;
  insertions: number;
  deletions: number;
  at: number;
  /** Seconds east of UTC where it was authored, so the clock reads as that person's own. */
  offset: number;
}

/** How far the computer that sent this has got through its repositories. */
export interface WorkIndexState {
  done: number;
  total: number;
  complete: boolean;
}

export interface WorkDay {
  day: string;
  repo: string;
  commits: number;
  insertions: number;
  deletions: number;
  /** Absent when the person hasn't turned subject sharing on. */
  subjects?: WorkCommit[];
}

// Generous ceilings that still keep a typo or a broken client off the leaderboard.
const MAX_COMMITS_PER_DAY = 2_000;
const MAX_LINES_PER_DAY = 5_000_000;
const MAX_DAYS = 400;
const MAX_ROWS = 4_000;
const MAX_SUBJECTS = 200;
const MAX_SUBJECT_LENGTH = 200;
const MAX_REPO_LENGTH = 120;
/** "owner/name", as a remote names it. */
const REPO_PATTERN = /^[A-Za-z0-9._-]{1,60}\/[A-Za-z0-9._-]{1,60}$/;
const SHA_PATTERN = /^[0-9a-f]{7,40}$/;

/** Repositories on one computer, bounded the same way the app bounds its own scan. */
const MAX_REPOSITORIES = 1_000;

/**
 * Checks the index state an upload carries. It is optional: an older app sends none, and a batch
 * that isn't the last one of a sync sends none either.
 */
export function parseIndex(raw: unknown): { index?: WorkIndexState } | { error: string } {
  if (raw === undefined || raw === null) return {};
  const state = raw as Record<string, unknown>;
  const { done, total, complete } = state;
  if (!isCount(done, MAX_REPOSITORIES) || !isCount(total, MAX_REPOSITORIES)) {
    return { error: "Index progress must be whole numbers in range." };
  }
  if (typeof complete !== "boolean") return { error: "Index progress needs to say whether it finished." };
  // Finished at nothing is how a scan with no folders reports itself, and it is not progress worth
  // showing; anything past the total is a broken client.
  if (done > total) return { error: "Index progress can't be past its own total." };
  return { index: { done, total, complete } };
}

/** Checks an upload from the app: one entry per day and repository, within the last 400 days. */
export function parseWork(
  body: unknown,
  reference = today(),
): { days: WorkDay[]; index?: WorkIndexState } | { error: string } {
  const list = (body as { days?: unknown } | null)?.days;
  if (!Array.isArray(list)) return { error: "Send { days: [...] }." };
  if (list.length > MAX_ROWS) return { error: "Too many days at once." };
  const earliest = addDays(reference, -MAX_DAYS);
  const latest = addDays(reference, 1);
  const seen = new Set<string>();
  const days: WorkDay[] = [];
  for (const raw of list) {
    const entry = raw as Record<string, unknown>;
    const day = entry?.day;
    const repo = entry?.repo;
    if (typeof day !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(day) || Number.isNaN(Date.parse(`${day}T00:00:00Z`))) {
      return { error: "Each day needs a date like 2026-09-11." };
    }
    if (addDays(day, 0) !== day) return { error: `${day} isn't a real date.` };
    if (day < earliest || day > latest) return { error: `${day} is outside the last ${MAX_DAYS} days.` };
    if (typeof repo !== "string" || repo.length > MAX_REPO_LENGTH || !REPO_PATTERN.test(repo)) {
      return { error: "Each repository needs a name like owner/name." };
    }
    const commits = entry.commits;
    const insertions = entry.insertions;
    const deletions = entry.deletions;
    if (!isCount(commits, MAX_COMMITS_PER_DAY)) return { error: `Commits for ${repo} on ${day} must be a whole number in range.` };
    if (!isCount(insertions, MAX_LINES_PER_DAY) || !isCount(deletions, MAX_LINES_PER_DAY)) {
      return { error: `Lines for ${repo} on ${day} must be whole numbers in range.` };
    }
    const key = `${day}|${repo}`;
    if (seen.has(key)) return { error: `${repo} on ${day} appears twice.` };
    seen.add(key);

    const parsed = parseSubjects(entry.subjects, day, repo);
    if ("error" in parsed) return parsed;
    days.push({ day, repo, commits, insertions, deletions, subjects: parsed.subjects });
  }
  const index = parseIndex((body as { index?: unknown } | null)?.index);
  if ("error" in index) return index;
  return { days, index: index.index };
}

function parseSubjects(raw: unknown, day: string, repo: string): { subjects?: WorkCommit[] } | { error: string } {
  if (raw === undefined || raw === null) return {};
  if (!Array.isArray(raw)) return { error: `Subjects for ${repo} on ${day} must be a list.` };
  if (raw.length > MAX_SUBJECTS) return { error: `Too many subjects for ${repo} on ${day}.` };
  const seen = new Set<string>();
  const subjects: WorkCommit[] = [];
  for (const item of raw) {
    const commit = item as Record<string, unknown>;
    const sha = commit?.sha;
    const subject = commit?.subject;
    if (typeof sha !== "string" || !SHA_PATTERN.test(sha)) return { error: `Each commit for ${repo} on ${day} needs a hash.` };
    if (typeof subject !== "string") return { error: `Each commit for ${repo} on ${day} needs a subject.` };
    if (!isCount(commit.insertions, MAX_LINES_PER_DAY) || !isCount(commit.deletions, MAX_LINES_PER_DAY)) {
      return { error: `Lines for ${sha} must be whole numbers in range.` };
    }
    if (!isCount(commit.at, 2 ** 31)) return { error: `${sha} needs the time it was authored.` };
    const offset = commit.offset ?? 0;
    // Real zones run from -12:00 to +14:00; anything outside that is a broken clock, not a place.
    if (typeof offset !== "number" || !Number.isInteger(offset) || offset < -50400 || offset > 50400) {
      return { error: `${sha} has a time zone that isn't one.` };
    }
    if (seen.has(sha)) return { error: `${sha} appears twice on ${day}.` };
    seen.add(sha);
    // A subject arrives as one line: anything past the first is body text the app shouldn't send.
    const line = subject.split("\n")[0].trim().slice(0, MAX_SUBJECT_LENGTH);
    if (!line) return { error: `${sha} needs a subject.` };
    subjects.push({ sha, subject: line, insertions: commit.insertions, deletions: commit.deletions, at: commit.at, offset });
  }
  return { subjects };
}

function isCount(value: unknown, max: number): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= max;
}

export const work = new Hono<AppEnv>();

/**
 * The app sends what it counted; each day and repository replaces what was there, subjects included.
 * A day that arrives without subjects clears the ones stored for it, which is how turning sharing
 * off takes the words back off the website at the next sync.
 */
work.post("/api/work", apiUser, apiWriter, uploadLimit, async (c) => {
  const parsed = parseWork(await c.req.json().catch(() => null));
  if ("error" in parsed) return c.json(parsed, 400);
  const user = c.get("user")!;
  const at = now();
  const statements: D1PreparedStatement[] = [];
  for (const entry of parsed.days) {
    statements.push(
      c.env.DB.prepare(
        `INSERT INTO daily_work (user_id, day, repo, commits, insertions, deletions, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (user_id, day, repo) DO UPDATE SET commits = excluded.commits, insertions = excluded.insertions,
         deletions = excluded.deletions, updated_at = excluded.updated_at`,
      ).bind(user.id, entry.day, entry.repo, entry.commits, entry.insertions, entry.deletions, at),
    );
    statements.push(
      c.env.DB.prepare("DELETE FROM work_commits WHERE user_id = ? AND day = ? AND repo = ?").bind(user.id, entry.day, entry.repo),
    );
    for (const commit of entry.subjects ?? []) {
      statements.push(
        c.env.DB.prepare(
          `INSERT INTO work_commits (user_id, day, repo, sha, subject, insertions, deletions, at, offset_seconds)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        ).bind(user.id, entry.day, entry.repo, commit.sha, commit.subject, commit.insertions, commit.deletions, commit.at, commit.offset),
      );
    }
  }
  if (parsed.index) {
    const { done, total, complete } = parsed.index;
    statements.push(
      c.env.DB.prepare(
        `INSERT INTO work_index (user_id, done, total, complete, updated_at) VALUES (?, ?, ?, ?, ?)
         ON CONFLICT (user_id) DO UPDATE SET done = excluded.done, total = excluded.total,
         complete = excluded.complete, updated_at = excluded.updated_at`,
      ).bind(user.id, done, total, complete ? 1 : 0, at),
    );
  }
  for (let start = 0; start < statements.length; start += 100) {
    await c.env.DB.batch(statements.slice(start, start + 100));
  }
  return c.json({ saved: parsed.days.length });
});

/** Turning subject sharing off takes the words off the website right away, not at the next sync. */
work.delete("/api/work/subjects", apiUser, apiWriter, async (c) => {
  const user = c.get("user")!;
  await c.env.DB.prepare("DELETE FROM work_commits WHERE user_id = ?").bind(user.id).run();
  return c.json({ cleared: true });
});

export interface DayRepo {
  repo: string;
  commits: number;
  insertions: number;
  deletions: number;
  subjects: WorkCommit[];
}

/**
 * A person whose computer is still working through its repositories.
 *
 * Only ever set from a row refreshed recently: an app that stopped mid-index would otherwise leave
 * its team reading "still indexing" forever, which is its own kind of lie.
 */
export interface Indexing {
  done: number;
  total: number;
}

export interface PersonDay {
  userId: string;
  login: string;
  name: string | null;
  avatarUrl: string | null;
  public: boolean;
  tokens: number;
  costMicros: number;
  requests: number;
  commits: number;
  insertions: number;
  deletions: number;
  repos: DayRepo[];
  /** Set only while this person's figures are still filling in. */
  indexing: Indexing | null;
}

/**
 * One day for one team, as a page can read it: every member, what they spent, what they committed
 * and in which repositories. Members are listed whether or not their profile is public, since
 * joining a team is the agreement to be seen by the rest of it.
 */
export async function teamDay(db: D1Database, teamId: string, day: string): Promise<PersonDay[]> {
  const people = await db
    .prepare(
      `SELECT u.id, u.login, COALESCE(u.display_name, u.name) AS name, u.avatar_url, u.public
       FROM team_members m JOIN users u ON u.id = m.user_id WHERE m.team_id = ?`,
    )
    .bind(teamId)
    .all<{ id: string; login: string; name: string | null; avatar_url: string | null; public: number }>();

  const [usage, repos, subjects, indexes] = await Promise.all([
    db
      .prepare(
        `SELECT d.user_id, SUM(d.tokens) AS tokens, SUM(d.cost_micros) AS cost_micros, SUM(d.requests) AS requests
         FROM daily_usage d WHERE d.day = ? AND d.user_id IN (SELECT user_id FROM team_members WHERE team_id = ?)
         GROUP BY d.user_id`,
      )
      .bind(day, teamId)
      .all<{ user_id: string; tokens: number; cost_micros: number; requests: number }>(),
    db
      .prepare(
        `SELECT w.user_id, w.repo, w.commits, w.insertions, w.deletions FROM daily_work w
         WHERE w.day = ? AND w.user_id IN (SELECT user_id FROM team_members WHERE team_id = ?)
         ORDER BY w.commits DESC, w.repo COLLATE NOCASE`,
      )
      .bind(day, teamId)
      .all<{ user_id: string; repo: string; commits: number; insertions: number; deletions: number }>(),
    db
      .prepare(
        `SELECT c.user_id, c.repo, c.sha, c.subject, c.insertions, c.deletions, c.at, c.offset_seconds FROM work_commits c
         WHERE c.day = ? AND c.user_id IN (SELECT user_id FROM team_members WHERE team_id = ?)
         ORDER BY c.at DESC`,
      )
      .bind(day, teamId)
      .all<{
        user_id: string; repo: string; sha: string; subject: string; insertions: number; deletions: number; at: number;
        offset_seconds: number;
      }>(),
    db
      .prepare(
        `SELECT user_id, done, total FROM work_index
         WHERE complete = 0 AND updated_at >= ? AND user_id IN (SELECT user_id FROM team_members WHERE team_id = ?)`,
      )
      .bind(now() - INDEX_TTL_SECONDS, teamId)
      .all<{ user_id: string; done: number; total: number }>(),
  ]);

  const byPerson = new Map<string, PersonDay>();
  for (const row of people.results) {
    byPerson.set(row.id, {
      userId: row.id,
      login: row.login,
      name: row.name,
      avatarUrl: row.avatar_url,
      public: row.public === 1,
      tokens: 0,
      costMicros: 0,
      requests: 0,
      commits: 0,
      insertions: 0,
      deletions: 0,
      repos: [],
      indexing: null,
    });
  }
  for (const row of indexes.results) {
    const person = byPerson.get(row.user_id);
    if (person && row.total > 0) person.indexing = { done: row.done, total: row.total };
  }
  for (const row of usage.results) {
    const person = byPerson.get(row.user_id);
    if (!person) continue;
    person.tokens = row.tokens;
    person.costMicros = row.cost_micros;
    person.requests = row.requests;
  }
  const repoOf = new Map<string, DayRepo>();
  for (const row of repos.results) {
    const person = byPerson.get(row.user_id);
    if (!person) continue;
    const entry: DayRepo = { repo: row.repo, commits: row.commits, insertions: row.insertions, deletions: row.deletions, subjects: [] };
    person.repos.push(entry);
    person.commits += row.commits;
    person.insertions += row.insertions;
    person.deletions += row.deletions;
    repoOf.set(`${row.user_id}|${row.repo}`, entry);
  }
  for (const row of subjects.results) {
    repoOf.get(`${row.user_id}|${row.repo}`)?.subjects.push({
      sha: row.sha,
      subject: row.subject,
      insertions: row.insertions,
      deletions: row.deletions,
      at: row.at,
      offset: row.offset_seconds,
    });
  }

  // Whoever did something leads, and the rest of the team still appears, so a quiet day reads as a
  // quiet day rather than as a missing person.
  return [...byPerson.values()].sort(
    (a, b) => b.commits - a.commits || b.tokens - a.tokens || a.login.localeCompare(b.login, "en", { sensitivity: "base" }),
  );
}

/** The days a team has anything on, newest first, so the date picker only offers real days. */
export async function teamDays(db: D1Database, teamId: string, limit = 30): Promise<string[]> {
  const { results } = await db
    .prepare(
      `SELECT day FROM (
         SELECT day FROM daily_work WHERE commits > 0 AND user_id IN (SELECT user_id FROM team_members WHERE team_id = ?)
         UNION
         SELECT day FROM daily_usage WHERE tokens > 0 AND user_id IN (SELECT user_id FROM team_members WHERE team_id = ?)
       ) ORDER BY day DESC LIMIT ?`,
    )
    .bind(teamId, teamId, Math.min(Math.max(limit, 1), 90))
    .all<{ day: string }>();
  return results.map((row) => row.day);
}
