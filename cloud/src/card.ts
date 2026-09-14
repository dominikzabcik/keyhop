import { Hono } from "hono";
import { type AppEnv, type User } from "./env";
import { profileBadges } from "./quests";
import { currentSeason, seasonBoard, tierFor } from "./seasons";
import { profile } from "./stats";

/**
 * A profile's share card, as one SVG: the sort of thing to drop in a README or a post. It is drawn
 * from the same counts the profile page shows, and only for a profile its owner has made public.
 */

const WIDTH = 880;
const HEIGHT = 260;

/** Everything written into the card is escaped: a name or bio is someone else's text. */
function esc(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

/** Keeps a line short enough to fit, with an ellipsis when it does not. */
function fit(value: string, characters: number): string {
  return value.length <= characters ? value : `${value.slice(0, characters - 1).trimEnd()}…`;
}

function short(tokens: number): string {
  if (tokens >= 1_000_000_000) return `${(tokens / 1_000_000_000).toFixed(tokens >= 10_000_000_000 ? 0 : 1)}B`;
  if (tokens >= 1_000_000) return `${(tokens / 1_000_000).toFixed(tokens >= 10_000_000 ? 0 : 1)}M`;
  if (tokens >= 1_000) return `${Math.round(tokens / 1000)}K`;
  return String(tokens);
}

const TIER_TONES: Record<string, string> = {
  bronze: "#b09070",
  silver: "#adadad",
  gold: "#c2ad84",
  platinum: "#b0bcbf",
  diamond: "#c3cdd4",
  master: "#f2f2f2",
};

const TIER_STEPS: Record<string, number> = { bronze: 1, silver: 2, gold: 3, platinum: 4, diamond: 5, master: 6 };

/** The same climbing squares the site uses for a tier. */
function tierMark(key: string, x: number, y: number, tone: string): string {
  const lit = TIER_STEPS[key] ?? 1;
  return Array.from({ length: 6 }, (_, index) => {
    const height = 4 + index * 3;
    return `<rect x="${x + index * 7}" y="${y + (22 - height)}" width="5" height="${height}" rx="1.5" fill="${tone}" fill-opacity="${index < lit ? 1 : 0.22}"/>`;
  }).join("");
}

/** Keyhop's mark, on the card's own scale. */
function keyhopMark(x: number, y: number, size: number): string {
  const unit = size / 24;
  const square = (left: number, top: number, width: number, height: number) =>
    `<rect x="${x + left * unit}" y="${y + top * unit}" width="${width * unit}" height="${height * unit}" rx="${1.5 * unit}" fill="#EBEBEB"/>`;
  return square(2.5, 2.5, 6, 19.5) + square(9.6, 9.2, 6, 6) + square(16, 1, 6, 6) + square(16, 17, 6, 6);
}

function stat(x: number, label: string, value: string): string {
  return `<text x="${x}" y="196" font-size="13" fill="#8a8a8a" font-family="system-ui, -apple-system, Segoe UI, Roboto, sans-serif">${esc(label)}</text>
    <text x="${x}" y="226" font-size="27" font-weight="620" fill="#EBEBEB" font-family="system-ui, -apple-system, Segoe UI, Roboto, sans-serif">${esc(value)}</text>`;
}

export const card = new Hono<AppEnv>();

card.get("/u/:login/card.svg", async (c) => {
  const login = c.req.param("login");
  const person = await c.env.DB.prepare(
    "SELECT id, github_id, login, name, display_name, bio, link, avatar_url, public, created_at FROM users WHERE login = ? COLLATE NOCASE",
  )
    .bind(login)
    .first<User>();
  // A card is a thing people share, so it exists only for a profile that is already public.
  if (!person || person.public !== 1) return c.notFound();

  const [stats, season, badges] = await Promise.all([
    profile(c.env.DB, person.id, true),
    seasonBoard(c.env.DB, { season: currentSeason(), metric: "tokens" }),
    profileBadges(c.env.DB, person.id),
  ]);
  const place = season.find((entry) => entry.userId === person.id);
  const tier = tierFor(place?.tokens ?? 0);
  const tone = TIER_TONES[tier.key] ?? "#EBEBEB";
  const roman = ["", "I", "II", "III"][tier.division ?? 0];
  const name = fit(person.display_name || person.name || person.login, 28);
  const earned = badges.filter((badge) => badge.earned).length;

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${WIDTH}" height="${HEIGHT}" viewBox="0 0 ${WIDTH} ${HEIGHT}" role="img" aria-label="${esc(name)} on Keyhop">
  <rect width="${WIDTH}" height="${HEIGHT}" rx="18" fill="#171717"/>
  <rect x="0.5" y="0.5" width="${WIDTH - 1}" height="${HEIGHT - 1}" rx="17.5" fill="none" stroke="#ffffff" stroke-opacity="0.08"/>
  ${keyhopMark(40, 36, 34)}
  <text x="88" y="60" font-size="16" font-weight="620" fill="#EBEBEB" font-family="system-ui, -apple-system, Segoe UI, Roboto, sans-serif">Keyhop</text>
  <text x="${WIDTH - 40}" y="60" text-anchor="end" font-size="13" fill="#6f6f6f" font-family="ui-monospace, SFMono-Regular, Menlo, monospace">keyhop.app/u/${esc(person.login)}</text>

  <text x="40" y="122" font-size="34" font-weight="640" fill="#EBEBEB" font-family="system-ui, -apple-system, Segoe UI, Roboto, sans-serif">${esc(name)}</text>
  <text x="40" y="150" font-size="14" fill="#8a8a8a" font-family="system-ui, -apple-system, Segoe UI, Roboto, sans-serif">@${esc(person.login)}</text>

  ${tierMark(tier.key, WIDTH - 152, 100, tone)}
  <text x="${WIDTH - 40}" y="119" text-anchor="end" font-size="17" font-weight="620" fill="${tone}" font-family="system-ui, -apple-system, Segoe UI, Roboto, sans-serif">${esc(tier.name)}${roman ? ` ${roman}` : ""}</text>
  <text x="${WIDTH - 40}" y="146" text-anchor="end" font-size="13" fill="#8a8a8a" font-family="system-ui, -apple-system, Segoe UI, Roboto, sans-serif">${place ? `#${place.rank} this season` : "Unranked this season"}</text>

  ${stat(40, "This season", short(place?.tokens ?? 0))}
  ${stat(250, "Streak", `${stats.streak} ${stats.streak === 1 ? "day" : "days"}`)}
  ${stat(430, "Active days", String(stats.activeDays))}
  ${stat(630, "Badges", `${earned} of ${badges.length}`)}
</svg>`;

  c.header("Content-Type", "image/svg+xml; charset=utf-8");
  // Long enough to spare the database on a busy README, short enough to follow a day's usage.
  c.header("Cache-Control", "public, max-age=900");
  return c.body(svg);
});
