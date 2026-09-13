import { type Context, Hono } from "hono";
import { html, raw } from "hono/html";
import { pageUser, safeNext } from "./auth";
import { type AppEnv, type User, today } from "./env";
import { landingPage } from "./landing";
import { downloadPage, privacyPage, securityPage, termsPage } from "./marketing";
import { TIERS, currentSeason, daysLeft, isSeason, nextStep, seasonBoard, seasonLabel, seasonList, seasonRange, tierFor } from "./seasons";
import { type Entry, type Metric, type Period, METRICS, PERIODS, isMetric, isPeriod, leaderboard, profile } from "./stats";
import { inviteInfo, members, myTeams, teamForMember } from "./teams";
import {
  type Html,
  PIXEL_MARK,
  ago,
  avatar,
  count,
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
    active?: "leaderboard" | "teams" | "season";
    mode?: "app" | "landing" | "marketing";
    index?: boolean;
    softwareSchema?: boolean;
    canonicalPath?: string;
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

function personCell(entry: Entry, viewer: User | null, size: number): Html {
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
    description: "Switch Claude Code, Cursor and Codex accounts, watch limits and explore Keyhop's roadmap for AI, MCP and mobile.",
    mode: "landing",
    softwareSchema: true,
  }),
);

pages.get("/download", (c) =>
  render(c, "Download Keyhop for macOS, Linux and Windows", downloadPage(), {
    description: "Download Keyhop for macOS, Linux or Windows and switch Claude Code, Cursor and Codex accounts without breaking flow.",
    mode: "marketing",
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
      ${board(entries, metric, user, "Nobody has synced usage for this period yet.")}`,
    { active: "leaderboard", description: `Who used the most AI ${PERIOD_PHRASES[period]}, on Keyhop.` },
  );
});

/** One month of ranked play. Past seasons are counted the same way, so they never go stale. */
async function seasonPage(c: C, season: string) {
  const viewer = c.get("user");
  const board = await seasonBoard(c.env.DB, { season, metric: "tokens" });
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
        : ""}
      ${board.length === 0
        ? html`<div class="card empty">Nobody has synced usage for this season yet.</div>`
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
      description: `Keyhop's ${seasonLabel(season)} season: who ranks where in Claude Code, Cursor and Codex.`,
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
  const person = await c.env.DB.prepare("SELECT id, github_id, login, name, avatar_url, public, created_at FROM users WHERE login = ? COLLATE NOCASE")
    .bind(login)
    .first<User>();
  const viewer = c.get("user");
  const isSelf = !!person && viewer?.id === person.id;
  if (!person || (person.public !== 1 && !isSelf)) return notFound(c, "This profile is private, or doesn't exist.");
  if (person.login !== login) return c.redirect(`/u/${person.login}`, 301);

  const [stats, season] = await Promise.all([
    profile(c.env.DB, person.id, person.public === 1),
    seasonBoard(c.env.DB, { season: currentSeason(), metric: "tokens" }),
  ]);
  const place = season.find((entry) => entry.userId === person.id);
  const url = `${new URL(c.req.url).origin}/u/${person.login}`;
  const display = person.name || person.login;
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
        <div><h1>${team.name}</h1><p class="lede">${people.length} ${people.length === 1 ? "member" : "members"}, ranked by ${METRICS[metric].label.toLowerCase()} ${PERIOD_PHRASES[period]}.</p></div>
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
      <p class="muted" style="margin:0;font-size:13px">Team members see each other's daily totals: tokens, API value and requests per tool.</p>
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
    "SELECT id, label, created_at, last_used_at FROM sessions WHERE user_id = ? AND kind = 'app' ORDER BY last_used_at DESC",
  )
    .bind(user.id)
    .all<{ id: string; label: string | null; created_at: number; last_used_at: number }>();
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
                  <span class="person"><span><b>${app.label || "Keyhop"}</b><small>Linked ${monthYear(app.created_at)} · used ${ago(app.last_used_at)}</small></span></span>
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

pages.get("/link", pageUser, (c) => {
  const user = c.get("user")!;
  if (c.req.query("done")) {
    return render(
      c,
      "Keyhop linked · Keyhop",
      html`<section class="card center-card">
        ${raw(PIXEL_MARK)}
        <h1>Keyhop is linked</h1>
        <p class="lede">Go back to Keyhop. It starts sending your daily totals to @${user.login}.</p>
        <a class="btn secondary" href="/u/${user.login}">View your profile</a>
      </section>`,
      { index: false },
    );
  }
  const code = (c.req.query("code") ?? "").toUpperCase().slice(0, 9);
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
      <p class="muted" style="margin:0;font-size:13px">Keyhop sends tokens, API value and requests per tool per day. Never prompts, emails or account names.</p>
    </section>`,
    { index: false },
  );
});
