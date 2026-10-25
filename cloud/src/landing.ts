import { html, raw } from "hono/html";
import { MEASURED_TOOLS, type Tool, TOOL_NAMES } from "./env";
import { creatureMarkup, petFrom } from "./pet";
import type { Html } from "./ui";
import { mark } from "./ui";

/**
 * The home page, as the KB-Web board in design/keyhop-v2/canvas draws it: the offer and the
 * install line beside a night field where three sample logins sit and the pet offers the hop,
 * then the figures, how a hop works, the tools, the settings people touch, the season, and
 * questions. Every sample on it says it is one.
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

// MARK: The night field

/** The same seeded stars as the board, so the picture never changes between visits. */
function stars(): string {
  let seed = 5;
  const rnd = () => ((seed = (seed * 9301 + 49297) % 233280), seed / 233280);
  return Array.from({ length: 44 }, (_, i) => {
    const x = Math.round(rnd() * 400), y = Math.round(rnd() * 210), r = rnd() > 0.85 ? 2.2 : 1.3;
    return `<rect class="star" style="--i:${i}" x="${x}" y="${y}" width="${r}" height="${r}"/>`;
  }).join("");
}

interface SampleLogin { tool: Tool; who: string; sub: string; left: number; state: "in-use" | "pick" | "out" }

const SAMPLE_LOGINS: SampleLogin[] = [
  { tool: "claude", who: "Personal · Claude Code", sub: "Max 5x · empty ~12:43 PM", left: 49, state: "in-use" },
  { tool: "claude", who: "work@studio.dev · Claude Code", sub: "Pro · 5-hour 12%, weekly 41%", left: 59, state: "pick" },
  { tool: "codex", who: "me@personal.dev · Codex", sub: "Plus · runs out ~11:19 AM", left: 7, state: "out" },
];

/** A sample pet: Bulk, mostly Claude Code, on a twelve-day streak. */
const SAMPLE_PET = creatureMarkup(petFrom({ tokens: 800_000_000, tools: { claude: 1 }, streak: 12, commits: 12_160 }), "field-pet");

function nightField(): Html {
  return html`<figure class="field" aria-label="Sample accounts: Claude Code's Personal login empties around 12:43 PM, and Keyhop offers to hop it to work@studio.dev, which is 12% into its window.">
    <svg class="field-sky" viewBox="0 0 400 300" preserveAspectRatio="xMidYMax slice" aria-hidden="true">
      ${raw(stars())}
      <path d="M0 236 C 70 214 140 220 210 228 C 280 236 340 216 400 222 L400 300 L0 300 Z" fill="#1C1F26"/>
      <path d="M0 266 C 100 252 210 256 300 262 C 350 265 380 264 400 262 L400 300 L0 300 Z" fill="#171A20"/>
    </svg>
    <div class="field-rows" aria-hidden="true">
      ${SAMPLE_LOGINS.map((row) => html`<div class="field-row ${row.state}">
        <span class="tool-chip">${mark(row.tool)}</span>
        <span class="field-who"><b>${row.who}</b><small>${row.sub}</small></span>
        <span class="meter"><i style="width:${row.left}%"></i></span>
        <span class="field-left">${row.left}%</span>
      </div>`)}
    </div>
    <div class="field-foot" aria-hidden="true">
      <div class="bubble"><b>Claude Code is running low.</b><span>Personal empties around 12:43 PM. Hop it to work@studio.dev, 12% into its window?</span><span class="bubble-actions"><span class="bubble-hop">Hop</span><span class="bubble-later">Later</span></span></div>
      <div class="field-pet-wrap">${raw(SAMPLE_PET)}<span class="shadow"></span></div>
    </div>
    <figcaption>Sample accounts</figcaption>
  </figure>`;
}

// MARK: Sections

const FIGURES: [string, string][] = [
  ["9", "AI coding tools it can switch"],
  ["6", "of them with a full token history"],
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
      ${nightField()}
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
.btn.lg { height: 44px; padding: 0 22px; border-radius: 10px; font-size: 15px; }
.btn.lg svg { width: 16px; height: 16px; fill: none; }

/* The first screen: the offer beside the night field. */
.hero { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1.05fr); gap: 56px; align-items: center; padding: 96px 0 88px; }
.hero-copy { display: flex; flex-direction: column; gap: 24px; }
.hero h1 { font-size: 72px; line-height: 72px; font-weight: 500; letter-spacing: -.045em; text-wrap: balance; }
.hero-copy > p { max-width: 44ch; font-size: 17px; line-height: 27px; color: var(--muted); }
.hero-actions { margin-top: 8px; display: flex; flex-wrap: wrap; gap: 10px; }
.install-line { height: 44px; padding: 0 8px 0 16px; display: flex; align-items: center; gap: 12px; border-radius: 10px; background: hsl(var(--on) / .03); box-shadow: inset 0 0 0 1px var(--border); font-family: var(--mono); font-size: 13px; }
.install-line .prompt { color: var(--subtle); }
.install-line code { font-size: 13px; white-space: nowrap; }
.hero-note { font-size: 13px; color: var(--subtle); }

