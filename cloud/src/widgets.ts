import { Hono } from "hono";
import { type AppEnv, TOOL_NAMES, addDays, shownTools, today } from "./env";
import { currentSeason, seasonBoard, seasonRange, tierFor, tierLabel } from "./seasons";
import { type Period, type Subject, type WindowTotals, activity, dailyTokens, leaderboard, summed } from "./stats";
import { dollars, esc, fit, frame, grouped, keyhopMark, MONO, SANS, shortTokens, svgHeaders, svgOpen, themeOf, type Theme } from "./svg";
import { publishedTeam } from "./teams";
import { yearSquares, yearStart } from "./ui";

/**
 * README images besides the profile card and the pet: a small badge, a streak, a tool mix, and a year of days.
 * A team gets the same set once its owner publishes it. Rank and tier stay on a person, because
 * a season ladder is one account, not a sum of them.
 */

const BADGE_PERIODS = ["today", "week", "month", "all", "season"] as const;
type BadgePeriod = (typeof BADGE_PERIODS)[number];

const PERSON_METRICS = ["tokens", "cost", "requests", "commits", "lines", "streak", "rank", "tier"] as const;
type PersonMetric = (typeof PERSON_METRICS)[number];

const TEAM_METRICS = ["tokens", "cost", "requests", "commits", "lines", "streak"] as const;
type TeamMetric = (typeof TEAM_METRICS)[number];

const PERIOD_SHORT: Record<BadgePeriod, string> = {
  today: "today",
  week: "7d",
  month: "30d",
  all: "all",
  season: "season",
};

const MEASURE_LABEL: Record<"tokens" | "cost" | "requests" | "commits" | "lines", string> = {
  tokens: "tokens",
  cost: "api value",
  requests: "requests",
  commits: "commits",
  lines: "lines",
};

export const PERSON_WIDGETS = [
  ["Badge", "badge.svg"],
  ["Card", "card.svg"],
  ["Streak", "streak.svg"],
  ["Tools", "tools.svg"],
  ["Year", "graph.svg"],
  ["Pet", "pet.svg"],
] as const;

export const TEAM_WIDGETS = [
  ["Badge", "badge.svg"],
  ["Card", "card.svg"],
  ["Streak", "streak.svg"],
  ["Tools", "tools.svg"],
  ["Year", "graph.svg"],
] as const;

export function widgetMarkdown(page: string, file: string, label: string): string {
  return `[![${label}](${page}/${file})](${page})`;
}

function listed<T extends string>(value: string | undefined, allowed: readonly T[], fallback: T): T | null {
  if (value === undefined || value === "") return fallback;
  return (allowed as readonly string[]).includes(value) ? (value as T) : null;
}

function bounds(period: BadgePeriod, reference = today()): { from: string; until: string } {
  if (period === "season") {
    const range = seasonRange(currentSeason(reference), reference);
    return { from: range.from, until: range.to };
  }
  if (period === "all") return { from: "0000-00-00", until: reference };
  const days = period === "today" ? 1 : period === "week" ? 7 : 30;
  return { from: addDays(reference, -(days - 1)), until: reference };
}

function days(count: number): string {
  return `${count} ${count === 1 ? "day" : "days"}`;
}

function measure(metric: keyof typeof MEASURE_LABEL, totals: WindowTotals): string {
  if (metric === "tokens") return shortTokens(totals.tokens);
  if (metric === "cost") return dollars(totals.costMicros);
  if (metric === "requests") return grouped(totals.requests);
  if (metric === "commits") return grouped(totals.commits);
  return grouped(totals.insertions + totals.deletions);
}

async function figure(
  db: D1Database,
  who: Subject,
  metric: PersonMetric,
  period: BadgePeriod,
  userId?: string,
): Promise<{ label: string; value: string; aria: string }> {
  const span = PERIOD_SHORT[period];
  if (metric === "streak") {
    const lived = await activity(db, who);
    const value = days(lived.streak);
    return { label: "streak", value, aria: `${value} streak on Keyhop` };
  }
  if (metric === "tier") {
    const season = bounds("season");
    const totals = await summed(db, who, season.from, season.until);
    const value = tierLabel(tierFor(totals.tokens));
    return { label: "tier", value, aria: `${value} this season on Keyhop` };
  }
  if (metric === "rank" && userId) {
    const rank = await rankOf(db, userId, period);
    const value = rank ? `#${rank}` : "unranked";
    return { label: `rank · ${span}`, value, aria: `${value} by tokens, ${span}, on Keyhop` };
  }
  const totals = await summed(db, who, bounds(period).from, bounds(period).until);
  const name = MEASURE_LABEL[metric as keyof typeof MEASURE_LABEL];
  const value = measure(metric as keyof typeof MEASURE_LABEL, totals);
  return { label: `${name} · ${span}`, value, aria: `${value} ${name}, ${span}, on Keyhop` };
}

