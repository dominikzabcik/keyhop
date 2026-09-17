import { html, raw } from "hono/html";
import type { Tool } from "./env";
import type { Html } from "./ui";
import { mark } from "./ui";

/**
 * The home page is built around one picture: accounts as lanes across a working day, limits
 * filling them, and a hop as the moment work moves from a full lane to one with room. It is the
 * same idea as Keyhop's mark, whose two arms fill as your nearest limits do.
 *
 * The day is drawn by one number, `--t`, from 0 at 09:00 to 1 at 18:00. Where the browser can tie
 * it to scrolling, the day plays out as the page scrolls. Everywhere else `--t` stays at 1 and the
 * whole day is simply shown, so nothing on the page waits on an animation to exist.
 */

// MARK: The hop board

const DAY_START = 9;
const DAY_HOURS = 9;
const ROW = 60;
const GROUP_GAP = 28;

interface Lane {
  tool: Tool;
  toolName: string;
  account: string;
  plan: string;
  /** What the lane says about its day, in Keyhop's own words. */
  note: string;
}

const LANES: Lane[] = [
  { tool: "claude", toolName: "Claude Code", account: "Personal", plan: "Max 5x", note: "5h limit reached 11:30" },
  { tool: "claude", toolName: "Claude Code", account: "Studio", plan: "Max 20x", note: "5h limit reached 15:15" },
  { tool: "claude", toolName: "Claude Code", account: "Team", plan: "Team", note: "48% left at 18:00" },
  { tool: "codex", toolName: "Codex", account: "Personal", plan: "Plus", note: "5h limit reached 13:40" },
  { tool: "codex", toolName: "Codex", account: "Work", plan: "Pro", note: "69% left at 18:00" },
];

/** Where each tool's work sits through the day: one lane at a time, hopping when a lane fills. */
const RUNS: Record<"claude" | "codex", { lane: number; from: string; to: string }[]> = {
  claude: [
    { lane: 0, from: "09:00", to: "11:30" },
    { lane: 1, from: "11:30", to: "15:15" },
    { lane: 2, from: "15:15", to: "18:00" },
  ],
  codex: [
    { lane: 3, from: "09:00", to: "13:40" },
    { lane: 4, from: "13:40", to: "18:00" },
  ],
};

/** 0 at the start of the day, 1 at its end. */
const at = (time: string) => {
  const [hours, minutes] = time.split(":").map(Number);
  return (hours + minutes / 60 - DAY_START) / DAY_HOURS;
};

/** The vertical centre of a lane, with a little room between the two tools. */
const laneY = (lane: number) => lane * ROW + (LANES[lane].tool === "codex" ? GROUP_GAP : 0) + ROW / 2;
const BOARD_HEIGHT = LANES.length * ROW + GROUP_GAP;
/** How long, in day fractions, a hop takes to draw. */
const HOP = 0.02;
const f = (n: number) => n.toFixed(4);

/** Each lane's rail: where an account could be used, whether it was or not. */
const railPaths = () => LANES.map((_, lane) => `<line class="rail" x1="0" x2="1000" y1="${laneY(lane)}" y2="${laneY(lane)}"/>`).join("");

/** The work itself. The layer is cut at the playhead, so the day so far is what shows. */
function boardPaths(): string {
  const parts: string[] = [];
  for (const runs of Object.values(RUNS)) {
    runs.forEach((run, index) => {
      const start = at(run.from) + (index ? HOP : 0);
      const end = at(run.to);
      const y = laneY(run.lane);
      const x0 = start * 1000;
      const x1 = end * 1000;
      parts.push(`<path class="run" d="M${x0.toFixed(1)} ${y}H${x1.toFixed(1)}"/>`);
      const next = runs[index + 1];
      if (next) {
        // The hop: an S from the full lane to the one with room.
        const y2 = laneY(next.lane);
        const x2 = (end + HOP) * 1000;
        parts.push(`<path class="run hop" d="M${x1.toFixed(1)} ${y}C${(x1 + 12).toFixed(1)} ${y} ${(x2 - 12).toFixed(1)} ${y2} ${x2.toFixed(1)} ${y2}"/>`);
        // The moment the lane filled: a closed cap where the run ends.
        parts.push(`<rect class="cap" x="${(x1 - 3).toFixed(1)}" y="${y - 7}" width="6" height="14" rx="3"/>`);
      }
    });
  }
  return parts.join("");
}

