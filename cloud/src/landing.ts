import { html, raw } from "hono/html";
import { MEASURED_TOOLS, type Tool, TOOL_NAMES } from "./env";
import type { Html } from "./ui";
import { PIXEL_MARK, mark } from "./ui";

/**
 * The home page in the Keyhop 2.0 world: the offer and the install line beside a picture of the
 * app's own screen, with the verdict, the logins ranked by runway and the hop it offers, then the
 * figures, how a hop works, the tools, the settings people touch, the season, and questions.
 * Every sample on it says it is one.
 */

// MARK: Sections

interface ToolRow {
  tool: Tool;
  name: string;
  limits: string;
  history: string;
  how: string;
}

/** What Keyhop does with each tool, as it ships. Kept in step with the README's table. */
const TOOL_ROWS: ToolRow[] = [
  { tool: "claude", name: "Claude Code", limits: "5-hour and weekly", history: "Local transcripts", how: "Its own login, in your keychain" },
  { tool: "cursor", name: "Cursor", limits: "Auto and API", history: "Cursor's usage export", how: "Cursor's own login link" },
  { tool: "codex", name: "Codex", limits: "5-hour and weekly", history: "Local transcripts", how: "~/.codex/auth.json" },
  { tool: "gemini", name: "Gemini CLI", limits: "Stays in Gemini CLI", history: "Local transcripts", how: "Google sign-in files" },
  { tool: "opencode", name: "OpenCode", limits: "Stays with each provider", history: "OpenCode's own ledger", how: "The whole auth.json profile" },
  { tool: "pi", name: "Pi", limits: "Stays with each provider", history: "Local sessions", how: "The whole auth.json profile" },
  { tool: "copilot", name: "GitHub Copilot", limits: "Plan quota from GitHub", history: "Not exposed", how: "The GitHub CLI's accounts" },
  { tool: "windsurf", name: "Windsurf", limits: "Cached for the account in use", history: "Not exposed", how: "~/.codeium/config.json" },
  { tool: "codebuff", name: "Codebuff", limits: "Credits, block and week", history: "Not exposed", how: "Its default profile" },
];

const INSTALL_UNIX = "curl -fsSL https://raw.githubusercontent.com/dominikzabcik/keyhop/main/install.sh | bash";

// MARK: The app, pictured

interface SampleLogin { tool: Tool; who: string; sub: string; left: number; reset: string; state: "in-use" | "pick" | "out" }

const SAMPLE_LOGINS: SampleLogin[] = [
  { tool: "claude", who: "Personal", sub: "Claude Code · Max 5x · in use", left: 18, reset: "empty ~12:43 PM", state: "in-use" },
  { tool: "claude", who: "work@studio.dev", sub: "Claude Code · Pro", left: 88, reset: "resets 2:00 PM", state: "pick" },
  { tool: "codex", who: "me@personal.dev", sub: "Codex · Plus", left: 7, reset: "back ~11:19 AM", state: "out" },
];

/** A picture of the app's own screen: the verdict, the logins ranked by runway, and the hop. */
function appShot(): Html {
  return html`<figure class="shot" aria-label="A sample of Keyhop's window: Claude Code's Personal login empties around 12:43 PM, work@studio.dev still has 88% of its window, and Keyhop offers the hop.">
    <div class="shot-bar" aria-hidden="true">${raw(PIXEL_MARK)}<b>Keyhop</b><span>read 1 min ago</span></div>
    <div class="shot-body" aria-hidden="true">
      <p class="shot-verdict">Personal empties around 12:43 PM.<br>work@studio.dev has the room.</p>
      <div class="shot-rows">
        ${SAMPLE_LOGINS.map((row) => html`<div class="shot-row ${row.state}">
          ${mark(row.tool)}
          <span class="shot-who"><b>${row.who}</b><small>${row.sub}</small></span>
          <span class="runway"><i style="width:${row.left}%"></i></span>
          <span class="shot-left">${row.left}%<small>${row.reset}</small></span>
        </div>`)}
      </div>
      <div class="shot-foot">
        <span class="shot-hop">Hop to work@studio.dev</span>
        <span class="shot-today">14.1M · $30.26 today</span>
      </div>
    </div>
    <figcaption>Sample accounts</figcaption>
  </figure>`;
}