async function rankOf(db: D1Database, userId: string, period: BadgePeriod): Promise<number | null> {
  if (period === "season") {
    const board = await seasonBoard(db, { season: currentSeason(), metric: "tokens" });
    return board.find((entry) => entry.userId === userId)?.rank ?? null;
  }
  const board = await leaderboard(db, { period: period as Period, metric: "tokens" });
  return board.find((entry) => entry.userId === userId)?.rank ?? null;
}

function badgeImage(theme: Theme, label: string, value: string, aria: string): string {
  const labelWidth = Math.max(64, Math.ceil(label.length * 7.1) + 20);
  const valueWidth = Math.max(44, Math.ceil(value.length * 7.4) + 20);
  const width = labelWidth + valueWidth;
  const height = 28;
  const labelFill = theme.name === "dark" ? "#2c2c2c" : "#171717";
  return `${svgOpen(width, height, aria)}
  <rect width="${width}" height="${height}" rx="6" fill="${theme.bg}" stroke="${theme.stroke}" stroke-opacity="${theme.strokeOpacity}"/>
  <rect width="${labelWidth}" height="${height}" rx="6" fill="${labelFill}"/>
  <rect x="${labelWidth - 6}" width="6" height="${height}" fill="${labelFill}"/>
  <text x="${labelWidth / 2}" y="18" text-anchor="middle" font-size="12" font-weight="600" fill="#EBEBEB" font-family="${SANS}">${esc(label)}</text>
  <text x="${labelWidth + valueWidth / 2}" y="18" text-anchor="middle" font-size="12" font-weight="620" fill="${theme.text}" font-family="${SANS}">${esc(value)}</text>
</svg>`;
}

function stat(theme: Theme, x: number, y: number, label: string, value: string): string {
  return `<text x="${x}" y="${y}" font-size="13" fill="${theme.muted}" font-family="${SANS}">${esc(label)}</text>
    <text x="${x}" y="${y + 30}" font-size="27" font-weight="620" fill="${theme.text}" font-family="${SANS}">${esc(value)}</text>`;
}

function header(theme: Theme, width: number, path: string): string {
  return `${keyhopMark(40, 32, 28, theme.mark)}
  <text x="78" y="52" font-size="16" font-weight="620" fill="${theme.text}" font-family="${SANS}">Keyhop</text>
  <text x="${width - 40}" y="52" text-anchor="end" font-size="13" fill="${theme.faint}" font-family="${MONO}">keyhop.app/${esc(path)}</text>`;
}

function streakImage(theme: Theme, title: string, subtitle: string, path: string, streak: number, longest: number, activeDays: number): string {
  const width = 880;
  const height = 230;
  return `${svgOpen(width, height, `${title} on Keyhop`)}
  ${frame(width, height, theme)}
  ${header(theme, width, path)}
  <text x="40" y="112" font-size="32" font-weight="640" fill="${theme.text}" font-family="${SANS}">${esc(fit(title, 32))}</text>
  <text x="40" y="140" font-size="14" fill="${theme.muted}" font-family="${SANS}">${esc(subtitle)}</text>
  ${stat(theme, 40, 178, "Streak", days(streak))}
  ${stat(theme, 280, 178, "Longest", days(longest))}
  ${stat(theme, 540, 178, "Active days", grouped(activeDays))}
</svg>`;
}

function toolsImage(theme: Theme, title: string, path: string, period: BadgePeriod, tools: WindowTotals["tools"]): string {
  const width = 880;
  const row = 36;
  const shown = shownTools(tools);
  const height = 148 + shown.length * row;
  const max = Math.max(...shown.map((tool) => tools[tool]), 1);
  const bars = shown.map((tool, index) => {
    const y = 136 + index * row;
    const widthOf = tools[tool] > 0 ? Math.max(4, (tools[tool] / max) * 360) : 0;
    return `<text x="40" y="${y + 16}" font-size="15" fill="${theme.text}" font-family="${SANS}">${esc(TOOL_NAMES[tool])}</text>
      <rect x="200" y="${y + 4}" width="360" height="12" rx="3" fill="${theme.text}" fill-opacity="0.08"/>
      <rect x="200" y="${y + 4}" width="${widthOf.toFixed(1)}" height="12" rx="3" fill="${theme.text}"/>
      <text x="${width - 40}" y="${y + 16}" text-anchor="end" font-size="15" fill="${theme.muted}" font-family="${SANS}">${esc(shortTokens(tools[tool]))}</text>`;
  }).join("");
  const span = period === "today" ? "Today" : period === "week" ? "7 days" : period === "month" ? "30 days" : period === "all" ? "All time" : "This season";
  return `${svgOpen(width, height, `${title} tools on Keyhop`)}
  ${frame(width, height, theme)}
  ${header(theme, width, path)}
  <text x="40" y="100" font-size="28" font-weight="640" fill="${theme.text}" font-family="${SANS}">${esc(fit(title, 32))}</text>
  <text x="40" y="124" font-size="14" fill="${theme.muted}" font-family="${SANS}">${esc(span)}</text>
  ${bars}
</svg>`;
}

