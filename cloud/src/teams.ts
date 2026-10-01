import { Hono } from "hono";
import { apiUser, apiWriter, pageUser } from "./auth";
import { randomToken } from "./crypto";
import { type AppEnv, addDays, now, today } from "./env";
import { type Metric, type Period, isMetric, isPeriod, leaderboard } from "./stats";
import { presentDay } from "./tasks";
import { teamDay } from "./work";

export interface Team {
  id: string;
  slug: string;
  name: string;
  owner_id: string;
  created_at: number;
  /** 1 once the owner has published README images of the team's totals. */
  public: number;
}
export type Role = "owner" | "member";

const INVITE_SECONDS = 7 * 24 * 3600;
const MAX_MEMBERS = 200;
const MAX_OWNED_TEAMS = 20;

export function slugify(name: string): string {
  const slug = name
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 32)
    .replace(/-+$/, "");
  return slug || "team";
}

export async function myTeams(db: D1Database, userId: string) {
  const { results } = await db
    .prepare(
      `SELECT t.slug, t.name, t.public, m.role, (SELECT COUNT(*) FROM team_members x WHERE x.team_id = t.id) AS members
       FROM team_members m JOIN teams t ON t.id = m.team_id WHERE m.user_id = ? ORDER BY t.name COLLATE NOCASE`,
    )
    .bind(userId)
    .all<{ slug: string; name: string; public: number; role: Role; members: number }>();
  return results;
}

/** A team whose owner published its totals. Missing and unpublished are the same, so a slug is not confirmed. */
export async function publishedTeam(db: D1Database, slug: string) {
  return db
    .prepare(
      `SELECT t.id, t.slug, t.name, (SELECT COUNT(*) FROM team_members m WHERE m.team_id = t.id) AS members
       FROM teams t WHERE t.slug = ? AND t.public = 1`,
    )
    .bind(slug)
    .first<{ id: string; slug: string; name: string; members: number }>();
}

export async function teamForMember(db: D1Database, slug: string, userId: string): Promise<{ team: Team; role: Role } | null> {
  const row = await db
    .prepare(
      `SELECT t.id, t.slug, t.name, t.owner_id, t.created_at, t.public, m.role FROM teams t
       JOIN team_members m ON m.team_id = t.id AND m.user_id = ? WHERE t.slug = ?`,
    )
    .bind(userId, slug)
    .first<Team & { role: Role }>();
  if (!row) return null;
  const { role, ...team } = row;
  return { team, role };
}

export async function members(db: D1Database, teamId: string) {
  const { results } = await db
    .prepare(
      `SELECT u.id, u.login, COALESCE(u.display_name, u.name) AS name, u.avatar_url, u.public, m.role, m.joined_at FROM team_members m
       JOIN users u ON u.id = m.user_id WHERE m.team_id = ? ORDER BY m.role = 'owner' DESC, u.login COLLATE NOCASE`,
    )
    .bind(teamId)
    .all<{ id: string; login: string; name: string | null; avatar_url: string | null; public: number; role: Role; joined_at: number }>();
  return results;
}

export async function inviteInfo(db: D1Database, code: string) {
  return db
    .prepare(
      `SELECT t.id, t.slug, t.name, u.login AS owner, (SELECT COUNT(*) FROM team_members x WHERE x.team_id = t.id) AS members
       FROM team_invites i JOIN teams t ON t.id = i.team_id JOIN users u ON u.id = t.owner_id
       WHERE i.code = ? AND i.revoked = 0 AND i.expires_at > ?`,
    )
    .bind(code, now())
    .first<{ id: string; slug: string; name: string; owner: string; members: number }>();
}

export const teams = new Hono<AppEnv>();

const TEAM_ERRORS = {
  name: "Give the team a name of at least 2 characters.",
  limit: "You own as many teams as Keyhop allows.",
  taken: "That name was just taken. Try another.",
} as const;