// MARK: Sections

const FIGURES: [string, string][] = [
  ["9", "AI coding tools it can switch"],
  ["13", "tools with a full token history"],
  ["0", "logins that leave your computer"],
  ["1 click", "from the alert to the login with room"],
];

const STEPS: [string, string, string][] = [
  ["Save", "First, it saves the login in use.", "Personal is saved to your keychain before anything changes."],
  ["Load", "Then it loads the one you chose.", "work@studio.dev comes out of the same vault."],
  ["Hand over", "Next, it hands it to the tool.", "Claude Code gets it through the path it already reads."],
  ["Confirm", "Last, it reads it back.", "Claude Code now uses work@studio.dev, 12% into its 5-hour window."],
];

/** The settings people actually change, drawn as the app shows them. The switches are a picture. */
const SETTINGS: [string, string, boolean][] = [
  ["Hop for me before a limit runs out.", "The alert switches to Smart Hop's best login by itself.", true],
  ["Warn me when a budget passes 80%.", "Per login or across all of them, by day, week or month. Keyhop notifies you at 80% and at 100%.", true],
  ["Share today's totals live with my team.", "Per-tool totals go every 90 seconds; your team day marks you live for three minutes.", false],
  ["Count the commits I wrote myself.", "Merge commits are left out, and each day is rewritten on sync, so a rebase counts once.", false],
  ["Rank me by commits per million tokens.", "The season compares people on your plan, past a floor of one million tokens.", false],
];

/** Sample rows only: the real board is one click away. */
const SAMPLE_BOARD: [string, string, string, string, string, string][] = [
  ["S1", "sample-one", "Monument · 41-day streak", "18.4", "2.1B", "38,640"],
  ["S2", "sample-two", "Mass · 12-day streak", "16.9", "940M", "15,886"],
  ["YO", "you", "Bulk · 12-day streak", "15.2", "800M", "12,160"],
  ["S4", "sample-four", "Bulk · 3-day streak", "13.7", "620M", "8,494"],
  ["S5", "sample-five", "Frame · 9-day streak", "12.1", "48M", "581"],
];

const FAQ: { q: string; a: Html | string; code?: string }[] = [
  { q: "What is Keyhop, exactly?", a: "A small app on your own computer. It sits in the menu bar or tray, answers as the keyhop command, holds the logins you already have for each AI coding tool, and hands a tool another of your accounts when you ask or when the one in use runs out." },
  { q: "Does it share accounts or add usage?", a: "No. Keyhop only switches between accounts you own. It cannot raise a plan's limits, and every provider's terms still apply." },
  { q: "What leaves my computer?", a: "Nothing, until you link GitHub. Then daily totals per tool go to the leaderboard, and current limits only if you share them. Prompts, code and provider tokens never do. This prints every payload before it goes:", code: "keyhop cloud show-data" },
  { q: "How do I install it?", a: html`On macOS and Linux, run the line below. Homebrew, Scoop, DEB, RPM, Arch and the Windows PowerShell line are on the <a href="/download">download page</a>.`, code: INSTALL_UNIX },
  { q: "Can my coding agent read it?", a: html`Yes. <code>keyhop mcp</code> serves three read-only tools, <code>keyhop_status</code>, <code>keyhop_usage</code> and <code>keyhop_recommendation</code>, so an agent can check the room left before a long run. It can't see credentials, and it can't switch.` },
  { q: "What does API value mean?", a: "The tokens you used, priced at each provider's standard API rates. It is the value of your usage, not a bill from your subscription." },
  { q: "Is the phone app in the App Store?", a: "Not yet. The iOS companion builds from source, with seasons, quests, badges, shared limits and an alert when a limit comes back." },
  { q: "Can I build it myself?", a: "Yes. Keyhop is MIT licensed, its installers are readable shell scripts, and the app, the website, the packaging and the tests are in one public repository." },
];