/** The marks where a hop happened, placed as HTML so their text stays crisp at any width. */
function hopNotes(): Html[] {
  const notes: Html[] = [];
  for (const runs of Object.values(RUNS)) {
    runs.slice(1).forEach((run) => {
      const x = at(run.from) * 100;
      const y = laneY(run.lane);
      notes.push(html`<span class="hop-note" style="left:${x.toFixed(2)}%;top:${y}px;--a:${f(at(run.from))}">hop ${run.from}</span>`);
    });
  }
  return notes;
}

/** "Claude Code on Studio" for each stretch of the day, one showing at a time. */
function readout(tool: "claude" | "codex", name: string): Html {
  const runs = RUNS[tool];
  return html`<span class="readout-row"><b>${name}</b><span class="readout-states">${runs.map((run, index) => {
    const from = index ? at(run.from) : -1;
    const to = index === runs.length - 1 ? 2 : at(run.to);
    const lane = LANES[run.lane];
    return html`<span class="state" style="--a:${f(from)};--b:${f(to)}">on ${lane.account}</span>`;
  })}</span></span>`;
}

function hopBoard(): Html {
  return html`<figure class="board" aria-label="A working day in Keyhop: Claude Code moves from Personal to Studio at 11:30 and to Team at 15:15, and Codex moves from Personal to Work at 13:40, each time an account's five-hour limit fills.">
    <div class="board-top" aria-hidden="true">
      <span class="clock"><span class="clock-static">18:00</span></span>
      ${readout("claude", "Claude Code")}
      ${readout("codex", "Codex")}
    </div>
    <div class="board-body" aria-hidden="true">
      <div class="lanes">
        ${LANES.map((lane, index) => html`<div class="lane${index === 3 ? " group-start" : ""}">
          ${index === 0 || index === 3 ? mark(lane.tool) : html`<span class="mark-space"></span>`}
          <span class="lane-name"><b>${index === 0 || index === 3 ? html`<span class="tool-name">${lane.toolName}</span> ` : ""}${lane.account}</b><small>${lane.plan} · ${lane.note}</small></span>
        </div>`)}
      </div>
      <div class="tracks" style="height:${BOARD_HEIGHT}px">
        <svg viewBox="0 0 1000 ${BOARD_HEIGHT}" preserveAspectRatio="none">${raw(railPaths())}</svg>
        <svg class="day" viewBox="0 0 1000 ${BOARD_HEIGHT}" preserveAspectRatio="none">${raw(boardPaths())}</svg>
        ${hopNotes()}
        <span class="playhead"></span>
        <div class="hours"><span>09:00</span><span>12:00</span><span>15:00</span><span>18:00</span></div>
      </div>
    </div>
  </figure>`;
}

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
const INSTALL_WINDOWS = "irm https://raw.githubusercontent.com/dominikzabcik/keyhop/main/install.ps1 | iex";

const command = (label: string, text: string) => html`<div class="command">
  <div class="command-top"><span>${label}</span><button class="copy" type="button" data-copy="${text}">Copy</button></div>
  <code>${text}</code>
</div>`;