/** Creates a team the same way the website form does. */
export async function createTeam(db: D1Database, userId: string, rawName: string): Promise<{ slug: string; name: string } | { error: keyof typeof TEAM_ERRORS }> {
  const name = rawName.trim().replace(/\s+/g, " ").slice(0, 40);
  if (name.length < 2) return { error: "name" };
  const owned = await db.prepare("SELECT COUNT(*) AS n FROM teams WHERE owner_id = ?").bind(userId).first<{ n: number }>();
  if ((owned?.n ?? 0) >= MAX_OWNED_TEAMS) return { error: "limit" };

  const base = slugify(name);
  let slug = base;
  for (let n = 2; await db.prepare("SELECT 1 FROM teams WHERE slug = ?").bind(slug).first(); n++) {
    slug = n <= 50 ? `${base.slice(0, 28)}-${n}` : `${base.slice(0, 20)}-${randomToken(6).toLowerCase().replace(/[^a-z0-9]/g, "")}`;
  }
  const id = crypto.randomUUID();
  const at = now();
  try {
    await db.batch([
      db.prepare("INSERT INTO teams (id, slug, name, owner_id, created_at) VALUES (?, ?, ?, ?, ?)").bind(id, slug, name, userId, at),
      db.prepare("INSERT INTO team_members (team_id, user_id, role, joined_at) VALUES (?, ?, 'owner', ?)").bind(id, userId, at),
    ]);
  } catch {
    return { error: "taken" };
  }
  return { slug, name };
}

teams.post("/teams", pageUser, async (c) => {
  const created = await createTeam(c.env.DB, c.get("user")!.id, String((await c.req.parseBody()).name ?? ""));
  if ("error" in created) return c.redirect(`/teams?error=${created.error}`);
  return c.redirect(`/t/${created.slug}`);
});

teams.post("/t/:slug/invites", pageUser, async (c) => {
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), c.get("user")!.id);
  if (membership?.role !== "owner") return c.notFound();
  const code = randomToken(12);
  await c.env.DB.prepare("INSERT INTO team_invites (code, team_id, created_by, created_at, expires_at) VALUES (?, ?, ?, ?, ?)")
    .bind(code, membership.team.id, c.get("user")!.id, now(), now() + INVITE_SECONDS)
    .run();
  return c.redirect(`/t/${membership.team.slug}?invite=${code}`);
});

teams.post("/t/:slug/invites/revoke", pageUser, async (c) => {
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), c.get("user")!.id);
  if (membership?.role !== "owner") return c.notFound();
  await c.env.DB.prepare("UPDATE team_invites SET revoked = 1 WHERE team_id = ?").bind(membership.team.id).run();
  return c.redirect(`/t/${membership.team.slug}?revoked=1`);
});

teams.post("/invite/:code", pageUser, async (c) => {
  const code = c.req.param("code");
  const info = await inviteInfo(c.env.DB, code);
  if (!info) return c.redirect(`/invite/${encodeURIComponent(code)}`);
  if (info.members >= MAX_MEMBERS) return c.redirect(`/invite/${encodeURIComponent(code)}?error=full`);
  await c.env.DB.prepare("INSERT OR IGNORE INTO team_members (team_id, user_id, role, joined_at) VALUES (?, ?, 'member', ?)")
    .bind(info.id, c.get("user")!.id, now())
    .run();
  return c.redirect(`/t/${info.slug}`);
});

teams.post("/t/:slug/members/:login/remove", pageUser, async (c) => {
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), c.get("user")!.id);
  if (membership?.role !== "owner") return c.notFound();
  await c.env.DB.prepare(
    "DELETE FROM team_members WHERE team_id = ? AND role = 'member' AND user_id = (SELECT id FROM users WHERE login = ? COLLATE NOCASE)",
  )
    .bind(membership.team.id, c.req.param("login"))
    .run();
  return c.redirect(`/t/${membership.team.slug}`);
});

teams.post("/t/:slug/leave", pageUser, async (c) => {
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), c.get("user")!.id);
  if (!membership) return c.notFound();
  // The owner deletes the team instead, so a team is never left without one.
  if (membership.role === "owner") return c.redirect(`/t/${membership.team.slug}`);
  await c.env.DB.prepare("DELETE FROM team_members WHERE team_id = ? AND user_id = ?").bind(membership.team.id, c.get("user")!.id).run();
  return c.redirect("/teams");
});

teams.post("/t/:slug/public", pageUser, async (c) => {
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), c.get("user")!.id);
  if (membership?.role !== "owner") return c.notFound();
  const form = await c.req.parseBody();
  await c.env.DB.prepare("UPDATE teams SET public = ? WHERE id = ?").bind(form.public === "on" ? 1 : 0, membership.team.id).run();
  return c.redirect(`/t/${membership.team.slug}`);
});