const DOWNLOAD_GLYPH = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 4v12M6 10l6 6 6-6M5 20h14"/></svg>`;

export function landingPage(): Html {
  const measuredOnly = MEASURED_TOOLS.filter((tool) => !TOOL_ROWS.some((row) => row.tool === tool)).map((tool) => TOOL_NAMES[tool]);
  const others = measuredOnly.length > 1 ? `${measuredOnly.slice(0, -1).join(", ")} and ${measuredOnly[measuredOnly.length - 1]}` : measuredOnly.join("");
  return html`
    <section class="hero" id="product" aria-labelledby="hero-title">
      <div class="hero-copy">
        <span class="lab">Free and open source · macOS, Linux, Windows</span>
        <h1 id="hero-title">Every login, one hop away.</h1>
        <p>Keyhop watches the limits on every AI coding account you own and moves your tools to the login with room, before a limit stops you.</p>
        <div class="hero-actions">
          <a class="btn lg" href="/download">${raw(DOWNLOAD_GLYPH)}Download Keyhop</a>
          <span class="install-line"><span class="prompt" aria-hidden="true">$</span><code title="${INSTALL_UNIX}">curl -fsSL …/install.sh | bash</code><button class="copy" type="button" data-copy="${INSTALL_UNIX}" aria-label="Copy the install command">Copy</button></span>
        </div>
        <span class="hero-note">MIT licence. The installer checks the release's SHA-256 before it installs anything.</span>
      </div>
      ${appShot()}
    </section>

    <section class="figures" aria-label="Keyhop in figures">
      ${FIGURES.map(([value, label]) => html`<div><b>${value}</b><span>${label}</span></div>`)}
    </section>

    <section class="band" aria-labelledby="how-title">
      <div class="band-head wide">
        <span class="lab">How a hop works</span>
        <h2 id="how-title">A switch never signs you out anywhere.</h2>
        <p>Logins stay in the system's own vault: Keychain on macOS, Secret Service on Linux, DPAPI on Windows. Provider tokens are never sent to keyhop.app.</p>
      </div>
      <ol class="steps">
        ${STEPS.map(([verb, title, say], index) => html`<li class="step${index === STEPS.length - 1 ? " last" : ""}">
          <span class="step-top"><span class="step-n">${index + 1}</span><span class="lab">${verb}</span></span>
          <b>${title}</b>
          <span>${say}</span>
        </li>`)}
      </ol>
    </section>

    <section class="band split-band" id="tools" aria-labelledby="tools-title">
      <div class="band-head">
        <span class="lab">Tools</span>
        <h2 id="tools-title">Nine tools, each switched its own way.</h2>
        <p>The first six keep a token history, counted on your computer by account, model and project. The last three keep none, so Keyhop shows their limits and invents no totals.</p>
        <p class="band-note">It also counts the tokens of ${others}, which it doesn't switch.</p>
      </div>
      <div class="panel table-scroll">
        <table class="tool-table">
          <thead><tr><th scope="col">Tool</th><th scope="col">Limits read</th><th scope="col">Login it switches</th><th scope="col" class="end">Tokens</th></tr></thead>
          <tbody>
            ${TOOL_ROWS.map((row) => {
              const counted = row.history !== "Not exposed";
              return html`<tr>
                <th scope="row">${mark(row.tool)}${row.name}</th>
                <td data-label="Limits read">${row.limits}</td>
                <td data-label="Login it switches"${row.how.startsWith("~") ? raw(' class="path"') : ""}>${row.how}</td>
                <td class="end"><span class="tag${counted ? " counted" : ""}">${counted ? "Counted" : "Limits only"}</span></td>
              </tr>`;
            })}
          </tbody>
        </table>
      </div>
    </section>

    <section class="band split-band" aria-labelledby="set-title">
      <div class="band-head">
        <span class="lab">Settings you will touch</span>
        <h2 id="set-title">Hop before the wall.</h2>
        <p>Smart Hop ranks your logins offline by room, resets, forecast and budget. Everything shared is opt-in.</p>
      </div>
      <ul class="panel settings-list">
        ${SETTINGS.map(([name, desc, on]) => html`<li><span><b>${name}</b><span>${desc}</span></span><span class="switch${on ? " on" : ""}" aria-hidden="true"><i></i></span></li>`)}
      </ul>
    </section>

    <section class="band split-band" id="season" aria-labelledby="lb-title">
      <div class="band-head">
        <span class="lab">Season · Max division · sample</span>
        <h2 id="lb-title">Ranked by what you ship.</h2>
        <p>The leaderboard compares people on your plan by commits per million tokens, past a floor of one million tokens. Only commits you wrote count, merges are left out, and only daily totals per tool are shared.</p>
        <a class="btn secondary" href="/leaderboard">Open the leaderboard</a>
      </div>
      <div class="panel table-scroll" role="table" aria-label="A sample season board">
        <div class="board-row board-headrow" role="row"><span role="columnheader">#</span><span role="columnheader">Person · sample data</span><span role="columnheader" class="end">Commits / 1M</span><span role="columnheader" class="end">Tokens</span><span role="columnheader" class="end">Commits</span></div>
        ${SAMPLE_BOARD.map(([initials, who, pet, efficiency, total, commits], index) => html`<div class="board-row${who === "you" ? " is-you" : ""}" role="row">
          <span role="cell" class="rank">${index + 1}</span>
          <span role="cell" class="board-who"><span class="initials">${initials}</span><span><b>${who}</b><small>${pet}</small></span></span>
          <span role="cell" class="end eff">${efficiency}</span>
          <span role="cell" class="end">${total}</span>
          <span role="cell" class="end">${commits}</span>
        </div>`)}
      </div>
    </section>

    <section class="band split-band" id="faq" aria-labelledby="faq-title">
      <div class="band-head">
        <span class="lab">Questions</span>
        <h2 id="faq-title">Fair questions.</h2>
      </div>
      <div class="faq-grid">
        ${FAQ.map((item) => html`<div class="faq-item"><h3>${item.q}</h3><p>${item.a}</p>${item.code ? html`<code class="faq-code">${item.code}</code>` : ""}</div>`)}
      </div>
    </section>

    <section class="cta" aria-labelledby="cta-title">
      <span><h2 id="cta-title">Bring every login.</h2><span>For macOS, Linux and Windows. Your work never leaves your computer.</span></span>
      <a class="btn lg" href="/download">Download Keyhop</a>
      <a class="btn lg secondary" href="https://github.com/dominikzabcik/keyhop">View on GitHub</a>
    </section>
  `;
}

