import { Hono } from "hono";
import { apiUser, pageUser } from "./auth";
import { randomToken } from "./crypto";
import { type AppEnv, now } from "./env";
import { type Metric, type Period, isMetric, isPeriod, leaderboard } from "./stats";

export interface Team {
  id: string;
  slug: string;
  name: string;
  owner_id: string;
  created_at: number;
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
      `SELECT t.slug, t.name, m.role, (SELECT COUNT(*) FROM team_members x WHERE x.team_id = t.id) AS members
       FROM team_members m JOIN teams t ON t.id = m.team_id WHERE m.user_id = ? ORDER BY t.name COLLATE NOCASE`,
    )
    .bind(userId)
    .all<{ slug: string; name: string; role: Role; members: number }>();
  return results;
}

export async function teamForMember(db: D1Database, slug: string, userId: string): Promise<{ team: Team; role: Role } | null> {
  const row = await db
    .prepare(
      `SELECT t.id, t.slug, t.name, t.owner_id, t.created_at, m.role FROM teams t
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
      `SELECT u.id, u.login, u.name, u.avatar_url, u.public, m.role, m.joined_at FROM team_members m
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

teams.post("/teams", pageUser, async (c) => {
  const user = c.get("user")!;
  const form = await c.req.parseBody();
  const name = String(form.name ?? "").trim().replace(/\s+/g, " ").slice(0, 40);
  if (name.length < 2) return c.redirect("/teams?error=name");
  const owned = await c.env.DB.prepare("SELECT COUNT(*) AS n FROM teams WHERE owner_id = ?").bind(user.id).first<{ n: number }>();
  if ((owned?.n ?? 0) >= MAX_OWNED_TEAMS) return c.redirect("/teams?error=limit");

  const base = slugify(name);
  let slug = base;
  for (let n = 2; await c.env.DB.prepare("SELECT 1 FROM teams WHERE slug = ?").bind(slug).first(); n++) {
    slug = n <= 50 ? `${base.slice(0, 28)}-${n}` : `${base.slice(0, 20)}-${randomToken(6).toLowerCase().replace(/[^a-z0-9]/g, "")}`;
  }
  const id = crypto.randomUUID();
  const at = now();
  try {
    await c.env.DB.batch([
      c.env.DB.prepare("INSERT INTO teams (id, slug, name, owner_id, created_at) VALUES (?, ?, ?, ?, ?)").bind(id, slug, name, user.id, at),
      c.env.DB.prepare("INSERT INTO team_members (team_id, user_id, role, joined_at) VALUES (?, ?, 'owner', ?)").bind(id, user.id, at),
    ]);
  } catch {
    return c.redirect("/teams?error=taken");
  }
  return c.redirect(`/t/${slug}`);
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

teams.get("/api/teams", apiUser, async (c) => c.json({ teams: await myTeams(c.env.DB, c.get("user")!.id) }));

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