teams.post("/t/:slug/delete", pageUser, async (c) => {
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), c.get("user")!.id);
  if (membership?.role !== "owner") return c.notFound();
  const form = await c.req.parseBody();
  if (String(form.confirm ?? "").trim().toLowerCase() !== membership.team.slug.toLowerCase()) {
    return c.redirect(`/t/${membership.team.slug}?error=confirm`);
  }
  await c.env.DB.prepare("DELETE FROM teams WHERE id = ?").bind(membership.team.id).run();
  return c.redirect("/teams");
});

// MARK: JSON for the Keyhop app

teams.get("/api/teams", apiUser, async (c) => {
  const list = await myTeams(c.env.DB, c.get("user")!.id);
  return c.json({ teams: list.map((team) => ({ ...team, public: team.public === 1 })) });
});

teams.get("/api/leaderboard", async (c) => {
  const period: Period = isPeriod(c.req.query("period")) ? (c.req.query("period") as Period) : "week";
  const metric: Metric = isMetric(c.req.query("metric")) ? (c.req.query("metric") as Metric) : "tokens";
  const user = c.get("user");
  let teamId: string | undefined;
  const slug = c.req.query("team");
  if (slug) {
    if (!user) return c.json({ error: "Sign in first." }, 401);
    const membership = await teamForMember(c.env.DB, slug, user.id);
    if (!membership) return c.json({ error: "No such team." }, 404);
    teamId = membership.team.id;
  }
  const entries = await leaderboard(c.env.DB, { period, metric, teamId });
  return c.json({
    period,
    metric,
    entries: entries.map(({ userId, costMicros, ...entry }) => ({ ...entry, cost: costMicros / 1_000_000, isYou: userId === user?.id })),
  });
});

/** The same day `/t/:slug/day` draws, for Keyhop's window. */
teams.get("/api/teams/:slug/day", apiUser, async (c) => {
  const user = c.get("user")!;
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), user.id);
  if (!membership) return c.json({ error: "No such team." }, 404);
  const reference = today();
  const asked = c.req.query("date") ?? "";
  const day = /^\d{4}-\d{2}-\d{2}$/.test(asked) && addDays(asked, 0) === asked && asked <= reference ? asked : reference;
  const people = await teamDay(c.env.DB, membership.team.id, day);
  const following = addDays(day, 1);
  return c.json({
    team: { slug: membership.team.slug, name: membership.team.name },
    day,
    today: reference,
    previous: addDays(day, -1),
    next: following <= reference ? following : null,
    people: presentDay(people, user.id),
  });
});

teams.post("/api/teams", apiUser, apiWriter, async (c) => {
  const body = (await c.req.json().catch(() => null)) as { name?: unknown } | null;
  const created = await createTeam(c.env.DB, c.get("user")!.id, String(body?.name ?? ""));
  if ("error" in created) return c.json({ error: TEAM_ERRORS[created.error] }, 400);
  return c.json({ message: `Created ${created.name}.`, team: { slug: created.slug, name: created.name, role: "owner", members: 1 } });
});

/** The code at the end of an invite link, or the code itself. */
function inviteCode(raw: string): string {
  const trimmed = raw.trim();
  const match = trimmed.match(/invite\/([A-Za-z0-9_-]+)/);
  return (match?.[1] ?? trimmed).slice(0, 64);
}

teams.post("/api/teams/join", apiUser, apiWriter, async (c) => {
  const body = (await c.req.json().catch(() => null)) as { code?: unknown } | null;
  const code = inviteCode(String(body?.code ?? ""));
  const info = await inviteInfo(c.env.DB, code);
  if (!info) return c.json({ error: "That invite expired or was turned off." }, 404);
  if (info.members >= MAX_MEMBERS) return c.json({ error: "This team is full." }, 400);
  await c.env.DB.prepare("INSERT OR IGNORE INTO team_members (team_id, user_id, role, joined_at) VALUES (?, ?, 'member', ?)")
    .bind(info.id, c.get("user")!.id, now())
    .run();
  return c.json({ message: `Joined ${info.name}.`, team: { slug: info.slug, name: info.name } });
});