export function landingPage(): Html {
  return html`
    <section class="hop" id="product">
      <div class="hop-stage">
        <header class="hop-head">
          <h1><span class="line">Every account.</span><span class="line tone">One hop away.</span></h1>
          <div class="hop-intro">
            <p>Keyhop watches the limits on every account you own and moves your tools to the one with room, before a limit stops you.</p>
            <div class="hop-action">
              <a class="btn" href="/download">Download Keyhop</a>
              <span>Free and open source, for macOS, Linux and Windows</span>
            </div>
          </div>
        </header>
        ${hopBoard()}
      </div>
    </section>

    <section class="band ledger" id="privacy">
      <h2>Keyhop moves logins between your tools. <span class="tone">Your work never leaves your computer.</span></h2>
      <div class="ledger-grid">
        <div>
          <h3>What Keyhop handles</h3>
          <dl>
            <dt>The logins you already have</dt><dd>Saved in your system's own vault: Keychain, Secret Service or DPAPI. Handed to each tool through the path it already reads.</dd>
            <dt>Limit readings</dt><dd>Asked of each provider with that account's own login, and kept on your computer.</dd>
            <dt>Daily totals, if you link GitHub</dt><dd>Tokens, API value and requests per tool per day, for the leaderboard.</dd>
            <dt>Current limits, if you share them</dt><dd>How full each account is and when it resets, so your phone can count down. No history is kept.</dd>
          </dl>
        </div>
        <div>
          <h3>What never leaves</h3>
          <dl>
            <dt>Your prompts and your code</dt><dd>Keyhop counts usage. It never reads what was asked or written.</dd>
            <dt>Provider tokens</dt><dd>They stay in your vault and are never sent to keyhop.app.</dd>
            <dt>Emails and account names</dt><dd>Only a name you type for an account travels, and only if you share limits.</dd>
            <dt>Analytics</dt><dd>There are none, on the app or the website.</dd>
          </dl>
        </div>
      </div>
    </section>

    <section class="band tools" id="tools">
      <h2>Nine tools, each switched the way it already signs in.</h2>
      <div class="table-scroll">
        <table class="tool-table">
          <thead><tr><th scope="col">Tool</th><th scope="col">Limits</th><th scope="col">Usage history</th><th scope="col">How Keyhop switches it</th></tr></thead>
          <tbody>
            ${TOOL_ROWS.map((row) => html`<tr${row.history === "Not exposed" ? raw(' class="quiet"') : ""}>
              <th scope="row">${mark(row.tool)}${row.name}</th>
              <td data-label="Limits">${row.limits}</td>
              <td data-label="Usage history">${row.history}</td>
              <td data-label="Switches through">${row.how}</td>
            </tr>`)}
          </tbody>
        </table>
      </div>
      <p class="band-note">Keyhop only moves between accounts you own. It can't raise a plan's limits, and every provider's terms still apply.</p>
    </section>

    <section class="band elsewhere" id="roadmap">
      <h2>Your agents and your phone can read the runway too.</h2>
      <div class="elsewhere-grid">
        <div class="elsewhere-item">
          <h3>For coding agents</h3>
          <p><code>keyhop mcp</code> serves three read-only tools, so an agent can check the room left before a long run. It can't see credentials, and it can't switch.</p>
          <dl class="mcp-tools">
            <dt><code>keyhop_status</code></dt><dd>Accounts, limits, budgets and alerts</dd>
            <dt><code>keyhop_usage</code></dt><dd>Token, request and API value history</dd>
            <dt><code>keyhop_recommendation</code></dt><dd>The account with the most runway</dd>
          </dl>
        </div>
        <div class="elsewhere-item">
          <h3>On your phone</h3>
          <p>The iOS companion counts down to each reset and tells you the moment an account comes back. It builds from source today.</p>
          <div class="ping" aria-label="Example notification">
            <div class="ping-top"><span class="ping-app">Keyhop</span><span>now</span></div>
            <b>Codex · Work is ready</b>
            <span>The 5h limit just reset.</span>
          </div>
        </div>
      </div>
    </section>

    <section class="band social">
      <div class="social-copy">
        <h2>Compare the work, never the prompts.</h2>
        <p>Link GitHub for a public profile, private team boards and a ranked season every month. Only daily totals per tool are shared.</p>
        <a class="text-link" href="/leaderboard">See this week's leaderboard</a>
      </div>
      <ol class="mini-board" aria-label="Example leaderboard">
        ${[
          ["mira", "1.8B", 100],
          ["kai", "1.4B", 78],
          ["alex", "986M", 55],
          ["ren", "822M", 46],
        ].map(([login, total, share], index) => html`<li>
          <span class="rank">${index + 1}</span>
          <span class="who-name">${login}</span>
          <span class="bar"><i style="width:${share}%"></i></span>
          <span class="total">${total}</span>
        </li>`)}
      </ol>
    </section>

    <section class="band install" id="install">
      <div class="install-copy">
        <h2>Installed in a minute.</h2>
        <p>The installer picks the right package for your system and checks its SHA-256 before anything is installed. Homebrew, Scoop, RPM, DEB and Arch packages are there too.</p>
        <a class="btn" href="/download">All downloads</a>
      </div>
      <div class="install-commands">
        ${command("macOS and Linux", INSTALL_UNIX)}
        ${command("Windows PowerShell", INSTALL_WINDOWS)}
      </div>
    </section>

    <section class="band faq">
      <h2>Before you hand over a login.</h2>
      <div class="faq-list">
        <details><summary>Does Keyhop share accounts or add usage?</summary><p>No. Keyhop only switches between accounts you already own. It cannot increase a plan's limits, and every provider's terms still apply.</p></details>
        <details><summary>What exactly changes when I switch?</summary><p>Keyhop saves the login the tool is using, loads the one you chose, hands it to the tool through its normal credential path, and reads it back to confirm the switch.</p></details>
        <details><summary>Where are my provider tokens stored?</summary><p>In Login Keychain on macOS, Secret Service or private files on Linux, and DPAPI-encrypted files on Windows. Provider tokens are never sent to keyhop.app.</p></details>
        <details><summary>Do I have to use the leaderboard?</summary><p>No. Switching, limits, history, budgets and alerts all work without a Keyhop cloud account. Leaderboards and teams are opt-in.</p></details>
        <details><summary>What does "API value" mean?</summary><p>Keyhop prices the tokens you used at each provider's standard API rates. It shows the value of your usage, not a bill from your subscription.</p></details>
        <details><summary>Why do some tools show no usage history?</summary><p>GitHub Copilot, Windsurf and Codebuff don't keep a complete record of model tokens on your computer, so Keyhop shows the limits they report and doesn't invent totals.</p></details>
        <details><summary>Is the phone app in the App Store?</summary><p>Not yet. The iOS companion builds from source with seasons, quests, badges, shared limits and alerts when a limit comes back. Android and automations are still planned.</p></details>
        <details><summary>Can I inspect or build Keyhop myself?</summary><p>Yes. Keyhop is MIT licensed, its installers are readable shell scripts, and the app, the website, the packaging and the tests are all in the public repository.</p></details>
      </div>
    </section>
  `;
}

