import { Hono, type Context, type MiddlewareHandler } from "hono";
import { deleteCookie, getCookie, setCookie } from "hono/cookie";
import { randomToken, sha256, userCode } from "./crypto";
import { type AppEnv, type Env, type User, now } from "./env";

export const SESSION_COOKIE = "keyhop_session";
const OAUTH_COOKIE = "keyhop_oauth";
const WEB_SESSION_SECONDS = 30 * 24 * 3600;
const LINK_SECONDS = 10 * 60;

const USER_COLUMNS = "u.id, u.github_id, u.login, u.name, u.avatar_url, u.public, u.created_at";

/** Reads who is signed in: a session cookie in the browser, or a bearer token from the Keyhop app. */
export const session: MiddlewareHandler<AppEnv> = async (c, next) => {
  c.set("user", null);
  c.set("sessionKind", null);
  const bearer = c.req.header("authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1];
  const token = bearer ?? getCookie(c, SESSION_COOKIE);
  if (token) {
    const kind = bearer ? "app" : "web";
    const hash = await sha256(token);
    const row = await c.env.DB.prepare(
      `SELECT ${USER_COLUMNS}, s.kind AS session_kind, s.expires_at, s.last_used_at
       FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?`,
    )
      .bind(hash)
      .first<User & { session_kind: string; expires_at: number | null; last_used_at: number }>();
    if (row && row.session_kind === kind && (row.expires_at === null || row.expires_at > now())) {
      const { session_kind, expires_at, last_used_at, ...user } = row;
      c.set("user", user);
      c.set("sessionKind", kind);
      if (now() - last_used_at > 3600) {
        await c.env.DB.prepare("UPDATE sessions SET last_used_at = ? WHERE token_hash = ?").bind(now(), hash).run();
      }
    }
  }
  await next();
};

/**
 * Changes made with a session cookie must come from Keyhop's own pages. SameSite=Lax already keeps
 * the cookie off cross-site form posts; this refuses anything else that slips through.
 */
export const sameOrigin: MiddlewareHandler<AppEnv> = async (c, next) => {
  const reads = c.req.method === "GET" || c.req.method === "HEAD" || c.req.method === "OPTIONS";
  if (!reads && !c.req.header("authorization") && getCookie(c, SESSION_COOKIE)) {
    if (c.req.header("origin") !== new URL(c.req.url).origin) return c.text("Cross-site request refused.", 403);
  }
  await next();
};

export const apiUser: MiddlewareHandler<AppEnv> = async (c, next) => {
  if (!c.get("user")) return c.json({ error: "Sign in first." }, 401);
  await next();
};

export const pageUser: MiddlewareHandler<AppEnv> = async (c, next) => {
  if (!c.get("user")) {
    const url = new URL(c.req.url);
    return c.redirect(`/login?next=${encodeURIComponent(url.pathname + url.search)}`);
  }
  await next();
};

/** Only same-site paths, so a login link can't send someone elsewhere afterwards. */
export function safeNext(value: string | undefined | null): string {
  if (!value || !value.startsWith("/") || value.startsWith("//") || value.includes("\\")) return "/leaderboard";
  return value;
}

function isLocal(c: Context<AppEnv>): boolean {
  const host = new URL(c.req.url).hostname;
  return host === "localhost" || host === "127.0.0.1";
}

export async function startWebSession(c: Context<AppEnv>, userId: string): Promise<void> {
  const token = randomToken();
  const at = now();
  await c.env.DB.prepare(
    "INSERT INTO sessions (id, token_hash, user_id, kind, created_at, last_used_at, expires_at) VALUES (?, ?, ?, 'web', ?, ?, ?)",
  )
    .bind(crypto.randomUUID(), await sha256(token), userId, at, at, at + WEB_SESSION_SECONDS)
    .run();
  setCookie(c, SESSION_COOKIE, token, {
    httpOnly: true,
    secure: new URL(c.req.url).protocol === "https:",
    sameSite: "Lax",
    path: "/",
    maxAge: WEB_SESSION_SECONDS,
  });
}

export interface GitHubProfile {
  id: number;
  login: string;
  name?: string | null;
  avatar_url?: string | null;
}

/** Creates or refreshes the person behind a GitHub account. */
export async function upsertUser(db: D1Database, profile: GitHubProfile): Promise<{ user: User; created: boolean }> {
  const at = now();
  const existing = await db.prepare("SELECT id FROM users WHERE github_id = ?").bind(profile.id).first<{ id: string }>();
  // GitHub logins can be renamed and reused. Whoever held this one before keeps a unique name.
  await db
    .prepare("UPDATE users SET login = login || '-' || github_id WHERE login = ? COLLATE NOCASE AND github_id != ?")
    .bind(profile.login, profile.id)
    .run();
  if (existing) {
    await db
      .prepare("UPDATE users SET login = ?, name = ?, avatar_url = ?, updated_at = ? WHERE id = ?")
      .bind(profile.login, profile.name ?? null, profile.avatar_url ?? null, at, existing.id)
      .run();
  } else {
    await db
      .prepare("INSERT INTO users (id, github_id, login, name, avatar_url, public, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 0, ?, ?)")
      .bind(crypto.randomUUID(), profile.id, profile.login, profile.name ?? null, profile.avatar_url ?? null, at, at)
      .run();
  }
  const user = await db.prepare(`SELECT ${USER_COLUMNS} FROM users u WHERE u.github_id = ?`).bind(profile.id).first<User>();
  return { user: user!, created: !existing };
}

export const auth = new Hono<AppEnv>();

auth.get("/auth/github", (c) => {
  const state = randomToken(16);
  const next = safeNext(c.req.query("next"));
  setCookie(c, OAUTH_COOKIE, `${state}|${encodeURIComponent(next)}`, {
    httpOnly: true,
    secure: new URL(c.req.url).protocol === "https:",
    sameSite: "Lax",
    path: "/auth",
    maxAge: 600,
  });
  const origin = new URL(c.req.url).origin;
  const params = new URLSearchParams({
    client_id: c.env.GITHUB_CLIENT_ID,
    redirect_uri: `${origin}/auth/github/callback`,
    state,
    allow_signup: "true",
  });
  return c.redirect(`https://github.com/login/oauth/authorize?${params}`);
});

auth.get("/auth/github/callback", async (c) => {
  const saved = getCookie(c, OAUTH_COOKIE) ?? "";
  deleteCookie(c, OAUTH_COOKIE, { path: "/auth" });
  const [state, encodedNext] = saved.split("|");
  const code = c.req.query("code");
  if (!state || state !== c.req.query("state") || !code) {
    return c.text("That sign-in expired. Go back and sign in again.", 400);
  }
  const origin = new URL(c.req.url).origin;
  const exchange = await fetch("https://github.com/login/oauth/access_token", {
    method: "POST",
    headers: { accept: "application/json", "content-type": "application/json" },
    body: JSON.stringify({
      client_id: c.env.GITHUB_CLIENT_ID,
      client_secret: c.env.GITHUB_CLIENT_SECRET,
      code,
      redirect_uri: `${origin}/auth/github/callback`,
    }),
  });
  const grant = (await exchange.json().catch(() => ({}))) as { access_token?: string };
  if (!grant.access_token) return c.text("GitHub didn't confirm the sign-in. Try again.", 502);

  const response = await fetch("https://api.github.com/user", {
    headers: { authorization: `Bearer ${grant.access_token}`, accept: "application/vnd.github+json", "user-agent": "keyhop-cloud" },
  });
  if (!response.ok) return c.text("Couldn't read your GitHub profile. Try again.", 502);
  const { user, created } = await upsertUser(c.env.DB, (await response.json()) as GitHubProfile);
  await startWebSession(c, user.id);
  const next = safeNext(decodeURIComponent(encodedNext ?? ""));
  return c.redirect(created ? `/welcome?next=${encodeURIComponent(next)}` : next);
});

/** Local development and tests only: signs in as a made-up GitHub account. */
auth.get("/auth/dev", async (c) => {
  if (c.env.DEV_LOGIN !== "true" || !isLocal(c)) return c.notFound();
  const login = (c.req.query("login") ?? "dev").replace(/[^A-Za-z0-9-]/g, "").slice(0, 39) || "dev";
  let id = 0;
  for (const char of login.toLowerCase()) id = (id * 31 + char.charCodeAt(0)) % 1_000_000_000;
  const { user } = await upsertUser(c.env.DB, { id: id + 1, login, name: login, avatar_url: null });
  await startWebSession(c, user.id);
  return c.redirect(safeNext(c.req.query("next")));
});

auth.post("/auth/logout", async (c) => {
  const token = getCookie(c, SESSION_COOKIE);
  if (token) await c.env.DB.prepare("DELETE FROM sessions WHERE token_hash = ?").bind(await sha256(token)).run();
  deleteCookie(c, SESSION_COOKIE, { path: "/" });
  return c.redirect("/leaderboard");
});

// MARK: Linking the Keyhop app

auth.post("/api/device/start", async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as { label?: unknown };
  const label = typeof body.label === "string" ? body.label.trim().slice(0, 60) : "";
  const deviceCode = randomToken();
  const at = now();
  await c.env.DB.prepare("DELETE FROM device_links WHERE expires_at < ?").bind(at).run();
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = userCode();
    const inserted = await c.env.DB.prepare(
      "INSERT OR IGNORE INTO device_links (device_hash, user_code, label, created_at, expires_at) VALUES (?, ?, ?, ?, ?)",
    )
      .bind(await sha256(deviceCode), code, label || null, at, at + LINK_SECONDS)
      .run();
    if (inserted.meta.changes === 1) {
      const origin = new URL(c.req.url).origin;
      return c.json({ deviceCode, userCode: code, verifyUrl: `${origin}/link?code=${code}`, interval: 3, expiresIn: LINK_SECONDS });
    }
  }
  return c.json({ error: "Couldn't start linking. Try again." }, 503);
});

