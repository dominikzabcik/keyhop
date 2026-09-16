import { html } from "hono/html";
import type { Html } from "./ui";

const RELEASES = "https://github.com/dominikzabcik/keyhop/releases/latest";
const DOWNLOADS = `${RELEASES}/download`;
const REPOSITORY = "https://github.com/dominikzabcik/keyhop";

function pageHero(kicker: string, title: string, description: string): Html {
  return html`<header class="page-hero">
    <span class="landing-kicker">${kicker}</span>
    <h1>${title}</h1>
    <p>${description}</p>
  </header>`;
}

function codeBlock(label: string, command: string): Html {
  return html`<div class="command-block"><span>${label}</span><code>${command}</code></div>`;
}

export function downloadPage(): Html {
  return html`<div class="marketing-page">
    ${pageHero(
      "Download Keyhop",
      "Ready on every desktop.",
      "Install the native Keyhop app for macOS, Linux or Windows. Every official download is published on GitHub with a SHA-256 checksum.",
    )}

    <section class="platform-grid" aria-label="Download Keyhop">
      <article class="platform-card featured">
        <div class="platform-head"><span class="platform-mark">⌘</span><div><h2>macOS</h2><p>macOS 14 or later · Apple silicon and Intel</p></div></div>
        ${codeBlock("Terminal", "curl -fsSL https://raw.githubusercontent.com/dominikzabcik/keyhop/main/install.sh | bash")}
        <p>Installs Keyhop into Applications, adds the <code>keyhop</code> command to your PATH and opens the app.</p>
        <div class="platform-actions"><a class="btn" href="${DOWNLOADS}/Keyhop.dmg">Download for macOS</a><a href="${REPOSITORY}#install">Homebrew and DMG options</a></div>
      </article>
      <article class="platform-card">
        <div class="platform-head"><span class="platform-mark">◆</span><div><h2>Linux</h2><p>x86_64 and aarch64 · Static binary</p></div></div>
        ${codeBlock("Shell", "curl -fsSL https://raw.githubusercontent.com/dominikzabcik/keyhop/main/install.sh | bash")}
        <p>The installer selects RPM, DEB, Arch or a portable <code>~/.local</code> build for your distribution.</p>
        <div class="platform-actions"><a class="btn secondary" href="${DOWNLOADS}/Keyhop-Linux-x86_64.tar.gz">Linux x86_64</a><a href="${DOWNLOADS}/Keyhop-Linux-aarch64.tar.gz">Linux aarch64</a><a href="${RELEASES}">All packages</a></div>
      </article>
      <article class="platform-card">
        <div class="platform-head"><span class="platform-mark">⊞</span><div><h2>Windows</h2><p>Windows 10 and 11 · Per-user install</p></div></div>
        ${codeBlock("PowerShell", "irm https://raw.githubusercontent.com/dominikzabcik/keyhop/main/install.ps1 | iex")}
        <p>Installs without administrator rights, adds Keyhop to PATH and the Start menu, and opens it at sign-in.</p>
        <div class="platform-actions"><a class="btn secondary" href="${DOWNLOADS}/Keyhop-Windows-x86_64.zip">Download for Windows</a><a href="${REPOSITORY}#install">Scoop option</a></div>
      </article>
    </section>

    <section class="content-split">
      <div><span class="section-index">01 / VERIFY</span><h2>Every release checks itself.</h2></div>
      <div class="prose"><p>The one-line installers download the matching release and compare it with the release’s <code>SHA256SUMS</code> before installing anything. The built-in updater performs the same check.</p><p>Keyhop is not notarized or certificate-signed. If you prefer not to run a prebuilt binary, inspect the installer or build the MIT-licensed source yourself.</p></div>
    </section>
    <section class="content-split">
      <div><span class="section-index">02 / FIRST RUN</span><h2>Your existing login is enough.</h2></div>
      <div class="prose"><p>Open Keyhop and it finds the Claude Code, Cursor, Codex and Gemini CLI logins already on your computer. Add another account by signing in to the tool normally when Keyhop asks.</p><p>No provider API key is required. Codex accounts must use a ChatGPT sign-in, and Gemini CLI accounts must use Sign in with Google.</p></div>
    </section>
    <aside class="page-cta"><div><b>Want to inspect it first?</b><span>Read every line, build from source, or check the latest release notes.</span></div><a class="btn" href="${REPOSITORY}">View on GitHub</a></aside>
  </div>`;
}