/** Five steps from an empty day to the heaviest, painted so a light page and a dark page both read. */
const YEAR_FILLS: Record<Theme["name"], [string, string, string, string, string]> = {
  dark: ["#232323", "#414141", "#6b6b6b", "#a2a2a2", "#e8e8e8"],
  light: ["#e7e7e7", "#cacaca", "#999999", "#5d5d5d", "#1e1e1e"],
};

const WEEKDAYS = ["Mon", "Wed", "Fri"];

function graphImage(theme: Theme, title: string, path: string, days: { day: string; tokens: number }[], reference: string): string {
  const width = 880;
  const height = 320;
  const cell = 11;
  const step = 14;
  const gridX = 72;
  const gridY = 168;
  const { squares, months, total } = yearSquares(days, reference);
  const fills = YEAR_FILLS[theme.name];
  const shown = `${shortTokens(total)} tokens in the last year`;
  const cells = squares
    .map(
      (square) =>
        `<rect x="${gridX + square.column * step}" y="${gridY + square.row * step}" width="${cell}" height="${cell}" rx="2" fill="${fills[square.level]}"><title>${square.day}: ${shortTokens(square.tokens)} tokens</title></rect>`,
    )
    .join("");
  const monthLabels = months
    .map(
      (month) =>
        `<text x="${gridX + month.column * step}" y="${gridY - 8}" font-size="11" fill="${theme.faint}" font-family="${MONO}">${month.label}</text>`,
    )
    .join("");
  const weekdayLabels = WEEKDAYS.map(
    (label, index) =>
      `<text x="40" y="${gridY + index * 2 * step + 9}" font-size="10" fill="${theme.faint}" font-family="${MONO}">${label}</text>`,
  ).join("");
  const legendX = 78;
  const legend = fills
    .map((fill, index) => `<rect x="${legendX + index * 16}" y="286" width="11" height="11" rx="2" fill="${fill}"/>`)
    .join("");
  return `${svgOpen(width, height, `${title}, ${shown}`)}
  ${frame(width, height, theme)}
  ${header(theme, width, path)}
  <text x="40" y="104" font-size="22" font-weight="640" fill="${theme.text}" font-family="${SANS}">${esc(fit(title, 36))}</text>
  <text x="40" y="130" font-size="14" fill="${theme.muted}" font-family="${SANS}">${esc(shown)}</text>
  ${weekdayLabels}
  ${monthLabels}
  ${cells}
  <text x="40" y="296" font-size="11" fill="${theme.faint}" font-family="${SANS}">Less</text>
  ${legend}
  <text x="${legendX + fills.length * 16 + 4}" y="296" font-size="11" fill="${theme.faint}" font-family="${SANS}">More</text>
</svg>`;
}

function teamCardImage(theme: Theme, name: string, slug: string, members: number, seasonTokens: number, streak: number, activeDays: number): string {
  const width = 880;
  const height = 250;
  return `${svgOpen(width, height, `${name} on Keyhop`)}
  ${frame(width, height, theme)}
  ${header(theme, width, `t/${slug}`)}
  <text x="40" y="118" font-size="34" font-weight="640" fill="${theme.text}" font-family="${SANS}">${esc(fit(name, 28))}</text>
  <text x="40" y="146" font-size="14" fill="${theme.muted}" font-family="${SANS}">${esc(`${members} ${members === 1 ? "member" : "members"}`)}</text>
  ${stat(theme, 40, 186, "This season", shortTokens(seasonTokens))}
  ${stat(theme, 250, 186, "Streak", days(streak))}
  ${stat(theme, 460, 186, "Active days", grouped(activeDays))}
  ${stat(theme, 680, 186, "Members", String(members))}
</svg>`;
}

async function publicPerson(db: D1Database, login: string) {
  const person = await db
    .prepare("SELECT id, login, name, display_name, public FROM users WHERE login = ? COLLATE NOCASE")
    .bind(login)
    .first<{ id: string; login: string; name: string | null; display_name: string | null; public: number }>();
  return person?.public === 1 ? person : null;
}

export const widgets = new Hono<AppEnv>();