// MARK: Styles

export const LANDING_CSS = `
/* The day's position, from 0 at 09:00 to 1 at 18:00. It rests at 1, so without scroll-driven
   animation the whole day is drawn and nothing waits to appear. */
@property --t { syntax: "<number>"; inherits: true; initial-value: 1; }
@property --mins { syntax: "<integer>"; inherits: true; initial-value: 540; }

.landing .backdrop { height: 900px; min-height: 0; }
.landing .backdrop::after { height: 55%; }
.landing .top-inner, .landing .site-foot { max-width: 1180px; }
.landing .top { border-color: transparent; }
.landing-main { max-width: 1180px; padding: 0 24px; display: block; }
body.landing { overflow-x: clip; }
.landing-main h1, .landing-main h2, .landing-main h3, .landing-main p, .landing-main dl, .landing-main dd { margin: 0; }
.landing-main h2 { max-width: 820px; font-size: clamp(28px, 3.6vw, 46px); line-height: 1.08; letter-spacing: -.04em; font-weight: 650; text-wrap: balance; }
.landing-main h3 { font-size: 15px; font-weight: 620; letter-spacing: -.01em; }
.landing-main .tone { color: var(--muted); }
.landing-main .btn { height: 42px; padding: 0 18px; border-radius: 9px; }
.landing-main code { font-family: var(--mono); font-size: .92em; color: hsl(0 0% 80%); }

/* The first screen. */
.hop-stage { min-height: calc(100vh - 56px); padding: 64px 0 40px; display: flex; flex-direction: column; justify-content: center; gap: 44px; }
.hop-head { display: grid; grid-template-columns: minmax(0, 1.25fr) minmax(0, .75fr); gap: 48px; align-items: end; }
.hop-head h1 { font-size: clamp(46px, 6vw, 84px); line-height: .98; letter-spacing: -.055em; font-weight: 680; }
.hop-head h1 .line { display: block; white-space: nowrap; }
.hop-intro { display: grid; gap: 22px; padding-bottom: 8px; }
.hop-intro p { color: hsl(0 0% 72%); font-size: 17px; line-height: 1.55; text-wrap: pretty; }
.hop-action { display: flex; align-items: center; gap: 16px; flex-wrap: wrap; }
.hop-action span { color: var(--subtle); font-size: 12.5px; }

/* The board. */
.board { margin: 0; padding: 22px 24px 18px; border: 1px solid hsl(0 0% 100% / .09); border-radius: 16px; background: hsl(0 0% 8.5% / .78); box-shadow: inset 0 1px 0 hsl(0 0% 100% / .05); -webkit-backdrop-filter: blur(14px); backdrop-filter: blur(14px); }
.board-top { margin-bottom: 18px; display: flex; align-items: baseline; gap: 28px; flex-wrap: wrap; }
.clock { min-width: 64px; font: 600 22px/1 var(--mono); letter-spacing: -.02em; font-variant-numeric: tabular-nums; }
.readout-row { display: inline-flex; align-items: baseline; gap: 8px; color: var(--muted); font-size: 13px; }
.readout-row b { color: var(--text); font-weight: 600; }
.readout-states { display: inline-grid; }
.readout-states .state { grid-area: 1 / 1; white-space: nowrap;
  opacity: calc(clamp(0, (var(--t) - var(--a)) * 1000, 1) * clamp(0, (var(--b) - var(--t)) * 1000, 1)); }
.board-body { display: grid; grid-template-columns: 230px minmax(0, 1fr); gap: 20px; }
.lanes { display: grid; grid-template-rows: repeat(3, ${ROW}px) ${ROW + GROUP_GAP}px ${ROW}px; }
.lane { display: flex; align-items: center; gap: 10px; min-width: 0; }
.lane.group-start { padding-top: ${GROUP_GAP}px; }
.lane .mark { width: 16px; height: 16px; flex: none; fill: var(--text); }
.mark-space { width: 16px; flex: none; }
.lane-name { min-width: 0; display: grid; gap: 2px; }
.lane-name b { font-size: 13px; font-weight: 600; white-space: nowrap; }
.lane-name .tool-name { color: var(--muted); font-weight: 500; }
.lane-name small { overflow: hidden; color: var(--subtle); font-size: 11.5px; text-overflow: ellipsis; white-space: nowrap; }
.tracks { position: relative; }
.tracks svg { position: absolute; inset: 0; width: 100%; height: 100%; overflow: visible; }
.rail { stroke: hsl(0 0% 100% / .07); stroke-width: 6; stroke-linecap: round; vector-effect: non-scaling-stroke; }
.run { fill: none; stroke: hsl(0 0% 90%); stroke-width: 6; stroke-linecap: round; vector-effect: non-scaling-stroke;
}
.day { clip-path: inset(-12px calc((1 - var(--t)) * 100% - 8px) -12px -12px); }
.run.hop { stroke: hsl(0 0% 72%); stroke-width: 2.5; }
.cap { fill: hsl(34 58% 62%); }
.hop-note { position: absolute; transform: translate(-50%, -26px); padding: 2px 6px; border-radius: 5px; color: var(--muted); background: hsl(0 0% 8.5%); font: 11px/1.4 var(--mono); white-space: nowrap; pointer-events: none;
  opacity: clamp(0, (var(--t) - var(--a)) * 60, 1); }
.playhead { position: absolute; top: -8px; bottom: -4px; left: calc(var(--t) * 100%); width: 1px; background: hsl(0 0% 100% / .22); }
.hours { position: absolute; left: 0; right: 0; bottom: -26px; display: flex; justify-content: space-between; color: var(--subtle); font: 11px/1 var(--mono); }
.board-body { padding-bottom: 24px; }

/* Where the browser can, the day plays out while the first screen is pinned. */
@supports (animation-timeline: view()) {
  @media (prefers-reduced-motion: no-preference) and (min-width: 861px) and (min-height: 760px) {
    .hop { height: 240vh; animation: hop-day linear both; animation-timeline: view(); animation-range: contain 0% contain 100%; }
    .hop-stage { position: sticky; top: 0; height: 100vh; min-height: 0; }
    .clock { --mins: calc(var(--t) * 540); counter-reset: hh calc(9 + round(down, var(--mins) / 60, 1)) mm calc(var(--mins) - round(down, var(--mins) / 60, 1) * 60); }
    .clock::before { content: counter(hh, decimal-leading-zero) ":" counter(mm, decimal-leading-zero); }
    .clock-static { display: none; }
  }
}
@keyframes hop-day { from { --t: .015; } to { --t: 1; } }

/* The sections after it: plain bands, each opening with what it has to say. */
.band { padding: 108px 0; }
.band > h2, .social-copy h2, .install-copy h2 { margin-bottom: 40px; }
.band-note { margin-top: 22px; color: var(--subtle); font-size: 13px; }

.ledger-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 56px; }
.ledger-grid h3 { color: var(--muted); }
.ledger-grid dt { margin-top: 20px; font-weight: 600; }
.ledger-grid dd { margin-top: 4px; color: var(--muted); line-height: 1.55; }

.table-scroll { overflow-x: auto; }
.tool-table { width: 100%; min-width: 720px; border-collapse: collapse; }
.tool-table th, .tool-table td { padding: 13px 16px 13px 0; border-bottom: 1px solid hsl(0 0% 100% / .07); text-align: left; vertical-align: middle; }
.tool-table thead th { color: var(--subtle); font-size: 12.5px; font-weight: 520; }
.tool-table tbody th { font-weight: 600; white-space: nowrap; }
.tool-table tbody th .mark { width: 16px; height: 16px; margin: -3px 12px 0 0; vertical-align: middle; fill: var(--text); }
.tool-table td { color: var(--muted); }
.tool-table tr.quiet td:nth-child(3) { color: var(--subtle); }

.elsewhere-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 56px; }
.elsewhere-item { display: grid; gap: 14px; align-content: start; }
.elsewhere-item > p { max-width: 460px; color: var(--muted); line-height: 1.6; }
.mcp-tools { margin-top: 8px; display: grid; grid-template-columns: auto 1fr; gap: 12px 20px; }
.mcp-tools dd { color: var(--muted); }
.ping { max-width: 360px; margin-top: 8px; padding: 14px 16px; display: grid; gap: 3px; border-radius: 16px; background: hsl(0 0% 16% / .9); box-shadow: inset 0 1px 0 hsl(0 0% 100% / .06); }
.ping-top { margin-bottom: 4px; display: flex; justify-content: space-between; color: var(--subtle); font-size: 12px; }
.ping-app { color: var(--muted); font-weight: 600; }
.ping b { font-weight: 600; }
.ping > span:last-child { color: var(--muted); }

.social { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 56px; align-items: center; }
.social-copy h2 { margin-bottom: 18px; }
.social-copy p { max-width: 460px; margin-bottom: 18px; color: var(--muted); line-height: 1.6; }
.social-copy .text-link { margin-left: -10px; }
.mini-board { margin: 0; padding: 0; list-style: none; }
.mini-board li { padding: 12px 0; display: grid; grid-template-columns: 28px 90px minmax(0, 1fr) 64px; gap: 14px; align-items: center; border-bottom: 1px solid hsl(0 0% 100% / .07); }
.mini-board .rank { color: var(--subtle); font-variant-numeric: tabular-nums; }
.mini-board .who-name { font-weight: 560; }
.mini-board .bar { height: 6px; border-radius: 99px; background: hsl(0 0% 100% / .07); overflow: hidden; }
.mini-board .bar i { display: block; height: 100%; border-radius: inherit; background: hsl(0 0% 80%); }
.mini-board .total { text-align: right; font-variant-numeric: tabular-nums; }

.install { display: grid; grid-template-columns: minmax(0, .8fr) minmax(0, 1.2fr); gap: 56px; align-items: start; }
.install-copy h2 { margin-bottom: 18px; }
.install-copy p { max-width: 420px; margin-bottom: 24px; color: var(--muted); line-height: 1.6; }
.install-commands { display: grid; gap: 12px; }
.command { padding: 12px 14px 15px 17px; display: grid; gap: 8px; border: 1px solid var(--border); border-radius: 10px; background: #111; }
.command-top { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.command-top span { color: var(--subtle); font-size: 12px; font-weight: 520; }
.command code { font: 12.5px/1.6 var(--mono); white-space: pre-wrap; overflow-wrap: anywhere; }

.faq-list { max-width: 860px; border-top: 1px solid hsl(0 0% 100% / .08); }
.faq-list details { border-bottom: 1px solid hsl(0 0% 100% / .08); }
.faq-list summary { min-height: 62px; display: flex; align-items: center; justify-content: space-between; gap: 20px; cursor: pointer; font-weight: 560; list-style: none; }
.faq-list summary::-webkit-details-marker { display: none; }
.faq-list summary::after { content: "+"; color: var(--subtle); font-size: 18px; }
.faq-list details[open] summary::after { content: "−"; }
.faq-list details p { max-width: 700px; margin: -4px 0 22px; color: var(--muted); line-height: 1.6; }

@media (max-width: 860px) {
  .landing-main { padding: 0 16px; }
  .hop-stage { min-height: 0; padding: 56px 0 24px; gap: 32px; }
  .hop-head { grid-template-columns: 1fr; gap: 24px; }
  .hop-head h1 .line { white-space: normal; }
  .board { padding: 18px 16px 14px; }
  .board-body { grid-template-columns: 120px minmax(0, 1fr); gap: 12px; }
  .lane-name .tool-name, .lane-name small { display: none; }
  .hop-note { font-size: 10px; }
  .band { padding: 80px 0; }
  .ledger-grid, .elsewhere-grid, .social, .install { grid-template-columns: 1fr; gap: 40px; }
}
@media (max-width: 600px) {
  .hop-head h1 { font-size: clamp(40px, 12.5vw, 56px); }
  .hop-action { flex-direction: column; align-items: stretch; }
  .hop-action .btn { justify-content: center; }
  .board-top { gap: 10px 18px; }
  .board-body { grid-template-columns: 96px minmax(0, 1fr); }
  .lane { gap: 8px; }
  .mini-board li { grid-template-columns: 22px 64px minmax(0, 1fr) 52px; gap: 10px; }
  /* The table becomes one short block per tool, each value named. */
  .tool-table { min-width: 0; }
  .tool-table thead { display: none; }
  .tool-table tr { padding: 16px 0; display: grid; gap: 6px; border-bottom: 1px solid hsl(0 0% 100% / .07); }
  .tool-table th, .tool-table td { padding: 0; border: 0; }
  .tool-table tbody th { margin-bottom: 4px; }
  .tool-table td { display: grid; grid-template-columns: 124px minmax(0, 1fr); gap: 12px; }
  .tool-table td::before { content: attr(data-label); color: var(--subtle); }
}
`;
