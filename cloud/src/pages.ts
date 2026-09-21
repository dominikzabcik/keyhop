import { type Context, Hono } from "hono";
import { html, raw } from "hono/html";
import { pageUser, safeNext } from "./auth";
import { type AppEnv, type User, addDays, now, today } from "./env";
import { LANDING_CSS, landingPage } from "./landing";
import { downloadPage, privacyPage, securityPage, termsPage } from "./marketing";
import { profileBadges, questsFor } from "./quests";
import { TIERS, currentSeason, daysLeft, isSeason, nextStep, seasonBoard, seasonLabel, seasonList, seasonRange, tierFor } from "./seasons";
import { type Entry, type Metric, type Period, METRICS, PERIODS, isMetric, isPeriod, leaderboard, profile } from "./stats";
import { inviteInfo, members, myTeams, teamForMember } from "./teams";
import { parseSubject, span, tasksForDay } from "./tasks";
import { type DayRepo, type PersonDay, teamDay } from "./work";
import {
  type Html,
  PIXEL_MARK,
  ago,
  avatar,
  badgeMark,
  count,
  diffStat,
  githubIcon,
  heatmap,
  layout,
  legend,
  metricValue,
  mixBar,
  monthYear,
  tierTag,
  tokens,
  toolRows,
  usd,
} from "./ui";

type C = Context<AppEnv>;

export const pages = new Hono<AppEnv>();

function render(
  c: C,
  title: string,
  body: Html,
  options: {
    description?: string;
    active?: "leaderboard" | "teams" | "season" | "download";
    mode?: "app" | "landing" | "marketing";
    index?: boolean;
    softwareSchema?: boolean;
    canonicalPath?: string;
    css?: string;
    status?: 200 | 404;
  } = {},
) {
  const url = new URL(c.req.url);
  if (options.index === false) c.header("X-Robots-Tag", "noindex, nofollow");
  return c.html(
    layout({
      title,
      description: options.description,
      path: url.pathname + url.search,
      user: c.get("user"),
      active: options.active,
      mode: options.mode,
      index: options.index,
      softwareSchema: options.softwareSchema,
      canonicalPath: options.canonicalPath,
      css: options.css,
      body,
      nonce: c.get("nonce"),
    }),
    options.status ?? 200,
  );
}

export function notFound(c: C, message = "There's nothing here.") {
  return render(
    c,
    "Not found · Keyhop",
    html`<section class="card center-card">${raw(PIXEL_MARK)}<h1>Not found</h1><p class="lede">${message}</p><a class="btn secondary" href="/leaderboard">Go to the leaderboard</a></section>`,
    { status: 404, index: false },
  );
}

const PERIOD_PHRASES: Record<Period, string> = {
  today: "today",
  week: "over the last 7 days",
  month: "over the last 30 days",
  all: "of all time",
};

function readChoice(c: C): { period: Period; metric: Metric } {
  const period = c.req.query("period");
  const metric = c.req.query("metric");
  return { period: isPeriod(period) ? period : "week", metric: isMetric(metric) ? metric : "tokens" };
}

function controls(base: string, period: Period, metric: Metric): Html {
  const link = (p: Period, m: Metric) => `${base}?period=${p}&metric=${m}`;
  const on = (yes: boolean) => (yes ? raw('aria-current="true"') : "");
  return html`<div class="toolbar">
    <nav class="tabs" aria-label="Period">${(Object.keys(PERIODS) as Period[]).map((p) => html`<a href="${link(p, metric)}" ${on(p === period)}>${PERIODS[p].label}</a>`)}</nav>
    <nav class="tabs" aria-label="Measure">${(Object.keys(METRICS) as Metric[]).map((m) => html`<a href="${link(period, m)}" ${on(m === metric)}>${METRICS[m].label}</a>`)}</nav>
  </div>`;
}

type Person = Pick<Entry, "userId" | "login" | "name" | "avatarUrl" | "public">;

function personCell(entry: Person, viewer: User | null, size: number): Html {
  const inner = html`${avatar(entry, size)}<span><b>${entry.name || entry.login}</b><small>@${entry.login}</small></span>`;
  // Team boards can list private profiles; those stay unlinked for everyone but their owner.
  return entry.public || viewer?.id === entry.userId
    ? html`<a class="person" href="/u/${entry.login}">${inner}</a>`
    : html`<span class="person">${inner}</span>`;
}

function board(entries: Entry[], metric: Metric, viewer: User | null, emptyText: string): Html {
  if (entries.length === 0) return html`<div class="card empty">${emptyText}</div>`;
  return html`
    <section class="podium" aria-label="Top three">
      ${entries.slice(0, 3).map(
        (entry) => html`<div class="card place-card ${entry.rank === 1 ? "first" : ""}">
          <span class="place">#${entry.rank}</span>
          ${personCell(entry, viewer, 40)}
          <span class="value">${metricValue(entry, metric)}</span>
          ${mixBar(entry.tools)}
        </div>`,
      )}
    </section>
    <div class="card"><div class="table-wrap"><table class="table">
      <thead><tr><th class="rank">#</th><th>Person</th><th class="hide-sm">Tools</th><th class="num hide-sm">Active days</th>
        <th class="num">${METRICS[metric].label}</th></tr></thead>
      <tbody>${entries.map(
        (entry) => html`<tr class="${viewer?.id === entry.userId ? "me" : ""}">
          <td class="rank">${entry.rank}</td>
          <td><div style="display:flex;align-items:center">${personCell(entry, viewer, 28)}${viewer?.id === entry.userId ? html`<span class="badge you">You</span>` : ""}</div></td>
          <td class="hide-sm">${mixBar(entry.tools)}</td>
          <td class="num hide-sm">${entry.activeDays}</td>
          <td class="num strong">${metricValue(entry, metric)}</td>
        </tr>`,
      )}</tbody>
    </table></div></div>
    ${legend()}`;
}