auth.post("/api/device/token", async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as { deviceCode?: unknown };
  if (typeof body.deviceCode !== "string") return c.json({ error: "expired" }, 410);
  const hash = await sha256(body.deviceCode);
  const link = await c.env.DB.prepare("SELECT user_id, label, expires_at FROM device_links WHERE device_hash = ?")
    .bind(hash)
    .first<{ user_id: string | null; label: string | null; expires_at: number }>();
  if (!link || link.expires_at < now()) return c.json({ error: "expired" }, 410);
  if (!link.user_id) return c.json({ error: "pending" }, 428);

  const token = randomToken();
  const at = now();
  await c.env.DB.batch([
    c.env.DB.prepare(
      "INSERT INTO sessions (id, token_hash, user_id, kind, label, created_at, last_used_at) VALUES (?, ?, ?, 'app', ?, ?, ?)",
    ).bind(crypto.randomUUID(), await sha256(token), link.user_id, link.label, at, at),
    c.env.DB.prepare("DELETE FROM device_links WHERE device_hash = ?").bind(hash),
  ]);
  const user = await c.env.DB.prepare(`SELECT ${USER_COLUMNS} FROM users u WHERE u.id = ?`).bind(link.user_id).first<User>();
  return c.json({ token, user: publicUser(user!) });
});

auth.post("/link", pageUser, async (c) => {
  const form = await c.req.parseBody();
  const code = String(form.code ?? "").trim().toUpperCase();
  const link = await c.env.DB.prepare("SELECT device_hash FROM device_links WHERE user_code = ? AND user_id IS NULL AND expires_at > ?")
    .bind(code, now())
    .first<{ device_hash: string }>();
  if (!link) return c.redirect(`/link?code=${encodeURIComponent(code)}&error=expired`);
  await c.env.DB.prepare("UPDATE device_links SET user_id = ? WHERE device_hash = ?").bind(c.get("user")!.id, link.device_hash).run();
  return c.redirect("/link?done=1");
});

export function publicUser(user: User) {
  return { login: user.login, name: user.name, avatarUrl: user.avatar_url, public: user.public === 1 };
}

export type { Env };
