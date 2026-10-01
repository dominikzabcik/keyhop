import { Hono } from "hono";
import { deleteCookie, getCookie } from "hono/cookie";
import { SESSION_COOKIE, apiUser, apiWriter, pageUser, publicUser, safeNext, signedInUser } from "./auth";
import { sha256 } from "./crypto";
import type { AppEnv } from "./env";

export const account = new Hono<AppEnv>();

account.get("/api/me", apiUser, (c) => c.json({ user: publicUser(c.get("user")!) }));

account.patch("/api/me", apiUser, apiWriter, async (c) => {
  const body = (await c.req.json().catch(() => null)) as Record<string, unknown> | null;
  if (!body || typeof body !== "object") return c.json({ error: "Send a profile." }, 400);
  const user = c.get("user")!;
  const touches = ["public", "displayName", "bio", "link"].filter((key) => key in body);
  if (touches.length === 0) return c.json({ error: "Send a profile field to change." }, 400);

  let isPublic = user.public === 1;
  let displayName = user.display_name;
  let bio = user.bio;
  let link = user.link;
  if ("public" in body) {
    if (typeof body.public !== "boolean") return c.json({ error: "public must be true or false." }, 400);
    isPublic = body.public;
  }
  if ("displayName" in body) displayName = text(body.displayName, 40);
  if ("bio" in body) bio = text(body.bio, 160);
  if ("link" in body) {
    const raw = body.link;
    if (raw === null || String(raw).trim() === "") link = null;
    else {
      const parsed = webLink(raw);
      if (!parsed) return c.json({ error: "That link isn't a web address." }, 400);
      link = parsed;
    }
  }
  await c.env.DB.prepare("UPDATE users SET public = ?, display_name = ?, bio = ?, link = ? WHERE id = ?")
    .bind(isPublic ? 1 : 0, displayName, bio, link, user.id)
    .run();
  return c.json({ user: publicUser({ ...user, public: isPublic ? 1 : 0, display_name: displayName, bio, link }) });
});

/** Computers linked to this account. The caller is marked so the window can tell itself apart. */
account.get("/api/apps", apiUser, async (c) => {
  const token = c.req.header("authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1] ?? "";
  const hash = await sha256(token);
  const { results } = await c.env.DB.prepare(
    "SELECT id, label, access, last_used_at, token_hash FROM sessions WHERE user_id = ? AND kind = 'app' ORDER BY last_used_at DESC",
  )
    .bind(c.get("user")!.id)
    .all<{ id: string; label: string | null; access: "read" | "write"; last_used_at: number; token_hash: string }>();
  return c.json({
    apps: results.map((app) => ({
      id: app.id,
      label: app.label,
      access: app.access,
      lastUsedAt: new Date(app.last_used_at * 1000).toISOString(),
      current: app.token_hash === hash,
    })),
  });
});

account.post("/api/apps/:id/revoke", apiUser, apiWriter, async (c) => {
  const token = c.req.header("authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1] ?? "";
  const hash = await sha256(token);
  const row = await c.env.DB.prepare("SELECT token_hash FROM sessions WHERE id = ? AND user_id = ? AND kind = 'app'")
    .bind(c.req.param("id"), c.get("user")!.id)
    .first<{ token_hash: string }>();
  if (!row) return c.json({ error: "That linked app is already gone." }, 404);
  await c.env.DB.prepare("DELETE FROM sessions WHERE id = ? AND user_id = ? AND kind = 'app'").bind(c.req.param("id"), c.get("user")!.id).run();
  return c.json({ message: "Unlinked.", current: row.token_hash === hash });
});

/** Deletes the account the same way Settings does on the website: the login has to be typed. */
account.post("/api/account/delete", apiUser, apiWriter, async (c) => {
  const user = c.get("user")!;
  const body = (await c.req.json().catch(() => null)) as { confirm?: unknown } | null;
  if (String(body?.confirm ?? "").trim().toLowerCase() !== user.login.toLowerCase()) {
    return c.json({ error: `Type ${user.login} to delete your account.` }, 400);
  }
  await c.env.DB.prepare("DELETE FROM users WHERE id = ?").bind(user.id).run();
  return c.json({ message: "Your account is deleted.", unlinked: true });
});

/** Signs out whatever is calling: the app unlinks itself, or the browser ends its session. */
account.delete("/api/session", signedInUser, async (c) => {
  const token = c.req.header("authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1] ?? getCookie(c, SESSION_COOKIE);
  if (token) await c.env.DB.prepare("DELETE FROM sessions WHERE token_hash = ?").bind(await sha256(token)).run();
  return c.body(null, 204);
});

account.post("/welcome", pageUser, async (c) => {
  const form = await c.req.parseBody();
  await c.env.DB.prepare("UPDATE users SET public = ? WHERE id = ?").bind(form.public === "on" ? 1 : 0, c.get("user")!.id).run();
  return c.redirect(safeNext(String(form.next ?? "")));
});

/** Keeps a field within its limit, and turns an empty one back into nothing. */
function text(value: unknown, limit: number): string | null {
  const trimmed = String(value ?? "").trim().replace(/\s+/g, " ").slice(0, limit);
  return trimmed.length === 0 ? null : trimmed;
}

/** A link is stored only when it is an ordinary web address. */
export function webLink(value: unknown): string | null {
  const raw = text(value, 200);
  if (!raw) return null;
  const candidate = /^[a-z][a-z0-9+.-]*:/i.test(raw) ? raw : `https://${raw}`;
  try {
    const url = new URL(candidate);
    return url.protocol === "http:" || url.protocol === "https:" ? url.toString() : null;
  } catch {
    return null;
  }
}

account.post("/settings/profile", pageUser, async (c) => {
  const form = await c.req.parseBody();
  const link = webLink(form.link);
  if (form.link && String(form.link).trim() !== "" && link === null) return c.redirect("/settings?error=link");
  await c.env.DB.prepare("UPDATE users SET public = ?, display_name = ?, bio = ?, link = ? WHERE id = ?")
    .bind(form.public === "on" ? 1 : 0, text(form.display_name, 40), text(form.bio, 160), link, c.get("user")!.id)
    .run();
  return c.redirect("/settings?saved=1");
});

account.post("/settings/apps/:id/revoke", pageUser, async (c) => {
  await c.env.DB.prepare("DELETE FROM sessions WHERE id = ? AND user_id = ? AND kind = 'app'").bind(c.req.param("id"), c.get("user")!.id).run();
  return c.redirect("/settings");
});

/** Deletes the account with its usage, app links, memberships and the teams it owns. */
account.post("/settings/delete", pageUser, async (c) => {
  const user = c.get("user")!;
  const form = await c.req.parseBody();
  if (String(form.confirm ?? "").trim().toLowerCase() !== user.login.toLowerCase()) return c.redirect("/settings?error=confirm");
  await c.env.DB.prepare("DELETE FROM users WHERE id = ?").bind(user.id).run();
  deleteCookie(c, SESSION_COOKIE, { path: "/" });
  return c.redirect("/leaderboard");
});