pages.get("/", (c) =>
  render(c, "Keyhop · Switch AI coding accounts without breaking flow", landingPage(), {
    description: "Switch Claude Code, Cursor, Codex, Gemini CLI, OpenCode, Pi, Copilot, Windsurf and Codebuff accounts, watch limits and track exact local usage.",
    mode: "landing",
    softwareSchema: true,
    css: LANDING_CSS,
  }),
);

pages.get("/download", (c) =>
  render(c, "Download Keyhop for macOS, Linux and Windows", downloadPage(), {
    description: "Download Keyhop for macOS, Linux or Windows and switch nine AI coding tools without breaking flow.",
    mode: "marketing",
    active: "download",
    softwareSchema: true,
  }),
);

pages.get("/privacy", (c) =>
  render(c, "Privacy · Keyhop", privacyPage(), {
    description: "How Keyhop stores provider credentials, reads local usage and handles optional cloud leaderboard data.",
    mode: "marketing",
  }),
);

pages.get("/terms", (c) =>
  render(c, "Use and trademarks · Keyhop", termsPage(), {
    description: "Responsible use, software license, cloud service terms and third-party trademarks for Keyhop.",
    mode: "marketing",
  }),
);

pages.get("/security", (c) =>
  render(c, "Security · Keyhop", securityPage(), {
    description: "Keyhop's security model, release verification and private vulnerability reporting channel.",
    mode: "marketing",
  }),
);

pages.get("/login", (c) => {
  const next = safeNext(c.req.query("next"));
  if (c.get("user")) return c.redirect(next);
  return render(
    c,
    "Sign in · Keyhop",
    html`<section class="card center-card">
      ${raw(PIXEL_MARK)}
      <h1>Sign in to Keyhop</h1>
      <p class="lede">Use your GitHub account. Keyhop reads only your public GitHub profile: your name, login and avatar.</p>
      <a class="btn" href="/auth/github?next=${encodeURIComponent(next)}">${githubIcon()}Continue with GitHub</a>
    </section>`,
    { index: false },
  );
});

pages.get("/welcome", pageUser, (c) => {
  const user = c.get("user")!;
  const next = safeNext(c.req.query("next"));
  return render(
    c,
    "Welcome · Keyhop",
    html`<section class="card center-card">
      ${avatar(user, 56)}
      <h1>Welcome, ${user.name || user.login}</h1>
      <p class="lede">Link the Keyhop app to send your daily totals: open Keyhop, then Settings, then Leaderboard.</p>
      <form class="form" method="post" action="/welcome">
        <input type="hidden" name="next" value="${next}">
        <label class="check"><input type="checkbox" name="public">
          <span>Show me on the global leaderboard<small>Anyone can then see your profile at /u/${user.login}. Teams you join always see your totals.</small></span></label>
        <button class="btn" type="submit">Continue</button>
      </form>
    </section>`,
    { index: false },
  );
});