/* The field is always the night, in either theme: it is a picture of the app's own field. */
.field { position: relative; height: 520px; margin: 0; overflow: hidden; border-radius: 16px; background: radial-gradient(80% 55% at 70% 100%, rgba(96, 165, 250, .30), transparent 72%), #13151a; box-shadow: inset 0 0 0 1px rgba(255, 255, 255, .10); color: #f5f5f5; }
.field-sky { position: absolute; inset: 0; width: 100%; height: 100%; }
.field-sky .star { fill: #fff; opacity: .35; }
.field-rows { position: absolute; top: 22px; left: 22px; right: 22px; display: grid; gap: 8px; }
.field-row { display: grid; grid-template-columns: 30px minmax(0, 1fr) 140px 52px; gap: 14px; align-items: center; padding: 12px 14px; border-radius: 10px; background: rgba(26, 26, 26, .86); box-shadow: inset 0 0 0 1px rgba(255, 255, 255, .10); }
.field-row.pick { box-shadow: inset 0 0 0 1px rgba(96, 165, 250, .55); }
.tool-chip { flex: none; width: 30px; height: 30px; border-radius: 8px; display: inline-flex; align-items: center; justify-content: center; background: rgba(255, 255, 255, .05); box-shadow: inset 0 0 0 1px rgba(255, 255, 255, .08); }
.field .mark { width: 16px; height: 16px; fill: #e5e5e5; }
.field-who { min-width: 0; display: grid; line-height: 18px; }
.field-who b { font-size: 13px; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.field-who small { font-size: 12px; color: #8a8a8a; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.meter { height: 4px; border-radius: 2px; background: rgba(255, 255, 255, .08); overflow: hidden; }
.meter i { display: block; height: 100%; border-radius: inherit; background: rgba(255, 255, 255, .78); }
.field-row.pick .meter i { background: #60a5fa; }
.field-row.out .meter i { background: #fb414a; }
.field-left { text-align: right; font-size: 13px; font-weight: 600; }
.field-row.out .field-left { color: #ff8a82; }
.field-foot { position: absolute; left: 28px; right: 28px; bottom: 36px; display: flex; align-items: flex-end; justify-content: space-between; gap: 16px; }
.bubble { max-width: 290px; margin-bottom: 72px; padding: 12px 14px; display: grid; gap: 2px; border-radius: 10px 10px 2px 10px; background: #f5f5f5; color: #1d1d1f; font-size: 13px; line-height: 18px; box-shadow: 0 10px 28px rgba(0, 0, 10, .45); }
.bubble b { font-weight: 600; }
.bubble > span { color: #48484a; }
.bubble-actions { margin-top: 8px; display: flex; gap: 6px; }
.bubble-actions span { height: 28px; padding: 0 13px; display: inline-flex; align-items: center; border-radius: 7px; font-size: 12px; font-weight: 500; background: rgba(0, 0, 0, .06); color: #3a3a3c; }
.bubble-actions .bubble-hop { background: #60a5fa; color: #0a1628; font-weight: 600; }
.field-pet-wrap { flex: none; display: flex; flex-direction: column; align-items: center; }
.field-pet { width: 104px; height: auto; }
.shadow { width: 64px; height: 9px; margin-top: 2px; border-radius: 50%; background: #000; opacity: .45; }
.field figcaption { position: absolute; left: 22px; bottom: 12px; font-size: 11px; color: #8a8a8a; }
@media (prefers-reduced-motion: no-preference) {
  .field-pet { animation: field-hop 2.4s cubic-bezier(.3, .7, .3, 1) infinite; transform-origin: 50% 100%; }
  .shadow { animation: field-shade 2.4s cubic-bezier(.3, .7, .3, 1) infinite; }
  .field-sky .star { animation: field-twinkle 3.2s ease-in-out infinite; animation-delay: calc(var(--i) * -.37s); }
  .bubble { animation: field-bubble .6s cubic-bezier(.2, .8, .2, 1) .5s both; }
}
@keyframes field-hop { 0%, 55%, 100% { transform: translateY(0) scale(1, 1); } 62% { transform: translateY(0) scale(1.08, .9); } 75% { transform: translateY(-16px) scale(.96, 1.05); } 88% { transform: translateY(0) scale(1.05, .94); } }
@keyframes field-shade { 0%, 55%, 100% { transform: scaleX(1); opacity: .45; } 75% { transform: scaleX(.6); opacity: .2; } }
@keyframes field-twinkle { 0%, 100% { opacity: .15; } 50% { opacity: .55; } }
@keyframes field-bubble { from { opacity: 0; transform: translateY(6px) scale(.96); } to { opacity: 1; transform: none; } }

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
.panel { margin: 0; padding: 0; border-radius: 12px; background: var(--panel); box-shadow: inset 0 0 0 1px var(--border); overflow: hidden; list-style: none; }

.steps { margin: 0; padding: 0; list-style: none; display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; }
.step { padding: 24px; display: flex; flex-direction: column; gap: 14px; border-radius: 12px; background: var(--panel); box-shadow: inset 0 0 0 1px var(--border); transition: box-shadow .25s ease; }
.step:hover { box-shadow: inset 0 0 0 1px var(--border-strong); }
.step-top { display: flex; align-items: center; justify-content: space-between; }
.step-n { width: 28px; height: 28px; border-radius: 8px; display: inline-flex; align-items: center; justify-content: center; background: hsl(var(--on) / .06); font: 600 12px var(--mono); }
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
.tag { display: inline-flex; height: 22px; padding: 0 8px; align-items: center; border-radius: 6px; background: hsl(var(--on) / .06); color: var(--muted); font-size: 12px; font-weight: 600; white-space: nowrap; }
.tag.counted { background: color-mix(in srgb, var(--primary) 14%, transparent); color: var(--info); }

.settings-list li { padding: 20px 24px; display: flex; align-items: center; gap: 24px; }
.settings-list li + li { box-shadow: inset 0 1px 0 hsl(var(--on) / .06); }
.settings-list li > span:first-child { flex: 1; min-width: 0; display: grid; gap: 2px; }
.settings-list b { font-weight: 600; }
.settings-list li > span:first-child > span { font-size: 14px; line-height: 22px; color: var(--muted); }
.switch { position: relative; flex: none; width: 40px; height: 22px; border-radius: 7px; background: hsl(var(--on) / .14); }
.switch i { position: absolute; top: 3px; left: 3px; width: 16px; height: 16px; border-radius: 5px; background: #f5f5f5; }
.switch.on { background: var(--primary); }
.switch.on i { left: 21px; }

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
.initials { flex: none; width: 30px; height: 30px; border-radius: 8px; display: inline-flex; align-items: center; justify-content: center; background: hsl(var(--on) / .08); font-size: 11px; font-weight: 600; }
.board-row .eff { font-size: 16px; font-weight: 500; }
.board-row.is-you { background: color-mix(in srgb, var(--primary) 7%, transparent); }
.board-row.is-you .eff { color: var(--info); }
.board-row.is-you .initials { background: color-mix(in srgb, var(--primary) 25%, transparent); }

.faq-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 36px 40px; }
.faq-item { padding-top: 18px; display: flex; flex-direction: column; gap: 8px; box-shadow: inset 0 1px 0 var(--faint); }
.faq-item h3 { font-size: 17px; line-height: 24px; font-weight: 500; }
.faq-item p { font-size: 14px; line-height: 22px; color: var(--muted); }
.faq-item a { color: var(--text); text-underline-offset: 3px; }
.faq-code { align-self: flex-start; max-width: 100%; padding: 6px 10px; border-radius: 8px; background: hsl(var(--on) / .04); box-shadow: inset 0 0 0 1px var(--faint); font-size: 12.5px !important; overflow-wrap: anywhere; }

.cta { margin: 112px 0 80px; padding: 48px 56px; display: flex; align-items: center; gap: 16px 40px; flex-wrap: wrap; border-radius: 16px; background: radial-gradient(60% 120% at 85% 100%, color-mix(in srgb, var(--primary) 22%, transparent), transparent 70%), var(--panel); box-shadow: inset 0 0 0 1px var(--border); }
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
  .field { height: 480px; }
  .field-row { grid-template-columns: 30px minmax(0, 1fr) 44px; }
  .field-row .meter { display: none; }
  .bubble { margin-bottom: 64px; }
  .field-pet { width: 80px; }
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
