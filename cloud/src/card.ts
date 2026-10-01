import { Hono } from "hono";
import { type AppEnv, type User } from "./env";
import { profileBadges } from "./quests";
import { currentSeason, seasonBoard, tierFor } from "./seasons";
import { profile } from "./stats";
import { esc, fit, frame, keyhopMark, MONO, SANS, shortTokens, svgHeaders, svgOpen, themeOf, type Theme } from "./svg";

/**
 * A profile's share card, as one SVG: the sort of thing to drop in a README or a post. It is drawn
 * from the same counts the profile page shows, and only for a profile its owner has made public.
 */

const WIDTH = 880;
const HEIGHT = 260;

const TIER_TONES: Record<Theme["name"], Record<string, string>> = {
  dark: { bronze: "#b09070", silver: "#adadad", gold: "#c2ad84", platinum: "#b0bcbf", diamond: "#c3cdd4", master: "#f2f2f2" },
  light: { bronze: "#8d6a45", silver: "#6a6a6a", gold: "#8a7040", platinum: "#5d6b70", diamond: "#4e5c66", master: "#171717" },
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

function stat(theme: Theme, x: number, label: string, value: string): string {
  return `<text x="${x}" y="196" font-size="13" fill="${theme.muted}" font-family="${SANS}">${label}</text>
    <text x="${x}" y="226" font-size="27" font-weight="620" fill="${theme.text}" font-family="${SANS}">${value}</text>`;
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

  const theme = themeOf(c.req.query("theme"));
  const [stats, season, badges] = await Promise.all([
    profile(c.env.DB, person.id, true),
    seasonBoard(c.env.DB, { season: currentSeason(), metric: "tokens" }),
    profileBadges(c.env.DB, person.id),
  ]);
  const place = season.find((entry) => entry.userId === person.id);
  const tier = tierFor(place?.tokens ?? 0);
  const tone = TIER_TONES[theme.name][tier.key] ?? theme.text;
  const roman = ["", "I", "II", "III"][tier.division ?? 0];
  const name = fit(person.display_name || person.name || person.login, 28);
  const earned = badges.filter((badge) => badge.earned).length;

  const svg = `${svgOpen(WIDTH, HEIGHT, `${name} on Keyhop`)}
  ${frame(WIDTH, HEIGHT, theme)}
  ${keyhopMark(40, 36, 34, theme.mark)}
  <text x="88" y="60" font-size="16" font-weight="620" fill="${theme.text}" font-family="${SANS}">Keyhop</text>
  <text x="${WIDTH - 40}" y="60" text-anchor="end" font-size="13" fill="${theme.faint}" font-family="${MONO}">keyhop.app/u/${esc(person.login)}</text>

  <text x="40" y="122" font-size="34" font-weight="640" fill="${theme.text}" font-family="${SANS}">${esc(name)}</text>
  <text x="40" y="150" font-size="14" fill="${theme.muted}" font-family="${SANS}">@${esc(person.login)}</text>

  ${tierMark(tier.key, WIDTH - 152, 100, tone)}
  <text x="${WIDTH - 40}" y="119" text-anchor="end" font-size="17" font-weight="620" fill="${tone}" font-family="${SANS}">${tier.name}${roman ? ` ${roman}` : ""}</text>
  <text x="${WIDTH - 40}" y="146" text-anchor="end" font-size="13" fill="${theme.muted}" font-family="${SANS}">${place ? `#${place.rank} this season` : "Unranked this season"}</text>

  ${stat(theme, 40, "This season", shortTokens(place?.tokens ?? 0))}
  ${stat(theme, 250, "Streak", `${stats.streak} ${stats.streak === 1 ? "day" : "days"}`)}
  ${stat(theme, 430, "Active days", String(stats.activeDays))}
  ${stat(theme, 630, "Badges", `${earned} of ${badges.length}`)}
</svg>`;

  svgHeaders(c);
  return c.body(svg);
});