teams.post("/api/teams/:slug/invites", apiUser, apiWriter, async (c) => {
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), c.get("user")!.id);
  if (membership?.role !== "owner") return c.json({ error: "Only the owner can invite people." }, 404);
  const code = randomToken(12);
  await c.env.DB.prepare("INSERT INTO team_invites (code, team_id, created_by, created_at, expires_at) VALUES (?, ?, ?, ?, ?)")
    .bind(code, membership.team.id, c.get("user")!.id, now(), now() + INVITE_SECONDS)
    .run();
  return c.json({ message: "Invite link is ready.", code, slug: membership.team.slug });
});

teams.post("/api/teams/:slug/invites/revoke", apiUser, apiWriter, async (c) => {
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), c.get("user")!.id);
  if (membership?.role !== "owner") return c.json({ error: "Only the owner can turn invites off." }, 404);
  await c.env.DB.prepare("UPDATE team_invites SET revoked = 1 WHERE team_id = ?").bind(membership.team.id).run();
  return c.json({ message: "Invite links for this team stopped working." });
});

teams.post("/api/teams/:slug/leave", apiUser, apiWriter, async (c) => {
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), c.get("user")!.id);
  if (!membership) return c.json({ error: "You aren't in that team." }, 404);
  if (membership.role === "owner") return c.json({ error: "The owner deletes the team instead of leaving it." }, 400);
  await c.env.DB.prepare("DELETE FROM team_members WHERE team_id = ? AND user_id = ?").bind(membership.team.id, c.get("user")!.id).run();
  return c.json({ message: `Left ${membership.team.name}.` });
});

/** Who is on a team, so the window can show the same list as `/t/:slug`. */
teams.get("/api/teams/:slug", apiUser, async (c) => {
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), c.get("user")!.id);
  if (!membership) return c.json({ error: "No such team." }, 404);
  const people = await members(c.env.DB, membership.team.id);
  return c.json({
    slug: membership.team.slug,
    name: membership.team.name,
    role: membership.role,
    public: membership.team.public === 1,
    members: people.map((person) => ({ login: person.login, name: person.name, role: person.role })),
  });
});

teams.post("/api/teams/:slug/public", apiUser, apiWriter, async (c) => {
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), c.get("user")!.id);
  if (membership?.role !== "owner") return c.json({ error: "Only the owner can publish this team." }, 404);
  const body = (await c.req.json().catch(() => null)) as { public?: unknown } | null;
  if (typeof body?.public !== "boolean") return c.json({ error: "public must be true or false." }, 400);
  await c.env.DB.prepare("UPDATE teams SET public = ? WHERE id = ?").bind(body.public ? 1 : 0, membership.team.id).run();
  return c.json({ slug: membership.team.slug, public: body.public });
});

teams.post("/api/teams/:slug/members/:login/remove", apiUser, apiWriter, async (c) => {
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), c.get("user")!.id);
  if (membership?.role !== "owner") return c.json({ error: "Only the owner can remove someone." }, 404);
  const login = c.req.param("login");
  const result = await c.env.DB.prepare(
    "DELETE FROM team_members WHERE team_id = ? AND role = 'member' AND user_id = (SELECT id FROM users WHERE login = ? COLLATE NOCASE)",
  )
    .bind(membership.team.id, login)
    .run();
  if ((result.meta.changes ?? 0) === 0) return c.json({ error: "That person isn't a member of this team." }, 404);
  return c.json({ message: `Removed @${login}.` });
});

teams.post("/api/teams/:slug/delete", apiUser, apiWriter, async (c) => {
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), c.get("user")!.id);
  if (membership?.role !== "owner") return c.json({ error: "Only the owner can delete this team." }, 404);
  const body = (await c.req.json().catch(() => null)) as { confirm?: unknown } | null;
  if (String(body?.confirm ?? "").trim().toLowerCase() !== membership.team.slug.toLowerCase()) {
    return c.json({ error: `Type ${membership.team.slug} to delete this team.` }, 400);
  }
  await c.env.DB.prepare("DELETE FROM teams WHERE id = ?").bind(membership.team.id).run();
  return c.json({ message: `Deleted ${membership.team.name}.` });
});
