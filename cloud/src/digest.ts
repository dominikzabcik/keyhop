import { Hono } from "hono";
import { apiUser, apiWriter, pageUser } from "./auth";
import { type AppEnv, today } from "./env";
import { shortTokens } from "./svg";
import { type Team, teamForMember } from "./teams";
import { type PersonDay, teamDay } from "./work";

/**
 * Team digests: once a day, at the hour the owner chose, the team's day goes to a Slack or Discord
 * incoming webhook. The text is what the team day page already shows: who worked, their commits and
 * repositories, and tokens. Nothing a member did not already share with the team.
 */

const ORIGIN = "https://keyhop.app";
const HOSTS = ["hooks.slack.com", "discord.com", "discordapp.com", "canary.discord.com", "ptb.discord.com"];

/** A Slack or Discord incoming webhook, and nothing else: the only places a digest is posted. */
export function digestURL(raw: string): string | null {
  const trimmed = raw.trim();
  if (!trimmed || trimmed.length > 512) return null;
  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    return null;
  }
  if (url.protocol !== "https:" || !HOSTS.includes(url.hostname)) return null;
  if (url.hostname === "hooks.slack.com" && !url.pathname.startsWith("/services/")) return null;
  if (url.hostname !== "hooks.slack.com" && !url.pathname.startsWith("/api/webhooks/")) return null;
  return url.toString();
}

/** The hour, 0 to 23 UTC, or null. */
export function digestHour(raw: unknown): number | null {
  const hour = typeof raw === "string" ? Number.parseInt(raw, 10) : typeof raw === "number" ? raw : Number.NaN;
  return Number.isInteger(hour) && hour >= 0 && hour <= 23 ? hour : null;
}

/** The webhook with its secret hidden, for a settings form that still says where it points. */
export function digestLabel(url: string): string {
  try {
    const parsed = new URL(url);
    const parts = parsed.pathname.split("/");
    parts[parts.length - 1] = "…";
    return `${parsed.hostname}${parts.join("/")}`;
  } catch {
    return "a webhook";
  }
}

/** Which channel a webhook feeds: Slack reads `text` with its own escapes, Discord reads `content` as markdown. */
export function digestKind(url: string): "slack" | "discord" {
  try {
    return new URL(url).hostname === "hooks.slack.com" ? "slack" : "discord";
  } catch {
    return "discord";
  }
}