widgets.get("/u/:login/badge.svg", async (c) => {
  const person = await publicPerson(c.env.DB, c.req.param("login"));
  if (!person) return c.notFound();
  const metric = listed(c.req.query("metric"), PERSON_METRICS, "tokens");
  const period = listed(c.req.query("period"), BADGE_PERIODS, "week");
  if (!metric || !period) return c.notFound();
  const drawn = await figure(c.env.DB, { userId: person.id }, metric, period, person.id);
  svgHeaders(c);
  return c.body(badgeImage(themeOf(c.req.query("theme")), drawn.label, drawn.value, drawn.aria));
});

widgets.get("/u/:login/streak.svg", async (c) => {
  const person = await publicPerson(c.env.DB, c.req.param("login"));
  if (!person) return c.notFound();
  const lived = await activity(c.env.DB, { userId: person.id });
  const name = person.display_name || person.name || person.login;
  svgHeaders(c);
  return c.body(streakImage(themeOf(c.req.query("theme")), name, `@${person.login}`, `u/${person.login}`, lived.streak, lived.longest, lived.activeDays));
});

widgets.get("/u/:login/tools.svg", async (c) => {
  const person = await publicPerson(c.env.DB, c.req.param("login"));
  if (!person) return c.notFound();
  const period = listed(c.req.query("period"), BADGE_PERIODS, "month");
  if (!period) return c.notFound();
  const totals = await summed(c.env.DB, { userId: person.id }, bounds(period).from, bounds(period).until);
  const name = person.display_name || person.name || person.login;
  svgHeaders(c);
  return c.body(toolsImage(themeOf(c.req.query("theme")), name, `u/${person.login}`, period, totals.tools));
});

widgets.get("/u/:login/graph.svg", async (c) => {
  const person = await publicPerson(c.env.DB, c.req.param("login"));
  if (!person) return c.notFound();
  const reference = today();
  const days = await dailyTokens(c.env.DB, { userId: person.id }, yearStart(reference), reference);
  const name = person.display_name || person.name || person.login;
  svgHeaders(c);
  return c.body(graphImage(themeOf(c.req.query("theme")), name, `u/${person.login}`, days, reference));
});

widgets.get("/t/:slug/badge.svg", async (c) => {
  const team = await publishedTeam(c.env.DB, c.req.param("slug"));
  if (!team) return c.notFound();
  const metric = listed(c.req.query("metric"), TEAM_METRICS, "tokens");
  const period = listed(c.req.query("period"), BADGE_PERIODS, "week");
  if (!metric || !period) return c.notFound();
  const drawn = await figure(c.env.DB, { teamId: team.id }, metric, period);
  svgHeaders(c);
  return c.body(badgeImage(themeOf(c.req.query("theme")), drawn.label, drawn.value, drawn.aria));
});

widgets.get("/t/:slug/streak.svg", async (c) => {
  const team = await publishedTeam(c.env.DB, c.req.param("slug"));
  if (!team) return c.notFound();
  const lived = await activity(c.env.DB, { teamId: team.id });
  svgHeaders(c);
  return c.body(
    streakImage(themeOf(c.req.query("theme")), team.name, `${team.members} ${team.members === 1 ? "member" : "members"}`, `t/${team.slug}`, lived.streak, lived.longest, lived.activeDays),
  );
});

widgets.get("/t/:slug/tools.svg", async (c) => {
  const team = await publishedTeam(c.env.DB, c.req.param("slug"));
  if (!team) return c.notFound();
  const period = listed(c.req.query("period"), BADGE_PERIODS, "month");
  if (!period) return c.notFound();
  const totals = await summed(c.env.DB, { teamId: team.id }, bounds(period).from, bounds(period).until);
  svgHeaders(c);
  return c.body(toolsImage(themeOf(c.req.query("theme")), team.name, `t/${team.slug}`, period, totals.tools));
});

widgets.get("/t/:slug/graph.svg", async (c) => {
  const team = await publishedTeam(c.env.DB, c.req.param("slug"));
  if (!team) return c.notFound();
  const reference = today();
  const days = await dailyTokens(c.env.DB, { teamId: team.id }, yearStart(reference), reference);
  svgHeaders(c);
  return c.body(graphImage(themeOf(c.req.query("theme")), team.name, `t/${team.slug}`, days, reference));
});

widgets.get("/t/:slug/card.svg", async (c) => {
  const team = await publishedTeam(c.env.DB, c.req.param("slug"));
  if (!team) return c.notFound();
  const season = bounds("season");
  const [totals, lived] = await Promise.all([
    summed(c.env.DB, { teamId: team.id }, season.from, season.until),
    activity(c.env.DB, { teamId: team.id }),
  ]);
  svgHeaders(c);
  return c.body(teamCardImage(themeOf(c.req.query("theme")), team.name, team.slug, team.members, totals.tokens, lived.streak, lived.activeDays));
});
