import { html, raw } from "hono/html";
import type { Html } from "./ui";
import { PIXEL_MARK, mark } from "./ui";

const arrow = () => html`<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8h9M8.5 4.5 12 8l-3.5 3.5"/></svg>`;

const dashboardIcon = (path: string) =>
  raw(`<svg viewBox="0 0 16 16" aria-hidden="true"><path d="${path}"/></svg>`);

export function landingPage(): Html {
  return html`
    <section class="landing-hero">
      <div class="hero-copy">
        <span class="landing-kicker">Free and open source</span>
        <h1>Every account.<br><span>One hop away.</span></h1>
        <p>Switch Claude Code, Cursor and Codex accounts before a limit slows you down. Keyhop keeps usage, resets and budgets in one quiet app.</p>
        <div class="hero-actions">
          <a class="btn" href="/download">Download Keyhop ${arrow()}</a>
          <a class="btn secondary" href="#install">Install from the terminal</a>
        </div>
        <div class="hero-note"><span>macOS, Linux and Windows</span><span>No telemetry</span></div>
        <div class="tool-strip" aria-label="Supported tools">
          <span class="tool-pill">${mark("claude")}Claude Code</span>
          <span class="tool-pill">${mark("cursor")}Cursor</span>
          <span class="tool-pill">${mark("codex")}Codex</span>
        </div>
      </div>

      <div class="product-stage" aria-hidden="true">
        <div class="product-window">
          <div class="product-titlebar"><i class="window-dot"></i><i class="window-dot"></i><i class="window-dot"></i><span class="title">Keyhop</span></div>
          <div class="product-shell">
            <aside class="product-sidebar">
              <div class="product-brand">${raw(PIXEL_MARK)}Keyhop</div>
              <span class="sidebar-link active">${dashboardIcon("M2.5 2.5h4v4h-4zm7 0h4v4h-4zm-7 7h4v4h-4zm7 0h4v4h-4z")}Overview</span>
              <span class="sidebar-link">${dashboardIcon("M5.5 7a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Zm-4 6.5c.3-2.6 1.6-4 4-4s3.7 1.4 4 4m.2-10.6a2.5 2.5 0 0 1 0 4.8m1.8 1.8c1.7.4 2.7 1.7 3 4")}Accounts</span>
              <span class="sidebar-link">${dashboardIcon("M2 13.5h12M3.5 11V7m3 4V3m3 8V6m3 5V1.5")}Usage</span>
              <span class="sidebar-link">${dashboardIcon("M2.5 4h11v8h-11zM2.5 6.5h11")}Budgets</span>
              <span class="sidebar-link">${dashboardIcon("M2 4.5h5m3 0h4M5 2v5m-3 4.5h8m3 0h1m-1.5-2.5v5")}Settings</span>
              <span class="sidebar-space"></span>
              <span class="sidebar-sync">Synced 2m ago<br>Everything looks good</span>
            </aside>
            <div class="product-content">
              <div class="product-content-head"><b>Overview</b><span class="sample-tag">SAMPLE</span></div>
              <div class="mock-alert"><i></i><span><b>Codex 5h limit at 93%</b>Switch to an account with more room.</span></div>
              <div class="mock-stats">
                <div class="mock-stat"><small>Tokens today</small><strong>11.8M</strong><em>+16%</em></div>
                <div class="mock-stat"><small>API value today</small><strong>$25.66</strong><em>1,309 requests</em></div>
                <div class="mock-stat"><small>Closest to a limit</small><strong>93%</strong><em>Codex · 5-hour</em></div>
              </div>
              <div class="mock-panel">
                <div class="mock-panel-head"><b>In use</b><span>Current accounts and limits</span></div>
                <div class="account-line">
                  <div class="account-name">${mark("claude")}<span>Claude Code<small>Personal · Max 5x</small></span></div>
                  <div class="limit-line"><span>5-hour</span><b>51%</b><div class="limit-track"><span class="warn" style="width:51%"></span></div></div>
                  <span class="account-action">Accounts</span>
                </div>
                <div class="account-line">
                  <div class="account-name">${mark("cursor")}<span>Cursor<small>Work · Ultra</small></span></div>
                  <div class="limit-line"><span>Auto</span><b>62%</b><div class="limit-track"><span style="width:62%"></span></div></div>
                  <span class="account-action">Accounts</span>
                </div>
                <div class="account-line">
                  <div class="account-name">${mark("codex")}<span>Codex<small>Personal · Plus</small></span></div>
                  <div class="limit-line"><span>5-hour</span><b>93%</b><div class="limit-track"><span class="bad" style="width:93%"></span></div></div>
                  <span class="account-action">Accounts</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="tray-card">
          <div class="tray-tabs">
            <span class="tray-tab active">${mark("claude")}Claude</span>
            <span class="tray-tab">${mark("cursor")}Cursor</span>
            <span class="tray-tab">${mark("codex")}Codex</span>
          </div>
          <div class="tray-account">
            <div class="tray-account-head"><span><b>Personal</b><small>me@personal.dev · Max 5x</small></span><span class="in-use">In use</span></div>
            <div class="tray-limits">
              <div class="tray-limit">5h <b>51%</b><div class="limit-track"><span class="warn" style="width:51%"></span></div></div>
              <div class="tray-limit">Week <b>6%</b><div class="limit-track"><span style="width:6%"></span></div></div>
            </div>
          </div>
          <div class="tray-account tray-switch"><span>work@studio.dev · Pro</span><b>8% left</b></div>
        </div>
      </div>
    </section>

    <section class="landing-section" id="product">
      <div class="section-heading">
        <span class="landing-kicker">Built for long sessions</span>
        <h2>Know where every account stands.</h2>
        <p>No spreadsheets, browser tabs or surprise limits. Keyhop watches the numbers that matter and keeps the next account ready.</p>
      </div>
      <div class="feature-grid">
        <article class="feature-card">
          <div class="feature-label">01 · Accounts</div>
          <h3>Switch without signing in again</h3>
          <p>Save the accounts you already own, then move Claude Code, Cursor or Codex over with one click.</p>
          <div class="feature-visual switch-visual" aria-hidden="true">
            <div class="switch-row">${mark("claude")}<span>Personal<small>me@personal.dev</small></span><em>In use</em></div>
            <div class="switch-row">${mark("claude")}<span>Studio<small>work@studio.dev</small></span><b>72% left</b></div>
          </div>
        </article>
        <article class="feature-card">
          <div class="feature-label">02 · Limits</div>
          <h3>See the runway, not just the warning</h3>
          <p>Live limit bars, reset times and forecasts tell you when to hop.</p>
          <div class="feature-visual limits-visual" aria-hidden="true">
            <div class="big-limit"><span>5-hour window</span><b>93%</b><div class="limit-track"><span class="bad" style="width:93%"></span></div></div>
            <div class="big-limit"><span>Weekly</span><b>62%</b><div class="limit-track"><span class="warn" style="width:62%"></span></div></div>
          </div>
        </article>
        <article class="feature-card">
          <div class="feature-label">03 · Usage</div>
          <h3>One history across every tool</h3>
          <p>Track tokens, requests and API value by account, model, hour or week.</p>
          <div class="feature-visual chart-visual" aria-hidden="true">
            <i style="--h:28%"></i><i style="--h:46%"></i><i style="--h:35%"></i><i style="--h:72%"></i><i style="--h:55%"></i><i style="--h:88%"></i><i style="--h:68%"></i><i style="--h:95%"></i><i style="--h:61%"></i>
          </div>
        </article>
        <article class="feature-card">
          <div class="feature-label">04 · Local first</div>
          <h3>Your coding stays yours</h3>
          <p>Credentials live in your system vault. Usage history stays on your computer. There is no analytics SDK looking over your shoulder.</p>
          <div class="feature-visual privacy-visual" aria-hidden="true">
            ${Array.from({ length: 32 }, () => html`<i></i>`)}
          </div>
        </article>
      </div>
    </section>

    <section class="workflow" aria-label="How Keyhop works">
      <article class="workflow-step"><div class="workflow-number">01 / SAVE</div><h3>Keyhop finds your logins</h3><p>Add another account the same way you normally sign in. Keyhop stores each login in the secure vault built into your system.</p></article>
      <article class="workflow-step"><div class="workflow-number">02 / WATCH</div><h3>Limits stay visible</h3><p>Usage refreshes quietly in the background, with budgets and forecasts before an account runs out of room.</p></article>
      <article class="workflow-step"><div class="workflow-number">03 / HOP</div><h3>Switch and keep moving</h3><p>Choose another saved account from the menu. Keyhop hands the login to the tool and confirms that it is live.</p></article>
    </section>

    <section class="landing-section" id="roadmap">
      <div class="roadmap-heading">
        <div>
          <span class="landing-kicker">Planned, not shipped yet</span>
          <h2>One layer between you and every AI tool.</h2>
        </div>
        <p>Today Keyhop keeps accounts, limits and usage under control. Next, it becomes a private coordination layer for agents, devices and the tools that have not launched yet.</p>
      </div>
      <div class="future-grid">
        <article class="future-card future-ai">
          <div class="future-label"><span>01 · Keyhop AI</span><em>Exploring</em></div>
          <h3>Know the best account before the next session starts.</h3>
          <p>A local advisor will weigh remaining capacity, reset time, tool and budget, then recommend the cleanest place to keep working—without reading your prompts.</p>
          <div class="future-preview route-preview" aria-hidden="true">
            <div><span>Recommended next</span><b>Claude · Studio</b><em>82% free</em></div>
            <div><span>Why</span><b>Resets in 34 min</b><em>Best runway</em></div>
          </div>
        </article>
        <article class="future-card future-mcp">
          <div class="future-label"><span>02 · MCP</span><em>Planned</em></div>
          <h3>Let agents check the runway before they run.</h3>
          <p>A local MCP server will let assistants read account health and request a confirmed switch. Models receive useful status, never raw credentials.</p>
          <div class="future-preview mcp-preview" aria-hidden="true">
            <span>agent → keyhop</span>
            <code>limits({ tool: "codex" })</code>
            <b>✓ Work has 91% left</b>
          </div>
        </article>
        <article class="future-card future-mobile">
          <div class="future-label"><span>03 · Mobile companion</span><em>Planned</em></div>
          <h3>Carry every reset in your pocket.</h3>
          <p>An optional iOS and Android companion for limit alerts, reset countdowns and account health. Your desktop remains in charge of every credential and switch.</p>
          <div class="future-preview phone-preview" aria-hidden="true">
            <div class="phone-top"><span>9:41</span><i></i></div>
            <div class="phone-alert"><span>Codex · Personal</span><b>Ready again in 24m</b></div>
            <div class="phone-meter"><span></span></div>
          </div>
        </article>
        <article class="future-card future-extend">
          <div class="future-label"><span>04 · Automations</span><em>On the horizon</em></div>
          <h3>Make Keyhop work the way your team does.</h3>
          <p>Rules, webhooks and a provider adapter SDK can bring new AI tools into the same view, enforce budget guardrails and trigger the right action before capacity runs dry.</p>
          <div class="future-preview rules-preview" aria-hidden="true">
            <span>WHEN <b>weekly capacity &lt; 10%</b></span>
            <span>THEN <b>notify team + suggest hop</b></span>
            <div><i>CLI</i><i>Webhook</i><i>Your adapter</i></div>
          </div>
        </article>
      </div>
      <aside class="roadmap-invite">
        <div><b>Help decide what ships first.</b><span>Keyhop is open source. Bring a workflow, provider or integration you want us to explore.</span></div>
        <a class="btn secondary" href="https://github.com/dominikzabcik/keyhop/issues">Request a feature ${arrow()}</a>
      </aside>
    </section>

    <section class="landing-section">
      <div class="community-panel">
        <div class="community-copy">
          <span class="landing-kicker">Optional and social</span>
          <h2>Compare the work, not the prompts.</h2>
          <p>Link GitHub when you want public profiles, private team boards and a new ranked season every month. Keyhop shares only daily totals per tool.</p>
          <a class="btn secondary" href="/leaderboard">See the leaderboard</a>
        </div>
        <div class="mini-board" aria-hidden="true">
          <div class="mini-board-head"><span>#</span><span>Builder</span><span>7 days</span></div>
          <div class="mini-board-row"><span class="mini-rank">01</span><span class="mini-person"><i class="mini-avatar">M</i>mira</span><span class="mini-total">1.8B</span></div>
          <div class="mini-board-row"><span class="mini-rank">02</span><span class="mini-person"><i class="mini-avatar">K</i>kai</span><span class="mini-total">1.4B</span></div>
          <div class="mini-board-row"><span class="mini-rank">03</span><span class="mini-person"><i class="mini-avatar">A</i>alex</span><span class="mini-total">986M</span></div>
          <div class="mini-board-row"><span class="mini-rank">04</span><span class="mini-person"><i class="mini-avatar">R</i>ren</span><span class="mini-total">822M</span></div>
        </div>
      </div>
    </section>

    <section class="landing-section" id="privacy">
      <div class="privacy-panel">
        <div class="privacy-copy">
          <span class="landing-kicker">Private by default</span>
          <h2>Your prompts never pass through Keyhop. <span>Neither do your account names.</span></h2>
          <p>Keyhop reads account limits and local usage records so it can help you switch at the right time. It has no analytics and sends nothing to keyhop.app unless you explicitly link the optional leaderboard.</p>
        </div>
        <div class="privacy-list">
          <div class="privacy-item">
            <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M4 9V6a6 6 0 0 1 12 0v3M3 9.5h14v8H3z"/></svg>
            <div><b>Credentials stay in your system vault</b><span>Keychain on macOS, Secret Service on Linux and DPAPI on Windows.</span></div>
          </div>
          <div class="privacy-item">
            <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M3 5.5 10 2l7 3.5v4.8c0 3.5-2.3 6.2-7 7.7-4.7-1.5-7-4.2-7-7.7zM7 10l2 2 4-4"/></svg>
            <div><b>No prompts or source code</b><span>Keyhop tracks totals and limits, never the content of your work.</span></div>
          </div>
          <div class="privacy-item">
            <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M3 10a7 7 0 1 0 2-4.9M3 3v5h5"/></svg>
            <div><b>Transparent and reversible</b><span>Open source, no lock-in, and your tools stay signed into the last account you used.</span></div>
          </div>
        </div>
      </div>
    </section>

    <section class="landing-section" id="install">
      <div class="install-panel">
        <div class="install-copy">
          <span class="landing-kicker">Start in a minute</span>
          <h2>Install once. Keep your flow.</h2>
          <p>The installer picks the right package for your system and verifies its SHA-256 before installing anything. You can also use Homebrew, Scoop, RPM, DEB or Arch packages.</p>
          <div class="platforms"><span class="platform">macOS 14+</span><span class="platform">Linux x86_64</span><span class="platform">Linux aarch64</span><span class="platform">Windows 10/11</span></div>
        </div>
        <div class="install-terminal" aria-label="Install commands">
          <div class="terminal-head"><span>Terminal</span><span>keyhop/install</span></div>
          <div class="terminal-body">
            <div class="terminal-line"><span>$</span><code>curl -fsSL https://raw.githubusercontent.com/dominikzabcik/keyhop/main/install.sh | bash</code></div>
            <div class="terminal-line"><span>&gt;</span><code>irm https://raw.githubusercontent.com/dominikzabcik/keyhop/main/install.ps1 | iex</code></div>
            <div class="comment"># macOS / Linux above · Windows PowerShell below</div>
          </div>
        </div>
      </div>
    </section>

    <section class="landing-section">
      <div class="section-heading">
        <span class="landing-kicker">Questions, answered</span>
        <h2>Before you hand over a login.</h2>
      </div>
      <div class="faq-list">
        <details><summary>Does Keyhop share accounts or add usage?</summary><p>No. Keyhop only switches between accounts you already own. It cannot increase a plan’s limits, and every provider’s terms still apply.</p></details>
        <details><summary>What exactly changes when I switch?</summary><p>Keyhop saves the login currently used by that tool, loads the selected saved login, hands it to the tool through its normal credential path, and reads it back to confirm the switch.</p></details>
        <details><summary>Where are my provider tokens stored?</summary><p>In Login Keychain on macOS, Secret Service or private files on Linux, and DPAPI-encrypted files on Windows. Provider tokens are never sent to keyhop.app.</p></details>
        <details><summary>Do I have to use the leaderboard?</summary><p>No. The desktop app, account switching, limits, history, budgets and alerts all work without a Keyhop cloud account. Leaderboards and teams are opt-in.</p></details>
        <details><summary>What does “API value” mean?</summary><p>Keyhop prices the tokens you used at each provider’s standard API rates. It shows the value of your usage, not a bill from your subscription.</p></details>
        <details><summary>Are Keyhop AI, MCP and the mobile app available now?</summary><p>Not yet. They are the direction we are exploring, not shipping features. The roadmap may change as people test Keyhop and tell us which workflows matter most.</p></details>
        <details><summary>Can I inspect or build Keyhop myself?</summary><p>Yes. Keyhop is MIT licensed, its installers are readable shell scripts, and the application, cloud service, packaging and tests are all in the public repository.</p></details>
      </div>
    </section>

    <section class="closing">
      ${raw(PIXEL_MARK)}
      <h2>Less account admin. More building.</h2>
      <p>Bring every Claude Code, Cursor and Codex account into one calm place.</p>
      <div class="closing-actions">
        <a class="btn" href="/download">Download Keyhop ${arrow()}</a>
        <a class="btn secondary" href="/leaderboard">Explore the leaderboard</a>
      </div>
    </section>
  `;
}