/** A name as the channel will show it, not as it will read it. */
export function escapeFor(kind: "slack" | "discord", text: string): string {
  return kind === "slack"
    ? text.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
    : text.replace(/([\\*_~`|>#@])/g, "\\$1");
}

/** The day as one message: a headline, then a line per person who did something. */
export function digestText(team: Pick<Team, "slug" | "name">, people: PersonDay[], day: string, kind: "slack" | "discord" = "slack"): string {
  const safe = (text: string) => escapeFor(kind, text);
  const worked = people.filter((person) => person.commits > 0 || person.tokens > 0);
  const commits = people.reduce((sum, person) => sum + person.commits, 0);
  const tokens = people.reduce((sum, person) => sum + person.tokens, 0);
  const repos = new Set(people.flatMap((person) => person.repos.map((repo) => repo.repo)));
  const date = new Date(`${day}T00:00:00Z`).toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric", timeZone: "UTC" });
  const lines = [
    `Keyhop · ${safe(team.name)} · ${date}`,
    `${worked.length} of ${people.length} working, ${commits} ${commits === 1 ? "commit" : "commits"} in ${repos.size} ${repos.size === 1 ? "repository" : "repositories"}, ${shortTokens(tokens)} tokens.`,
  ];
  for (const person of worked) {
    const names = person.repos.filter((repo) => repo.commits > 0).map((repo) => safe(repo.repo.split("/").pop() ?? repo.repo));
    lines.push(`• ${safe(person.name || person.login)}: ${person.commits} ${person.commits === 1 ? "commit" : "commits"}${names.length ? ` (${names.join(", ")})` : ""}, ${shortTokens(person.tokens)} tokens`);
  }
  if (worked.length === 0) lines.push("A quiet day.");
  lines.push(`${ORIGIN}/t/${team.slug}/day`);
  return lines.join("\n");
}

/** Posts one message. Slack reads `text`, Discord reads `content`. */
export async function postDigest(url: string, text: string, send: typeof fetch = fetch): Promise<boolean> {
  const response = await send(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(digestKind(url) === "discord" ? { content: text } : { text }),
  });
  return response.ok;
}

/** Every team whose hour this is, on the hourly trigger. Returns how many were posted. */
export async function sendDigests(db: D1Database, send: typeof fetch = fetch, at = new Date()): Promise<number> {
  const hour = at.getUTCHours();
  const { results } = await db
    .prepare("SELECT id, slug, name, digest_url FROM teams WHERE digest_url IS NOT NULL AND digest_hour = ?")
    .bind(hour)
    .all<{ id: string; slug: string; name: string; digest_url: string }>();
  let posted = 0;
  const day = today();
  for (const team of results) {
    try {
      const people = await teamDay(db, team.id, day);
      if (await postDigest(team.digest_url, digestText(team, people, day, digestKind(team.digest_url)), send)) posted++;
    } catch (error) {
      // One channel's trouble is not another team's.
      console.warn(`Digest for ${team.slug} failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  return posted;
}

export const digests = new Hono<AppEnv>();

async function saveDigest(db: D1Database, teamId: string, url: string | null, hour: number): Promise<void> {
  await db.prepare("UPDATE teams SET digest_url = ?, digest_hour = ? WHERE id = ?").bind(url, hour, teamId).run();
}

/** The team page's form: a webhook and an hour, or an empty field to stop. */
digests.post("/t/:slug/digest", pageUser, async (c) => {
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), c.get("user")!.id);
  if (membership?.role !== "owner") return c.notFound();
  const form = await c.req.parseBody();
  const raw = String(form.url ?? "");
  // The saved webhook is never shown back, so an empty field keeps it and only the hour changes.
  const url = raw.trim() ? digestURL(raw) : membership.team.digest_url;
  const hour = digestHour(String(form.hour ?? "17"));
  if ((raw.trim() && !url) || hour === null) return c.redirect(`/t/${membership.team.slug}?digest=refused`);
  await saveDigest(c.env.DB, membership.team.id, url, hour);
  return c.redirect(`/t/${membership.team.slug}?digest=${url ? "saved" : "off"}`);
});

digests.post("/t/:slug/digest/off", pageUser, async (c) => {
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), c.get("user")!.id);
  if (membership?.role !== "owner") return c.notFound();
  await saveDigest(c.env.DB, membership.team.id, null, membership.team.digest_hour);
  return c.redirect(`/t/${membership.team.slug}?digest=off`);
});

/** Sends today's digest right now, so the owner can see it land. */
digests.post("/t/:slug/digest/send", pageUser, async (c) => {
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), c.get("user")!.id);
  if (membership?.role !== "owner") return c.notFound();
  const row = await c.env.DB.prepare("SELECT digest_url FROM teams WHERE id = ?").bind(membership.team.id).first<{ digest_url: string | null }>();
  if (!row?.digest_url) return c.redirect(`/t/${membership.team.slug}?digest=refused`);
  const people = await teamDay(c.env.DB, membership.team.id, today());
  const ok = await postDigest(row.digest_url, digestText(membership.team, people, today(), digestKind(row.digest_url))).catch(() => false);
  return c.redirect(`/t/${membership.team.slug}?digest=${ok ? "sent" : "failed"}`);
});

/** The same setting for the app. */
digests.post("/api/teams/:slug/digest", apiUser, apiWriter, async (c) => {
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), c.get("user")!.id);
  if (membership?.role !== "owner") return c.json({ error: "Only the owner can set a digest." }, 404);
  const body = (await c.req.json().catch(() => null)) as { url?: unknown; hour?: unknown } | null;
  // A webhook that isn't mentioned stays; an empty string takes it down; anything else must be a webhook.
  const raw = typeof body?.url === "string" ? body.url : null;
  const url = raw === null ? membership.team.digest_url : raw.trim() ? digestURL(raw) : null;
  if (raw !== null && raw.trim() && !url) return c.json({ error: "The digest needs a Slack or Discord incoming webhook URL." }, 400);
  const hour = body?.hour === undefined ? 17 : digestHour(body.hour);
  if (hour === null) return c.json({ error: "The hour must be 0 to 23, in UTC." }, 400);
  await saveDigest(c.env.DB, membership.team.id, url, hour);
  return c.json({ slug: membership.team.slug, digest: url ? { to: digestLabel(url), hour } : null });
});
