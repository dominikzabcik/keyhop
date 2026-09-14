import { Hono } from "hono";
import { deleteCookie, getCookie } from "hono/cookie";
import { SESSION_COOKIE, apiUser, apiWriter, pageUser, publicUser, safeNext, signedInUser } from "./auth";
import { sha256 } from "./crypto";
import type { AppEnv } from "./env";

export const account = new Hono<AppEnv>();

account.get("/api/me", apiUser, (c) => c.json({ user: publicUser(c.get("user")!) }));

account.patch("/api/me", apiUser, apiWriter, async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as { public?: unknown };
  if (typeof body.public !== "boolean") return c.json({ error: "Send { public: true } or { public: false }." }, 400);
  await c.env.DB.prepare("UPDATE users SET public = ? WHERE id = ?").bind(body.public ? 1 : 0, c.get("user")!.id).run();
  return c.json({ user: publicUser({ ...c.get("user")!, public: body.public ? 1 : 0 }) });
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