// MARK: Styles

export const LANDING_CSS = `
body.landing { overflow-x: clip; }
.landing-main { max-width: 1440px; padding: 0 64px; display: block; font-size: 15px; line-height: 24px; }
.landing-main h1, .landing-main h2, .landing-main h3, .landing-main p { margin: 0; }
.landing-main h2 { font-size: 44px; line-height: 48px; font-weight: 500; letter-spacing: -.035em; text-wrap: balance; }
.landing-main code { font-family: var(--mono); font-size: .9em; color: var(--text); }
.landing-main .lab { display: block; }
.btn.lg { height: 44px; padding: 0 22px; border-radius: 6px; font-size: 15px; }
.btn.lg svg { width: 16px; height: 16px; fill: none; }

/* The first screen: the offer beside a picture of the app's own screen. */
.hero { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1.05fr); gap: 56px; align-items: center; padding: 96px 0 88px; }
.hero-copy { display: flex; flex-direction: column; gap: 24px; }
.hero h1 { font-size: 72px; line-height: 72px; font-weight: 500; letter-spacing: -.045em; text-wrap: balance; }
.hero-copy > p { max-width: 44ch; font-size: 17px; line-height: 27px; color: var(--muted); }
.hero-actions { margin-top: 8px; display: flex; flex-wrap: wrap; gap: 10px; }
.install-line { height: 44px; padding: 0 8px 0 16px; display: flex; align-items: center; gap: 12px; border-radius: 5px; background: hsl(var(--on) / .03); box-shadow: inset 0 0 0 1px var(--border); font-family: var(--mono); font-size: 13px; }
.install-line .prompt { color: var(--subtle); }
.install-line code { font-size: 13px; white-space: nowrap; }
.hero-note { font-size: 13px; color: var(--subtle); }

/* The depth is tonal, the way the app draws it: chrome, ground, surface, never a shadow. */
.shot { margin: 0; border-radius: 8px; background: var(--panel); box-shadow: inset 0 0 0 1px var(--border-strong); overflow: hidden; }
.shot-bar { display: flex; align-items: center; gap: 8px; height: 44px; padding: 0 16px; background: var(--chrome); box-shadow: inset 0 -1px 0 var(--border); font-size: 13px; }
.shot-bar b { font-weight: 600; }
.shot-bar span { margin-left: auto; color: var(--subtle); font-family: var(--mono); font-size: 11.5px; }
.shot-body { padding: 22px 20px 18px; display: grid; gap: 18px; }
.shot-verdict { margin: 0; font-size: 19px; line-height: 27px; font-weight: 500; letter-spacing: -.015em; text-wrap: balance; }
.shot-rows { display: grid; gap: 6px; }
.shot-row { display: grid; grid-template-columns: 16px minmax(0, 1fr) 110px 96px; gap: 14px; align-items: center; padding: 11px 13px; border-radius: 5px; background: var(--raised); box-shadow: inset 0 0 0 1px var(--border); }
.shot-row.pick { box-shadow: inset 0 0 0 1px var(--border-strong); }
.shot-row.out { background: rgba(224, 87, 70, .06); }
.shot-row .mark { width: 15px; height: 15px; fill: var(--text); }
.shot-who { min-width: 0; display: grid; line-height: 18px; }
.shot-who b { font-size: 13px; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.shot-who small { font-size: 12px; color: var(--subtle); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.runway { height: 4px; border-radius: 99px; background: hsl(var(--on) / .08); overflow: hidden; }
.runway i { display: block; height: 100%; min-width: 4px; border-radius: inherit; background: var(--good); }
.shot-row.in-use .runway i { background: var(--warn); }
.shot-row.out .runway i { background: var(--bad); }
.shot-left { text-align: right; display: grid; line-height: 16px; font-family: var(--mono); font-size: 12.5px; font-weight: 500; font-variant-numeric: tabular-nums; }
.shot-left small { font-size: 10.5px; font-weight: 400; color: var(--subtle); white-space: nowrap; }
.shot-row.in-use .shot-left { color: var(--warn); }
.shot-row.in-use .shot-left small, .shot-row.out .shot-left small { color: inherit; opacity: .8; }
.shot-row.out .shot-left { color: var(--bad); }
.shot-foot { display: flex; align-items: center; justify-content: space-between; gap: 14px; padding-top: 16px; box-shadow: inset 0 1px 0 var(--border); }
.shot-hop { height: 32px; padding: 0 15px; display: inline-flex; align-items: center; border-radius: 5px; background: var(--primary); color: var(--on-primary); font-size: 13px; font-weight: 600; }
.shot-today { color: var(--subtle); font-family: var(--mono); font-size: 12px; font-variant-numeric: tabular-nums; }
.shot figcaption { padding: 0 16px 12px; font-size: 11px; color: var(--subtle); background: var(--panel); }

/* Figures: one strip, split by hairlines. */
.figures { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); box-shadow: inset 0 1px 0 var(--faint), inset 0 -1px 0 var(--faint); }
.figures > div { padding: 28px 24px; display: grid; gap: 6px; box-shadow: inset 1px 0 0 var(--faint); }
.figures > div:first-child { box-shadow: none; }
.figures b { font-size: 36px; line-height: 40px; font-weight: 500; letter-spacing: -.03em; }
.figures span { font-size: 14px; color: var(--muted); }

/* The bands after it: a heading on the left, the thing itself on the right. */
.band { padding-top: 112px; }
.band-head { display: flex; flex-direction: column; align-items: flex-start; gap: 12px; }
.band-head.wide { max-width: 640px; margin-bottom: 36px; }
.band-head p { color: var(--muted); }
.band-head .btn { margin-top: 8px; }
.band-note { font-size: 13px; color: var(--subtle) !important; }
.split-band { display: grid; grid-template-columns: minmax(0, .8fr) minmax(0, 1.6fr); gap: 56px; align-items: start; }
.panel { margin: 0; padding: 0; border-radius: 8px; background: var(--panel); box-shadow: inset 0 0 0 1px var(--border); overflow: hidden; list-style: none; }

.steps { margin: 0; padding: 0; list-style: none; display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; }
.step { padding: 24px; display: flex; flex-direction: column; gap: 14px; border-radius: 8px; background: var(--panel); box-shadow: inset 0 0 0 1px var(--border); transition: box-shadow .25s ease; }
.step:hover { box-shadow: inset 0 0 0 1px var(--border-strong); }
.step-top { display: flex; align-items: center; justify-content: space-between; }
.step-n { width: 28px; height: 28px; border-radius: 5px; display: inline-flex; align-items: center; justify-content: center; background: hsl(var(--on) / .06); font: 600 12px var(--mono); }
.step.last .step-n { background: var(--primary); color: var(--on-primary); }
.step b { font-size: 18px; line-height: 24px; font-weight: 500; letter-spacing: -.01em; }
.step > span:last-child { font-size: 14px; line-height: 22px; color: var(--muted); }

.table-scroll { overflow-x: auto; }
.tool-table { width: 100%; min-width: 640px; border-collapse: collapse; font-size: 14px; }
.tool-table th, .tool-table td { padding: 0 16px 0 0; height: 48px; text-align: left; vertical-align: middle; border-top: 1px solid hsl(var(--on) / .06); }
.tool-table th:first-child, .tool-table td:first-child { padding-left: 22px; }
.tool-table .end { padding-right: 22px; text-align: right; }
.tool-table thead th { height: 44px; border-top: 0; color: var(--subtle); font: 400 12px var(--sans); letter-spacing: 0; text-transform: none; }
.tool-table tbody th { font-weight: 600; white-space: nowrap; }
.tool-table tbody th .mark { width: 16px; height: 16px; margin: -3px 10px 0 0; vertical-align: middle; fill: var(--text); }
.tool-table td { color: var(--muted); }
.tool-table td.path { font-family: var(--mono); font-size: 13px; }
.tag { display: inline-flex; height: 22px; padding: 0 8px; align-items: center; border-radius: 5px; background: hsl(var(--on) / .06); color: var(--muted); font-size: 12px; font-weight: 600; white-space: nowrap; }
.tag.counted { background: hsl(var(--on) / .1); color: var(--text); }

.settings-list li { padding: 20px 24px; display: flex; align-items: center; gap: 24px; }
.settings-list li + li { box-shadow: inset 0 1px 0 hsl(var(--on) / .06); }
.settings-list li > span:first-child { flex: 1; min-width: 0; display: grid; gap: 2px; }
.settings-list b { font-weight: 600; }
.settings-list li > span:first-child > span { font-size: 14px; line-height: 22px; color: var(--muted); }
.switch { position: relative; flex: none; width: 40px; height: 22px; border-radius: 7px; background: hsl(var(--on) / .14); }
.switch i { position: absolute; top: 3px; left: 3px; width: 16px; height: 16px; border-radius: 5px; background: var(--text); }
.switch.on { background: var(--primary); }
.switch.on i { left: 21px; background: var(--on-primary); }

.board-row { min-width: 560px; display: grid; grid-template-columns: 40px minmax(0, 1fr) 120px 110px 90px; gap: 16px; align-items: center; min-height: 56px; padding: 0 22px; font-size: 14px; }
.board-row + .board-row { box-shadow: inset 0 1px 0 hsl(var(--on) / .06); }
.board-headrow { min-height: 44px; font-size: 12px; color: var(--subtle); }
.board-row .end { text-align: right; }
.board-row > span:nth-child(n+4) { color: var(--muted); }
.board-row .rank { font-family: var(--mono); color: var(--subtle); }
.board-who { min-width: 0; display: flex; align-items: center; gap: 12px; }
.board-who > span:last-child { min-width: 0; display: grid; line-height: 18px; }
.board-who b { font-weight: 600; }
.board-who small { font-size: 12px; color: var(--subtle); }
.initials { flex: none; width: 30px; height: 30px; border-radius: 5px; display: inline-flex; align-items: center; justify-content: center; background: hsl(var(--on) / .08); font-size: 11px; font-weight: 600; }
.board-row .eff { font-size: 16px; font-weight: 500; }
.board-row.is-you { background: hsl(var(--on) / .04); }
.board-row.is-you .eff { color: var(--text); }
.board-row.is-you .initials { background: hsl(var(--on) / .16); }

.faq-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 36px 40px; }
.faq-item { padding-top: 18px; display: flex; flex-direction: column; gap: 8px; box-shadow: inset 0 1px 0 var(--faint); }
.faq-item h3 { font-size: 17px; line-height: 24px; font-weight: 500; }
.faq-item p { font-size: 14px; line-height: 22px; color: var(--muted); }
.faq-item a { color: var(--text); text-underline-offset: 3px; }
.faq-code { align-self: flex-start; max-width: 100%; padding: 6px 10px; border-radius: 8px; background: hsl(var(--on) / .04); box-shadow: inset 0 0 0 1px var(--faint); font-size: 12.5px !important; overflow-wrap: anywhere; }

.cta { margin: 112px 0 80px; padding: 48px 56px; display: flex; align-items: center; gap: 16px 40px; flex-wrap: wrap; border-radius: 8px; background: var(--raised); box-shadow: inset 0 0 0 1px var(--border-strong); }
.cta > span { flex: 1; min-width: 260px; display: flex; flex-direction: column; gap: 10px; }
.cta > span > span { color: var(--muted); }
.cta .btn + .btn { margin-left: -24px; }

@media (max-width: 1100px) {
  .hero h1 { font-size: 56px; line-height: 58px; }
  .steps { grid-template-columns: repeat(2, minmax(0, 1fr)); }
}
@media (max-width: 960px) {
  .landing-main { padding: 0 16px; }
  .hero { grid-template-columns: 1fr; gap: 40px; padding: 56px 0 56px; }
  .split-band { grid-template-columns: 1fr; gap: 28px; }
  .figures { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .figures > div:nth-child(3) { box-shadow: inset 0 1px 0 var(--faint); }
  .figures > div:nth-child(4) { box-shadow: inset 1px 0 0 var(--faint), inset 0 1px 0 var(--faint); }
  .band { padding-top: 80px; }
  .cta { padding: 32px 24px; margin: 80px 0 56px; }
  .cta .btn + .btn { margin-left: 0; }
}
@media (max-width: 600px) {
  .hero h1 { font-size: 44px; line-height: 46px; }
  .landing-main h2 { font-size: 32px; line-height: 36px; }
  .shot-row { grid-template-columns: 16px minmax(0, 1fr) 72px; }
  .shot-row .runway { display: none; }
  .shot-foot { flex-wrap: wrap; }
  .install-line { width: 100%; }
  .install-line code { flex: 1; overflow: hidden; text-overflow: ellipsis; }
  .hero-actions .btn { width: 100%; }
  .steps, .faq-grid { grid-template-columns: 1fr; }
  .figures b { font-size: 30px; }
  .settings-list li { padding: 16px 18px; }
  .cta .btn { width: 100%; }
  /* The table becomes one short block per tool, each value named. */
  .tool-table { min-width: 0; }
  .tool-table thead { display: none; }
  .tool-table tr { padding: 14px 18px; display: grid; gap: 6px; border-top: 1px solid hsl(var(--on) / .06); }
  .tool-table tbody tr:first-child { border-top: 0; }
  .tool-table th, .tool-table td, .tool-table th:first-child, .tool-table td:first-child { height: auto; padding: 0; border: 0; text-align: left; }
  .tool-table td[data-label] { display: grid; grid-template-columns: 120px minmax(0, 1fr); gap: 12px; }
  .tool-table td[data-label]::before { content: attr(data-label); color: var(--subtle); font-family: var(--sans); font-size: 13px; }
}
`;