export function privacyPage(): Html {
  return html`<div class="marketing-page">
    ${pageHero(
      "Privacy",
      "Your work is not the product.",
      "Keyhop has no analytics or advertising. The desktop app keeps credentials and usage history on your computer; cloud features are optional and deliberately narrow.",
    )}
    <div class="legal-layout">
      <aside class="legal-nav" aria-label="On this page">
        <span>On this page</span>
        <a href="#desktop">Desktop app</a><a href="#network">Network requests</a><a href="#cloud">Keyhop cloud</a><a href="#cookies">Website cookies</a><a href="#control">Your controls</a>
      </aside>
      <article class="legal-content">
        <section id="desktop"><span class="section-index">01 / DESKTOP APP</span><h2>What stays on your computer</h2><p>Saved provider logins live in the secure storage available to your user account: Login Keychain on macOS, Secret Service or private files on Linux, and DPAPI-encrypted files on Windows.</p><p>Account labels and Keyhop’s usage database live in Keyhop’s private data folder. The account list contains no provider tokens. Keyhop reads local Claude Code, Codex and Gemini CLI usage logs and Cursor’s own usage export to calculate totals, budgets and forecasts.</p></section>
        <section id="network"><span class="section-index">02 / NETWORK</span><h2>Requests the app makes</h2><ul><li><b>Provider limits and token refresh:</b> Anthropic, OpenAI and Cursor endpoints, using that account’s own token.</li><li><b>Gemini CLI:</b> No Google request. Keyhop switches its local login file and reads local transcript usage only.</li><li><b>Updates:</b> GitHub’s API and release downloads, with checksum verification.</li><li><b>Optional leaderboard:</b> keyhop.app, only after you link the app yourself.</li></ul><p>Keyhop does not send prompts, source code, account labels or local usage history to an analytics service. You can disable automatic usage checks in Settings.</p></section>
        <section id="cloud"><span class="section-index">03 / KEYHOP CLOUD</span><h2>What the optional leaderboard stores</h2><p>Signing in with GitHub stores your GitHub id, login, public name and avatar URL. GitHub’s access token is discarded after that public profile is read.</p><p>A linked desktop app sends daily totals per tool: tokens, API value and request count. The iOS companion receives a read-only link that can view your profile, season, quests and standings but cannot alter them. The service never receives prompts, emails, provider account names, model names or provider tokens. Profiles are private until you make yours public; team members can see one another’s totals.</p><p>Browser and linked-app session tokens are stored only as SHA-256 hashes. Daily totals, memberships and profile data remain until you delete your account.</p></section>
        <section id="cookies"><span class="section-index">04 / WEBSITE</span><h2>Cookies and third parties</h2><p>The website sets only essential, HTTP-only cookies for GitHub sign-in and your browser session. There are no analytics, advertising or cross-site tracking cookies.</p><p>Public profile avatars load from GitHub’s avatar service. Following links to GitHub, Anthropic, Cursor, OpenAI or Google takes you to those companies’ websites and their own privacy practices.</p></section>
        <section id="control"><span class="section-index">05 / YOUR CONTROL</span><h2>View, unlink or delete</h2><ul><li>Run <code>keyhop cloud logout</code> to unlink one computer.</li><li>Use Settings on keyhop.app to revoke any linked app or make your profile private.</li><li>Delete your website account to remove its profile, daily totals, sessions, memberships and teams.</li><li>Run <code>keyhop reset</code> to remove Keyhop’s local accounts, credentials, history and settings.</li></ul><p>For a privacy question, open an issue on <a href="${REPOSITORY}/issues">GitHub</a>. For a vulnerability, use <a href="${REPOSITORY}/security/advisories/new">private security reporting</a> instead.</p></section>
        <p class="updated">Last updated September 14, 2026.</p>
      </article>
    </div>
  </div>`;
}