pages.get("/leaderboard", async (c) => {
  const { period, metric } = readChoice(c);
  const user = c.get("user");
  const entries = await leaderboard(c.env.DB, { period, metric });
  return render(
    c,
    "Leaderboard · Keyhop",
    html`
      <div class="head">
        <div><h1>Leaderboard</h1><p class="lede">Ranked by ${METRICS[metric].label.toLowerCase()} ${PERIOD_PHRASES[period]}.</p></div>
        ${controls("/leaderboard", period, metric)}
      </div>
      ${user && !user.public
        ? html`<div class="notice"><div><b>You aren't on the leaderboard</b><p>Your profile is private. Turn it public in <a href="/settings">Settings</a> to join.</p></div></div>`
        : ""}
      ${board(entries, metric, user, "No usage yet for this period. Link a computer running Keyhop and yours shows up here.")}`,
    { active: "leaderboard", description: `Who used the most AI ${PERIOD_PHRASES[period]}, on Keyhop.` },
  );
});

/** One month of ranked play. Past seasons are counted the same way, so they never go stale. */
async function seasonPage(c: C, season: string) {
  const viewer = c.get("user");
  const [board, goals] = await Promise.all([
    seasonBoard(c.env.DB, { season, metric: "tokens" }),
    viewer ? questsFor(c.env.DB, viewer.id) : Promise.resolve(null),
  ]);
  const mine = viewer ? board.find((entry) => entry.userId === viewer.id) : undefined;
  const range = seasonRange(season);
  const left = daysLeft(season);
  const step = nextStep(mine?.tokens ?? 0);
  const recent = seasonList().slice(0, 6);
  const when = range.over ? "Finished" : left === 1 ? "Ends today" : `${left} days left`;

  return render(
    c,
    `Season ${seasonLabel(season)} · Keyhop`,
    html`
      <div class="head">
        <div><h1>Season</h1><p class="lede">${seasonLabel(season)} · ${when}. Your tier comes from the tokens you use this month.</p></div>
        ${recent.length > 1
          ? html`<nav class="tabs" aria-label="Season">${recent.map(
              (id) => html`<a href="${id === currentSeason() ? "/season" : `/season/${id}`}" ${id === season ? raw('aria-current="true"') : ""}>${seasonLabel(id).replace(" ", " ")}</a>`,
            )}</nav>`
          : ""}
      </div>
      ${viewer
        ? html`<section class="card season-head">
            ${tierTag(tierFor(mine?.tokens ?? 0), "lg")}
            <div class="grow">
              <b>${mine ? `#${mine.rank} of ${board.length}` : "Unranked"}</b>
              <p class="next">${mine
                ? step
                  ? `${tokens(step.tokens)} more tokens for ${step.label}.`
                  : "You're at the top of the ladder."
                : viewer.public === 1
                  ? "Sync some usage this month to take a place."
                  : "Turn your profile public in Settings to join the season."}</p>
            </div>
            <span class="mono muted">${tokens(mine?.tokens ?? 0)} this season</span>
          </section>`
        : html`<section class="card season-intro">
            <p>A season runs for one calendar month. Keyhop on your computer sends how many tokens
            each tool used that day, and your tier follows the total. Nothing about what you asked
            or wrote is sent.</p>
            <div class="row-actions">
              <a class="btn sm" href="/login">Sign in with GitHub</a>
              <a class="btn sm ghost" href="/download">Get Keyhop first</a>
            </div>
          </section>`}
      ${goals
        ? html`<section class="card">
            <div class="card-head"><h2>Quests</h2><span class="hint">Today and this week</span></div>
            ${goals.map(
              (goal) => html`<div class="quest-row ${goal.complete ? "done" : ""}">
                <div><b>${goal.name}</b><p>${goal.note}</p></div>
                <div>
                  <div class="quest-track"><span style="width:${Math.round((goal.done / goal.target) * 100)}%"></span></div>
                  <div class="quest-state">${goal.complete ? "Done" : goal.target <= 7 ? `${goal.done} of ${goal.target}` : `${Math.round((goal.done / goal.target) * 100)}%`}</div>
                </div>
              </div>`,
            )}
          </section>`
        : ""}
      ${board.length === 0
        ? html`<div class="card empty">No usage yet this season. Link a computer running Keyhop and yours shows up here.</div>`
        : html`<div class="card"><div class="table-wrap"><table class="table">
            <thead><tr><th class="rank">#</th><th>Person</th><th>Tier</th><th class="hide-sm">Tools</th>
              <th class="num hide-sm">Active days</th><th class="num">Tokens</th></tr></thead>
            <tbody>${board.map(
              (entry) => html`<tr class="${viewer?.id === entry.userId ? "me" : ""}">
                <td class="rank">${entry.rank}</td>
                <td><div style="display:flex;align-items:center">${personCell(entry, viewer, 28)}${viewer?.id === entry.userId ? html`<span class="badge you">You</span>` : ""}</div></td>
                <td>${tierTag(entry.tier)}</td>
                <td class="hide-sm">${mixBar(entry.tools)}</td>
                <td class="num hide-sm">${entry.activeDays}</td>
                <td class="num strong">${tokens(entry.tokens)}</td>
              </tr>`,
            )}</tbody>
          </table></div></div>`}
      <section class="card">
        <div class="card-head"><h2>The ladder</h2><span class="hint">Tokens in one season</span></div>
        <div class="ladder">${TIERS.map(
          (tier) => html`<div class="ladder-row ${tierFor(mine?.tokens ?? 0).key === tier.key && mine ? "here" : ""}">
            ${tierTag({ key: tier.key, name: tier.name, division: null })}
            <span class="at">${tier.at === 0 ? "from the first token" : `from ${tokens(tier.at)}`}</span>
          </div>`,
        )}</div>
      </section>`,
    {
      active: "season",
      description: `Keyhop's ${seasonLabel(season)} season: counted usage across Claude Code, Cursor, Codex, Gemini CLI, OpenCode and Pi.`,
    },
  );
}

pages.get("/season", (c) => seasonPage(c, currentSeason()));

pages.get("/season/:id", (c) => {
  const id = c.req.param("id");
  if (!isSeason(id)) return notFound(c, "That season hasn't run.");
  if (id === currentSeason()) return c.redirect("/season");
  return seasonPage(c, id);
});

pages.get("/u/:login", async (c) => {
  const login = c.req.param("login");
  const person = await c.env.DB.prepare("SELECT id, github_id, login, name, display_name, bio, link, avatar_url, public, created_at FROM users WHERE login = ? COLLATE NOCASE")
    .bind(login)
    .first<User>();
  const viewer = c.get("user");
  const isSelf = !!person && viewer?.id === person.id;
  if (!person || (person.public !== 1 && !isSelf)) return notFound(c, "This profile is private, or doesn't exist.");
  if (person.login !== login) return c.redirect(`/u/${person.login}`, 301);

  const [stats, season, badges] = await Promise.all([
    profile(c.env.DB, person.id, person.public === 1),
    seasonBoard(c.env.DB, { season: currentSeason(), metric: "tokens" }),
    profileBadges(c.env.DB, person.id),
  ]);
  const earned = badges.filter((entry) => entry.earned);
  const place = season.find((entry) => entry.userId === person.id);
  const url = `${new URL(c.req.url).origin}/u/${person.login}`;
  const display = person.display_name || person.name || person.login;
  const days = (n: number) => `${n} ${n === 1 ? "day" : "days"}`;
  return render(
    c,
    `${display} · Keyhop`,
    html`
      <section class="card profile-head">
        ${avatar(person, 64)}
        <div class="grow">
          <h1>${display}</h1>
          <p class="lede">@${person.login} · on Keyhop since ${monthYear(person.created_at)}${person.public !== 1 ? html` · <span class="badge">Private</span>` : ""}</p>
          ${person.bio ? html`<p class="bio">${person.bio}</p>` : ""}
          ${person.link ? html`<p class="bio"><a class="profile-link" href="${person.link}" rel="nofollow noopener ugc" target="_blank">${person.link.replace(/^https?:\/\//, "").replace(/\/$/, "")}</a></p>` : ""}
        </div>
        ${person.public === 1 ? html`<label class="share">Share this profile<input class="field mono" readonly value="${url}"></label>` : ""}
      </section>
      <section class="card season-head">
        ${tierTag(tierFor(place?.tokens ?? 0), "lg")}
        <div class="grow">
          <b><a href="/season" style="text-decoration:none">${seasonLabel(currentSeason())} season</a></b>
          <p class="next">${place ? `#${place.rank} of ${season.length}, with ${tokens(place.tokens)} tokens.` : "Not ranked this season yet."}</p>
        </div>
      </section>
      <section class="card">
        <div class="card-head"><h2>Badges</h2><span class="hint">${earned.length} of ${badges.length}</span></div>
        <div class="badges">${badges.map(
          (entry) => html`<div class="badge-row ${entry.earned ? "" : "locked"}">
            ${badgeMark(entry.key)}
            <span><b>${entry.name}</b><small>${entry.earned && entry.day ? `Earned ${entry.day}` : entry.note}</small></span>
          </div>`,
        )}</div>
      </section>
      <section class="stats">
        <div class="card stat"><div class="label">Tokens, 30 days</div><div class="value">${tokens(stats.month.tokens)}</div><div class="foot">${count(stats.month.requests)} requests</div></div>
        <div class="card stat"><div class="label">API value, 30 days</div><div class="value">${usd(stats.month.costMicros)}</div><div class="foot">At standard API prices</div></div>
        <div class="card stat"><div class="label">Streak</div><div class="value">${days(stats.streak)}</div><div class="foot">Longest ${days(stats.longestStreak)}</div></div>
        <div class="card stat"><div class="label">This week</div><div class="value">${stats.weekRank ? `#${stats.weekRank}` : "Unranked"}</div><div class="foot">${person.public === 1 ? "On the global leaderboard" : "Private profiles aren't ranked"}</div></div>
      </section>
      <section class="card">
        <div class="card-head"><h2>Activity</h2><span class="hint">Last 12 months</span></div>
        <div class="card-body table-wrap">${heatmap(stats.days, today())}</div>
      </section>
      <section class="split">
        <div class="card"><div class="card-head"><h2>Tools</h2><span class="hint">Last 30 days</span></div><div class="card-body">${toolRows(stats.month)}</div></div>
        <div class="card"><div class="card-head"><h2>All time</h2></div><div class="card-body kv">
          <span>Tokens</span><span class="mono">${tokens(stats.allTime.tokens)}</span>
          <span>API value</span><span class="mono">${usd(stats.allTime.costMicros)}</span>
          <span>Requests</span><span class="mono">${count(stats.allTime.requests)}</span>
          <span>Active days</span><span class="mono">${count(stats.activeDays)}</span>
        </div></div>
      </section>`,
    {
      description: `${display} used ${tokens(stats.month.tokens)} tokens in the last 30 days. See their Keyhop profile.`,
      index: person.public === 1,
      canonicalPath: `/u/${person.login}`,
    },
  );
});

pages.get("/teams", pageUser, async (c) => {
  const user = c.get("user")!;
  const list = await myTeams(c.env.DB, user.id);
  const error = c.req.query("error");
  const errors: Record<string, string> = {
    name: "Give the team a name of at least 2 characters.",
    limit: "You own as many teams as Keyhop allows.",
    taken: "That name was just taken. Try another.",
  };
  return render(
    c,
    "Teams · Keyhop",
    html`
      <div class="head"><div><h1>Teams</h1><p class="lede">Compare usage with the people you work with. Members see each other's daily totals.</p></div></div>
      <section class="aside-layout">
        <div class="card">
          <div class="card-head"><h2>Your teams</h2><span class="hint">${list.length}</span></div>
          ${list.length === 0
            ? html`<p class="empty">You aren't on a team yet. Create one, or open an invite link from a teammate.</p>`
            : list.map(
                (team) => html`<a class="list-row" href="/t/${team.slug}" style="text-decoration:none">
                  <span class="person"><span><b>${team.name}</b><small>${team.members} ${team.members === 1 ? "member" : "members"}</small></span></span>
                  ${team.role === "owner" ? html`<span class="badge">Owner</span>` : ""}
                </a>`,
              )}
        </div>
        <div class="card">
          <div class="card-head"><h2>Create a team</h2></div>
          <form class="form card-body" method="post" action="/teams">
            <label>Name<input class="field" name="name" maxlength="40" required placeholder="Studio" autocomplete="off"></label>
            ${error && errors[error] ? html`<p class="error-text">${errors[error]}</p>` : ""}
            <button class="btn" type="submit">Create team</button>
          </form>
        </div>
      </section>`,
    { active: "teams", index: false },
  );
});

pages.get("/t/:slug", pageUser, async (c) => {
  const user = c.get("user")!;
  const membership = await teamForMember(c.env.DB, c.req.param("slug"), user.id);
  if (!membership) return notFound(c, "This team doesn't exist, or you aren't in it.");
  const { team, role } = membership;
  const { period, metric } = readChoice(c);
  const [entries, people] = await Promise.all([leaderboard(c.env.DB, { period, metric, teamId: team.id }), members(c.env.DB, team.id)]);
  const origin = new URL(c.req.url).origin;
  const invite = c.req.query("invite");
  const owner = role === "owner";
  return render(
    c,
    `${team.name} · Keyhop`,
    html`
      <div class="head">
        <div>
          <h1>${team.name}</h1>
          <p class="lede">
            ${people.length} ${people.length === 1 ? "member" : "members"}, ranked by ${METRICS[metric].label.toLowerCase()} ${PERIOD_PHRASES[period]}.
            <a class="text-link" href="/t/${team.slug}/day">See today</a>
          </p>
        </div>
        ${controls(`/t/${team.slug}`, period, metric)}
      </div>
      <section class="aside-layout">
        <div class="stack">${board(entries, metric, user, "Nobody on this team has synced usage for this period yet.")}</div>
        <aside class="stack">
          ${owner
            ? html`<div class="card">
                <div class="card-head"><h2>Invite people</h2></div>
                <div class="card-body form">
                  ${invite
                    ? html`<label>Share this link<input class="field mono" readonly value="${origin}/invite/${invite}"></label>
                        <p class="muted" style="margin:0;font-size:13px">Anyone with the link can join for 7 days.</p>`
                    : c.req.query("revoked")
                      ? html`<p class="muted" style="margin:0;font-size:13px">Every invite link for this team stopped working.</p>`
                      : html`<p class="muted" style="margin:0;font-size:13px">Create a link and send it to your teammates.</p>`}
                  <form method="post" action="/t/${team.slug}/invites"><button class="btn" type="submit" style="width:100%">Create invite link</button></form>
                  <form method="post" action="/t/${team.slug}/invites/revoke"><button class="btn ghost sm" type="submit" style="width:100%">Turn off all invite links</button></form>
                </div>
              </div>`
            : ""}
          <div class="card">
            <div class="card-head"><h2>Members</h2><span class="hint">${people.length}</span></div>
            ${people.map(
              (person) => html`<div class="list-row">
                <span class="person">${avatar(person, 28)}<span><b>${person.name || person.login}</b><small>@${person.login}</small></span></span>
                ${person.role === "owner"
                  ? html`<span class="badge">Owner</span>`
                  : owner
                    ? html`<form method="post" action="/t/${team.slug}/members/${person.login}/remove"><button class="btn ghost sm" type="submit">Remove</button></form>`
                    : ""}
              </div>`,
            )}
          </div>
          <div class="card"><div class="card-body form">
            ${owner
              ? html`<form class="form" method="post" action="/t/${team.slug}/delete">
                  <label>Delete this team<input class="field" name="confirm" placeholder="Type ${team.slug} to confirm" autocomplete="off"></label>
                  ${c.req.query("error") === "confirm" ? html`<p class="error-text">Type the team's name exactly to delete it.</p>` : ""}
                  <button class="btn danger" type="submit">Delete team</button>
                </form>`
              : html`<form method="post" action="/t/${team.slug}/leave"><button class="btn secondary" type="submit" style="width:100%">Leave team</button></form>`}
          </div></div>
        </aside>
      </section>`,
    { active: "teams", index: false },
  );
});

/** A day, written the way someone would say it out loud. */
function dayLabel(day: string, reference: string): string {
  if (day === reference) return "Today";
  if (day === addDays(reference, -1)) return "Yesterday";
  const date = new Date(`${day}T00:00:00Z`);
  const format: Intl.DateTimeFormatOptions = { weekday: "long", day: "numeric", month: "long", timeZone: "UTC" };
  // The year only earns its place once the day is no longer in this one.
  if (day.slice(0, 4) !== reference.slice(0, 4)) format.year = "numeric";
  return date.toLocaleDateString("en-GB", format);
}

/** Moving between days. The step into the future is drawn but dead, since that day hasn't happened. */
function dayNav(slug: string, day: string, reference: string): Html {
  const chevron = (left: boolean) =>
    raw(
      `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${
        left ? "M10 3 5 8l5 5" : "M6 3l5 5-5 5"
      }"/></svg>`,
    );
  const previous = addDays(day, -1);
  const next = addDays(day, 1);
  return html`<nav class="day-nav" aria-label="Day">
    <a class="step" href="/t/${slug}/day/${previous}" aria-label="${dayLabel(previous, reference)}">${chevron(true)}</a>
    ${day === reference
      ? html`<span class="now">Today</span>`
      : html`<a href="/t/${slug}/day/${reference}">Today</a>`}
    ${next <= reference
      ? html`<a class="step" href="/t/${slug}/day/${next}" aria-label="${dayLabel(next, reference)}">${chevron(false)}</a>`
      : html`<span class="step off" aria-disabled="true">${chevron(false)}</span>`}
  </nav>`;
}

/**
 * Repositories share the tool mix's language: white at falling opacity, brightest first, so the
 * biggest piece of someone's day reads loudest without a colour being invented for it.
 */
const REPO_SHADES = [0.9, 0.55, 0.32, 0.2, 0.13, 0.09];
const repoShade = (index: number): string => `hsl(0 0% 100% / ${REPO_SHADES[Math.min(index, REPO_SHADES.length - 1)]})`;

function repoMix(repos: DayRepo[]): Html {
  const total = repos.reduce((sum, entry) => sum + entry.commits, 0);
  if (total === 0) return html``;
  return html`<div class="repos">
    <span class="mix" aria-hidden="true">
      ${repos.map((entry, index) => html`<span style="width:${((entry.commits / total) * 100).toFixed(2)}%;background:${repoShade(index)}"></span>`)}
    </span>
    <ul class="repo-keys">
      ${repos.map(
        (entry, index) => html`<li>
          <i class="swatch" style="background:${repoShade(index)}"></i>${entry.repo.split("/").pop()}
          <span class="n">${count(entry.commits)}</span>
        </li>`,
      )}
    </ul>
  </div>`;
}

/** At most this many tasks per person before the rest are summed up in a line. */
const SHOWN_TASKS = 6;

/**
 * One person's day, written as the things they worked on. The commits are still there under each
 * task, because that is what makes the summary checkable rather than something to be taken on
 * trust, but the task is what the page is about.
 */
function personDay(person: PersonDay, viewer: User | null): Html {
  const tasks = tasksForDay(person.repos.map((repo) => ({ repo: repo.repo, subjects: repo.subjects })));
  const quiet = person.commits === 0 && person.tokens === 0;
  const many = person.repos.length > 1;
  return html`<article class="card day-person">
    <header class="day-head">
      <h2 class="day-name">${personCell(person, viewer, 34)}</h2>
      <div class="day-figures">
        <div><b>${count(person.commits)}</b><small>${person.commits === 1 ? "commit" : "commits"}</small></div>
        <div><b>${count(person.repos.length)}</b><small>${person.repos.length === 1 ? "repo" : "repos"}</small></div>
        <div><b>${tokens(person.tokens)}</b><small>tokens</small></div>
        <div>${diffStat(person.insertions, person.deletions)}<small>lines</small></div>
      </div>
    </header>
    ${person.indexing
      ? html`<p class="indexing">
          Still reading this computer's repositories, ${count(person.indexing.done)} of ${count(person.indexing.total)}.
          What's here is real, but it isn't all of it yet.
        </p>`
      : ""}
    ${quiet && !person.indexing
      ? html`<p class="day-quiet">Nothing synced for this day.</p>`
      : person.repos.length > 0
        ? repoMix(person.repos)
        : ""}
    ${person.commits > 0 && tasks.length === 0
      ? html`<p class="day-quiet">Commit subjects aren't shared from this computer.</p>`
      : ""}
    ${tasks.length > 0
      ? html`<ol class="tasks">
          ${tasks.slice(0, SHOWN_TASKS).map(
            (task) => html`<li class="task">
              <div class="task-head">
                <h3>${task.title}</h3>
                <span class="task-meta">
                  ${many ? html`<span class="where">${task.repos.map((repo) => repo.split("/").pop()).join(", ")}</span>` : ""}
                  ${task.commits.length === 1 ? html`<code class="sha">${task.commits[0].sha.slice(0, 7)}</code>` : ""}
                  <span>${count(task.commits.length)} ${task.commits.length === 1 ? "commit" : "commits"}</span>
                  <span>${span(task.from, task.to, task.offset)}</span>
                  ${diffStat(task.insertions, task.deletions)}
                </span>
              </div>
              ${task.commits.length === 1
                ? ""
                : html`<ul class="commits">
                ${task.commits.map(
                  (commit) => html`<li class="commit">
                    <code class="sha">${commit.sha.slice(0, 7)}</code>
                    <span class="subject">${parseSubject(commit.subject).body}</span>
                    ${task.repos.length > 1 ? html`<span class="where">${commit.repo.split("/").pop()}</span>` : ""}
                  </li>`,
                )}
              </ul>`}
            </li>`,
          )}
          ${tasks.length > SHOWN_TASKS
            ? html`<li class="more-commits">and ${count(tasks.length - SHOWN_TASKS)} more</li>`
            : ""}
        </ol>`
      : ""}
  </article>`;
}

/**
 * One day, for one team. The point of the page is that it reads: the commits are there in words, so
 * a person can see what everyone actually did rather than only how much of it there was.
 */
pages.get("/t/:slug/day/:date", pageUser, (c) => teamDayPage(c, c.req.param("date")));
pages.get("/t/:slug/day", pageUser, (c) => teamDayPage(c, today()));

async function teamDayPage(c: C, date: string) {
  const user = c.get("user")!;
  const reference = today();
  const membership = await teamForMember(c.env.DB, c.req.param("slug") ?? "", user.id);
  if (!membership) return notFound(c, "This team doesn't exist, or you aren't in it.");
  const { team } = membership;
  // A date that isn't a date, or one that hasn't happened, falls back to today rather than erroring.
  const day = /^\d{4}-\d{2}-\d{2}$/.test(date) && addDays(date, 0) === date && date <= reference ? date : reference;

  const people = await teamDay(c.env.DB, team.id, day);
  const commits = people.reduce((sum, person) => sum + person.commits, 0);
  const dayTokens = people.reduce((sum, person) => sum + person.tokens, 0);
  const repos = new Set(people.flatMap((person) => person.repos.map((repo) => repo.repo)));
  const worked = people.filter((person) => person.commits > 0 || person.tokens > 0).length;
  const anySubjects = people.some((person) => person.repos.some((repo) => repo.subjects.length > 0));
  const stillIndexing = people.filter((person) => person.indexing);

  return render(
    c,
    `${dayLabel(day, reference)} · ${team.name} · Keyhop`,
    html`
      <div class="head">
        <div>
          <h1>${dayLabel(day, reference)}</h1>
          <p class="day-sum">
            <span><b>${count(worked)}</b> of ${count(people.length)} working</span>
            <span><b>${count(commits)}</b> ${commits === 1 ? "commit" : "commits"}</span>
            <span><b>${count(repos.size)}</b> ${repos.size === 1 ? "repository" : "repositories"}</span>
            <span><b>${tokens(dayTokens)}</b> tokens</span>
          </p>
          ${stillIndexing.length > 0
            ? html`<p class="day-note">
                ${stillIndexing.length === 1
                  ? html`${stillIndexing[0].name || stillIndexing[0].login} is still being indexed, so this day isn't complete.`
                  : html`${count(stillIndexing.length)} people are still being indexed, so this day isn't complete.`}
              </p>`
            : ""}
        </div>
        ${dayNav(team.slug, day, reference)}
      </div>
      <section class="stack">
        ${people.length === 0
          ? html`<div class="card empty">Nobody has joined ${team.name} yet.</div>`
          : people.map((person) => personDay(person, user))}
        ${commits === 0
          ? html`<div class="card empty">
              No commits synced for this day. Keyhop counts them from the repositories on your own computer, once
              <a href="/settings">you turn it on</a>.
            </div>`
          : anySubjects
            ? ""
            : html`<p class="muted" style="margin:0;font-size:13px">
                Commit subjects stay on each person's computer until they turn sharing on in Keyhop.
              </p>`}
      </section>`,
    { active: "teams", index: false },
  );
}

pages.get("/invite/:code", async (c) => {
  const code = c.req.param("code");
  const info = await inviteInfo(c.env.DB, code);
  if (!info) return notFound(c, "This invite link expired or was turned off. Ask for a new one.");
  const user = c.get("user");
  if (user && (await teamForMember(c.env.DB, info.slug, user.id))) return c.redirect(`/t/${info.slug}`);
  return render(
    c,
    `Join ${info.name} · Keyhop`,
    html`<section class="card center-card">
      ${raw(PIXEL_MARK)}
      <h1>Join ${info.name}</h1>
      <p class="lede">@${info.owner} invited you. ${info.members} ${info.members === 1 ? "person compares" : "people compare"} their AI usage here.</p>
      <p class="muted" style="margin:0;font-size:13px">Team members see each other's daily totals, and each other's day: tokens and API value per tool, and the commits behind them from anyone who shares them.</p>
      ${c.req.query("error") === "full" ? html`<p class="error-text">This team is full.</p>` : ""}
      ${user
        ? html`<form method="post" action="/invite/${code}"><button class="btn" type="submit">Join team</button></form>`
        : html`<a class="btn" href="/login?next=${encodeURIComponent(`/invite/${code}`)}">${githubIcon()}Sign in with GitHub to join</a>`}
    </section>`,
    { description: `Join ${info.name} on Keyhop and compare AI usage with your team.`, index: false },
  );
});

pages.get("/settings", pageUser, async (c) => {
  const user = c.get("user")!;
  const { results: apps } = await c.env.DB.prepare(
    "SELECT id, label, access, created_at, last_used_at FROM sessions WHERE user_id = ? AND kind = 'app' ORDER BY last_used_at DESC",
  )
    .bind(user.id)
    .all<{ id: string; label: string | null; access: "read" | "write"; created_at: number; last_used_at: number }>();
  return render(
    c,
    "Settings · Keyhop",
    html`
      <div class="head"><div><h1>Settings</h1><p class="lede">Signed in as @${user.login} with GitHub.</p></div></div>
      ${c.req.query("saved") ? html`<div class="notice ok"><div><b>Saved</b></div></div>` : ""}
      <section class="split">
        <div class="card">
          <div class="card-head"><h2>Profile</h2></div>
          <form class="form card-body" method="post" action="/settings/profile">
            <label>Display name<input class="field" name="display_name" maxlength="40" autocomplete="off"
              placeholder="${user.name ?? user.login}" value="${user.display_name ?? ""}"></label>
            <label>Bio<input class="field" name="bio" maxlength="160" autocomplete="off"
              placeholder="One line about you" value="${user.bio ?? ""}"></label>
            <label>Link<input class="field" name="link" maxlength="200" autocomplete="off" inputmode="url"
              placeholder="your-site.dev" value="${user.link ?? ""}"></label>
            ${c.req.query("error") === "link" ? html`<p class="error-text">That link isn't a web address. Use one starting with http or https.</p>` : ""}
            <label class="check"><input type="checkbox" name="public" ${user.public === 1 ? raw("checked") : ""}>
              <span>Show me on the global leaderboard<small>Your profile at /u/${user.login} becomes public. Teams you join always see your totals.</small></span></label>
            <div><button class="btn" type="submit">Save</button></div>
          </form>
        </div>
        <div class="card">
          <div class="card-head"><h2>Linked apps</h2><span class="hint">${apps.length}</span></div>
          ${apps.length === 0
            ? html`<p class="empty">No Keyhop app is linked yet. In Keyhop, open Settings, then Leaderboard.</p>`
            : apps.map(
                (app) => html`<div class="list-row">
                  <span class="person"><span><b>${app.label || "Keyhop"}</b><small>${app.access === "read" ? "Read only · " : ""}Linked ${monthYear(app.created_at)} · used ${ago(app.last_used_at)}</small></span></span>
                  <form method="post" action="/settings/apps/${app.id}/revoke"><button class="btn ghost sm" type="submit">Unlink</button></form>
                </div>`,
              )}
        </div>
      </section>
      <section class="split">
        <div class="card"><div class="card-head"><h2>Sign out</h2></div>
          <form class="card-body" method="post" action="/auth/logout"><button class="btn secondary" type="submit">Sign out of this browser</button></form>
        </div>
        <div class="card"><div class="card-head"><h2>Delete account</h2></div>
          <form class="form card-body" method="post" action="/settings/delete">
            <p class="muted" style="margin:0;font-size:13px">Removes your profile, synced totals, linked apps, memberships and the teams you own. This can't be undone.</p>
            <input class="field" name="confirm" placeholder="Type ${user.login} to confirm" autocomplete="off">
            ${c.req.query("error") === "confirm" ? html`<p class="error-text">Type your GitHub login exactly to delete your account.</p>` : ""}
            <div><button class="btn danger" type="submit">Delete account</button></div>
          </form>
        </div>
      </section>`,
    { index: false },
  );
});

pages.get("/link", pageUser, async (c) => {
  const user = c.get("user")!;
  if (c.req.query("done")) {
    return render(
      c,
      "Keyhop linked · Keyhop",
      html`<section class="card center-card">
        ${raw(PIXEL_MARK)}
        <h1>Keyhop is linked</h1>
        <p class="lede">Go back to Keyhop. It can now use the leaderboard as @${user.login}.</p>
        <a class="btn secondary" href="/u/${user.login}">View your profile</a>
      </section>`,
      { index: false },
    );
  }
  const code = (c.req.query("code") ?? "").toUpperCase().slice(0, 9);
  const pending = code
    ? await c.env.DB.prepare("SELECT label, access FROM device_links WHERE user_code = ? AND user_id IS NULL AND expires_at > ?")
        .bind(code, now())
        .first<{ label: string | null; access: "read" | "write" }>()
    : null;
  return render(
    c,
    "Link Keyhop · Keyhop",
    html`<section class="card center-card">
      ${raw(PIXEL_MARK)}
      <h1>Link Keyhop</h1>
      <p class="lede">Check that this code matches the one in your Keyhop window. Only approve a code you started yourself.</p>
      <form class="form" method="post" action="/link">
        <input class="field code" name="code" value="${code}" maxlength="9" required autocomplete="off" aria-label="Code">
        ${c.req.query("error") ? html`<p class="error-text">That code expired or was already used. Start again in Keyhop.</p>` : ""}
        <button class="btn" type="submit">Link to @${user.login}</button>
      </form>
      <p class="muted" style="margin:0;font-size:13px">${pending?.access === "read"
        ? html`<b>${pending.label || "This companion"}</b> can read your profile, season, quests and standings. It cannot upload usage or change your profile.`
        : html`<b>${pending?.label || "Keyhop"}</b> can send tokens, API value and requests per tool per day, and commit counts if you turn them on. Never prompts, emails or account names.`}</p>
    </section>`,
    { index: false },
  );
});
