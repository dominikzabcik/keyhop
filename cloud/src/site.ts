import { Hono } from "hono";
import type { AppEnv } from "./env";
import { currentSeason, seasonList } from "./seasons";

const ORIGIN = "https://keyhop.app";
const PUBLIC_PATHS = ["/", "/download", "/privacy", "/terms", "/security", "/leaderboard", "/season"];

export const site = new Hono<AppEnv>();

site.get("/robots.txt", (c) => {
  const body = [
    "User-agent: *",
    "Allow: /",
    "Disallow: /api/",
    "Disallow: /auth/",
    `Sitemap: ${ORIGIN}/sitemap.xml`,
    "",
  ].join("\n");
  c.header("Cache-Control", "public, max-age=3600");
  return c.text(body);
});

site.get("/sitemap.xml", async (c) => {
  const { results: profiles } = await c.env.DB.prepare("SELECT login FROM users WHERE public = 1 ORDER BY login").all<{ login: string }>();
  const seasons = seasonList()
    .filter((season) => season !== currentSeason())
    .map((season) => `/season/${season}`);
  const profilesPaths = profiles.map((profile) => `/u/${encodeURIComponent(profile.login)}`);
  const urls = [...PUBLIC_PATHS, ...seasons, ...profilesPaths].map((path) => `<url><loc>${ORIGIN}${path}</loc></url>`).join("");
  const body = `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${urls}</urlset>`;
  c.header("Content-Type", "application/xml; charset=UTF-8");
  c.header("Cache-Control", "public, max-age=3600");
  return c.body(body);
});

site.get("/.well-known/security.txt", (c) => {
  const expires = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString();
  const body = [
    "Contact: https://github.com/dominikzabcik/keyhop/security/advisories/new",
    `Expires: ${expires}`,
    "Preferred-Languages: en",
    `Canonical: ${ORIGIN}/.well-known/security.txt`,
    `Policy: ${ORIGIN}/security`,
    "",
  ].join("\n");
  c.header("Content-Type", "text/plain; charset=UTF-8");
  c.header("Cache-Control", "public, max-age=86400");
  return c.body(body);
});