export function termsPage(): Html {
  return html`<div class="marketing-page">
    ${pageHero(
      "Use and trademarks",
      "Use Keyhop with accounts that are yours.",
      "Keyhop moves existing logins between tools on your own computer. It does not add usage to a plan or change a provider’s limits.",
    )}
    <div class="legal-layout">
      <aside class="legal-nav" aria-label="On this page"><span>On this page</span><a href="#responsible-use">Responsible use</a><a href="#license">License</a><a href="#service">Cloud service</a><a href="#trademarks">Trademarks</a></aside>
      <article class="legal-content">
        <section id="responsible-use"><span class="section-index">01 / RESPONSIBLE USE</span><h2>Provider rules still apply</h2><p>Only save and switch between accounts you own and are allowed to use. Using multiple accounts to avoid one plan’s limits may violate that provider’s terms.</p><p>Review the current terms for <a href="https://www.anthropic.com/legal/consumer-terms">Anthropic</a>, <a href="https://cursor.com/terms-of-service">Cursor</a>, <a href="https://openai.com/policies/row-terms-of-use/">OpenAI</a> and <a href="https://policies.google.com/terms">Google</a>. Keyhop does not grant rights to any third-party service. Google restricts third-party access to Gemini CLI backend services, so Keyhop’s Gemini integration only switches local login state and reads local transcripts.</p></section>
        <section id="license"><span class="section-index">02 / SOFTWARE</span><h2>MIT licensed</h2><p>Keyhop’s source code is available under the <a href="${REPOSITORY}/blob/main/LICENSE">MIT License</a>. You may use, copy, modify and distribute it under that license’s conditions.</p><p>The software is provided “as is,” without warranty. The full license text controls if this summary differs from it.</p></section>
        <section id="service"><span class="section-index">03 / CLOUD SERVICE</span><h2>The leaderboard is optional</h2><p>keyhop.app provides profiles, teams, leaderboards and seasons as a convenience. Rankings come from totals reported by participants’ own Keyhop apps, so they are not independently verified.</p><p>You may stop using the cloud service at any time, unlink your computers and delete your account from Settings.</p></section>
        <section id="trademarks"><span class="section-index">04 / TRADEMARKS</span><h2>Independent project</h2><p>Keyhop is not affiliated with, endorsed by or sponsored by Anthropic, Anysphere, OpenAI or Google. Claude, Claude Code, Cursor, Codex, OpenAI, Gemini and Google are trademarks of their respective owners. Their marks appear only to identify compatible tools.</p></section>
        <p class="updated">Last updated September 13, 2026.</p>
      </article>
    </div>
  </div>`;
}

export function securityPage(): Html {
  return html`<div class="marketing-page">
    ${pageHero(
      "Security",
      "Report problems privately.",
      "Keyhop handles provider login tokens, so careful reports are welcome. Please do not put credentials or undisclosed vulnerabilities in a public issue.",
    )}
    <aside class="security-report"><div><span class="landing-kicker">Preferred channel</span><h2>GitHub private vulnerability reporting</h2><p>Include the affected version, operating system, reproduction steps and impact. Replace every real token or credential before attaching logs.</p></div><a class="btn" href="${REPOSITORY}/security/advisories/new">Open a private report</a></aside>
    <section class="content-split"><div><span class="section-index">01 / STORAGE</span><h2>Secrets use the system vault.</h2></div><div class="prose"><p>Provider credentials are stored in Login Keychain, Secret Service or DPAPI depending on the operating system. Keyhop’s account list contains labels and identifiers, not tokens.</p><p>On Linux without a running keyring, Keyhop falls back to files readable only by your user in a private directory.</p></div></section>
    <section class="content-split"><div><span class="section-index">02 / LOCAL DASHBOARD</span><h2>Bound to your computer.</h2></div><div class="prose"><p>The dashboard listens on <code>127.0.0.1</code> only. Its URL carries a random 256-bit session key, every API request must send it, non-loopback host names are refused, and the server stops after its last window closes.</p></div></section>
    <section class="content-split"><div><span class="section-index">03 / RELEASES</span><h2>Verified, but not signed.</h2></div><div class="prose"><p>Releases are not notarized or certificate-signed. Every download has a SHA-256 entry in <code>SHA256SUMS</code>, and the installers and updater refuse a release that does not match.</p><p>Read the complete <a href="${REPOSITORY}/blob/main/SECURITY.md">security model and known trade-offs</a> before reporting an issue.</p></div></section>
  </div>`;
}
