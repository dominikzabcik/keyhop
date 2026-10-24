import Foundation

/// The Settings panes and the overlays (toast, tip).
extension DashboardPage {
    static let scriptSettings = ##"""
  // MARK: Settings

  function settingsPage() {
    const state = data.state, doctor = data.doctor, update = data.update;
    let updateRow;
    if (isStatic) updateRow = `<div class="setting-row"><div><b>Version</b><p>Saved from Keyhop ${esc(state.version)}</p></div></div>`;
    else if (ui.checkingUpdate) updateRow = `<div class="setting-row"><div><b>Checking for updates…</b><p class="update-status" role="status"><span class="ring" aria-hidden="true"></span>Asking GitHub for the latest release</p></div></div>`;
    else if (data.updateError) updateRow = `<div class="setting-row"><div><b>Couldn’t check for updates</b><p>${esc(data.updateError)} Try again when you’re connected.</p></div><button class="btn sm secondary" data-action="check-update">Try Again</button></div>`;
    else if (update?.available) updateRow = `<div class="setting-row"><div><b>Keyhop ${esc(update.latest)} is available</b><p>You have ${esc(update.current)}. The download is checked against its SHA-256 before it installs.</p></div><button class="btn sm" data-action="install-update">Install Update</button></div>`;
    else if (update) updateRow = `<div class="setting-row"><div><b>Keyhop is up to date</b><p>Version ${esc(update.current)} is the latest ${update.channel === "beta" ? "Beta" : "Stable"} release.</p></div><button class="btn sm secondary" data-action="check-update">Check Again</button></div>`;
    else updateRow = `<div class="setting-row"><div><b>Keyhop ${esc(state.version)}</b><p>Update checks run separately from limit and usage refreshes.</p></div><button class="btn sm secondary" data-action="check-update">Check for Updates</button></div>`;

    const tools = doctor ? `<div class="list">${doctor.tools.map((t) => `<div class="row">
        <div class="who">${mark(t.id)}<div><b>${esc(t.name)}</b><small>${t.signedInAs ? `Signed in as ${esc(t.signedInAs)}` : t.problem ? esc(t.problem) : t.installed ? "Signed out" : "Not found on this computer"}</small></div></div>
        <div class="mono subtle" style="margin:8px 0 0 30px;overflow-wrap:anywhere">${esc(t.loginLocation)}</div>
      </div>`).join("")}</div>` : (isStatic ? `<p class="empty">Not included in a saved page.</p>` : busy("Looking for tools on this computer", "empty"));

    const privacy = `<section class="card"><div class="card-head"><h2>Storage & Privacy</h2></div>
      <div class="list">
        <div class="row kv"><span>Data folder</span><span class="mono">${esc(doctor?.dataDirectory || state.dataDirectory)}</span></div>
        <div class="row kv"><span>Saved logins</span><span>${esc(doctor ? `${doctor.savedAccounts} in ${doctor.secretStore}` : state.status.secretStore)}</span></div>
        ${doctor?.prices ? `<div class="row kv"><span>Model prices</span><span>${fmt.count(doctor.prices.models)} models, ${doctor.prices.updated ? `from models.dev ${esc(ago(doctor.prices.updated))}` : "built into this release"}</span></div>` : ""}
        <div class="row kv"><span>Network</span><span>Provider usage and sign-in services, public status pages, models.dev for prices, GitHub for updates${state.cloud?.linked ? `, and Keyhop cloud for your daily totals${state.cloud.sharesLimits ? " and current limits" : ""}` : ""}. No analytics.</span></div>
        <div class="row kv"><span>This window</span><span>Served by Keyhop on 127.0.0.1 with a private session key.</span></div>
      </div></section>`;
    const panes = {
      activity: `<div class="settings-intro"><h2>Activity</h2><p>Control what Keyhop reads locally and see where each tool is signed in.</p></div>${isStatic ? "" : workCard(state.work)}<section class="card"><div class="card-head"><h2>Tools on This Mac</h2></div>${tools}</section>`,
      browser: `<div class="settings-intro"><h2>Browser</h2><p>claude.ai and chatgpt.com follow each hop of Claude Code and Codex.</p></div>${browserCard(data.browser)}`,
      cloud: `<div class="settings-intro"><h2>Keyhop Cloud</h2><p>The link, what this computer sends, and who else can read it.</p></div>${cloudCard(state.cloud)}`,
      app: `<div class="settings-intro"><h2>App & Privacy</h2><p>Version ${esc(state.version)} on ${esc(state.platform)}. Updates and limit refreshes stay independent.</p></div>${helpCard()}<section class="card"><div class="card-head"><h2>Updates</h2>${isPrerelease(state.version) ? `<span class="pill warn">Beta build</span>` : ""}</div><div class="card-body">${updateRow}</div>${isStatic ? "" : channelRow(update)}</section>${privacy}`,
    };
    if (!panes[ui.settingsPane] || (ui.settingsPane === "cloud" && (isStatic || !state.cloud?.available))) ui.settingsPane = "activity";
    const choices = [["activity", "usage", "Activity"]];
    if (!isStatic) choices.push(["browser", "hop", "Browser"]);
    if (!isStatic && state.cloud?.available) choices.push(["cloud", "leaderboard", "Cloud"]);
    choices.push(["app", "update", "App & Privacy"]);
    const nav = choices.map(([value, glyph, label]) => `<button type="button" data-action="settings-pane" data-value="${value}" aria-current="${value === ui.settingsPane ? "page" : "false"}">${icon(glyph)}<span>${label}</span></button>`).join("");
    return { body: `<div class="settings-shell"><nav class="card settings-nav" aria-label="Settings categories">${nav}</nav><div class="settings-pane">${panes[ui.settingsPane]}</div></div>` };
  }

  // The Chrome extension: where its folder is, whether a browser has loaded it, and the site logins
  // it has kept. Loading an unpacked extension is the one step Keyhop can't do for you.
  function browserCard(report) {
    if (!report) return `<section class="card">${data.browserError ? `<p class="empty">${esc(data.browserError)}</p>` : busy("Looking for browsers", "empty")}</section>`;
    const registered = report.browsers.filter((browser) => browser.registered).map((browser) => browser.name);
    if (!report.installed) {
      return `<section class="card"><div class="card-head"><h2>Chrome extension</h2></div><div class="list">
        <div class="row setting-row"><div><b>Not set up</b><p>Keyhop writes the extension to a folder and lets Chrome, Edge, Brave and Arc talk to it. Site logins stay in ${esc(data.doctor?.secretStore || "Keyhop's vault")}, not in the browser.</p></div><button class="btn sm" data-action="browser-install">Set up</button></div>
      </div></section>`;
    }
    const heard = report.lastSeen ? `Connected ${esc(ago(report.lastSeen))}` : "Not loaded yet";
    const steps = report.lastSeen ? "" : `<div class="row setting-row"><div><b>Load it once</b><p>Open <span class="mono">chrome://extensions</span>, turn on Developer mode, click Load unpacked and choose the folder below.</p></div><button class="btn sm secondary" data-action="copy" data-value="${esc(report.extensionFolder)}">Copy folder</button></div>`;
    return `<section class="card"><div class="card-head"><h2>Chrome extension</h2><span class="pill ${report.lastSeen ? "good" : "warn"}">${heard}</span></div><div class="list">
      ${steps}
      <div class="row kv"><span>Folder</span><span class="mono">${esc(report.extensionFolder)}</span></div>
      <div class="row kv"><span>Browsers</span><span>${esc(registered.length ? registered.join(", ") : "None registered")}</span></div>
      <div class="row kv"><span>Site logins kept</span><span>${report.webLogins.length}</span></div>
      <div class="row setting-row"><div><b>After an update</b><p>Set it up again, then reload the extension in <span class="mono">chrome://extensions</span>.</p></div><div class="row-actions"><button class="btn sm secondary" data-action="browser-install">Set up again</button><button class="btn sm ghost danger" data-action="browser-remove">Remove</button></div></div>
    </div></section>`;
  }

  const isPrerelease = (version) => String(version || "").includes("-");

  // Stable or Beta. Beta takes the newest of both, so leaving it never strands anyone on an old build.
  function channelRow(update) {
    const channel = update?.channel || (isPrerelease(data.state?.version) ? "beta" : "stable");
    const note = channel === "beta"
      ? "Nightly builds of the next version: new features first, and sometimes a rough edge. Switch back any time; this build stays until a Stable release is newer."
      : "Tested releases, the default. Beta gets new features a day or a week earlier.";
    const tabs = [["stable", "Stable"], ["beta", "Beta"]].map(([value, label]) => `<button type="button" data-action="update-channel" data-value="${value}" aria-pressed="${value === channel}">${label}</button>`).join("");
    return `<div class="card-body setting-row"><div><b>Update channel</b><p>${note}</p></div><div class="tabs">${tabs}</div></div>`;
  }

  // Help: where the answers are, and what to run when something looks wrong.
  function helpCard() {
    return `<section class="card"><div class="card-head"><h2>Help</h2><span class="hint">Docs, questions and a check-up</span></div>
      <div class="list">
        <div class="row setting-row"><div><b>Read the guide</b><p>First run, every section of this window, the <span class="mono">keyhop</span> command, and what Keyhop cloud receives.</p></div><a class="btn sm secondary" href="https://keyhop.app/docs" target="_blank" rel="noopener">Open docs</a></div>
        <div class="row setting-row"><div><b>Ask or report</b><p>Questions and ideas go to GitHub Discussions; a tool that stopped switching or counting is an issue.</p></div><div class="row-actions"><a class="btn sm ghost" href="https://github.com/dominikzabcik/keyhop/discussions" target="_blank" rel="noopener">Discussions</a><a class="btn sm ghost" href="https://github.com/dominikzabcik/keyhop/issues/new/choose" target="_blank" rel="noopener">New issue</a></div></div>
        <div class="row setting-row"><div><b>Something looks wrong</b><p>Run <span class="mono">keyhop doctor</span> in a terminal: it names every path Keyhop reads, where logins are kept, and what it can't see. Paste its output into an issue.</p></div></div>
      </div></section>`;
  }

  // MARK: Overlays

  let toastTimer;
  function toast(message, error = false) {
    const node = $("#toast");
    node.textContent = message;
    node.classList.toggle("error", error);
    node.classList.remove("away");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => node.classList.add("away"), error ? 8000 : 5000);
  }

  function placeTip(tip, event) {
    tip.hidden = false;
    const box = tip.getBoundingClientRect();
    let x = event.clientX + 14, y = event.clientY + 14;
    if (x + box.width > innerWidth - 10) x = event.clientX - box.width - 14;
    if (y + box.height > innerHeight - 10) y = event.clientY - box.height - 14;
    tip.style.left = Math.max(10, x) + "px";
    tip.style.top = Math.max(10, y) + "px";
  }

  document.addEventListener("pointermove", (event) => {
    const tip = $("#tip");
    const card = event.target.closest && event.target.closest("[data-tip]");
    if (card) { tip.innerHTML = card.dataset.tip; placeTip(tip, event); return; }
    const hit = event.target.closest && event.target.closest(".hit");
    // The hovered day stays lit and the rest step back.
    for (const svg of document.querySelectorAll(".chart svg[data-hover]")) {
      if (!hit || hit.ownerSVGElement !== svg || svg.dataset.hover !== hit.dataset.bucket) {
        delete svg.dataset.hover;
        svg.querySelector(".col.on")?.classList.remove("on");
      }
    }
    if (hit && !hit.ownerSVGElement.dataset.hover) {
      hit.ownerSVGElement.dataset.hover = hit.dataset.bucket;
      hit.ownerSVGElement.querySelector(`.col[data-col="${hit.dataset.bucket}"]`)?.classList.add("on");
    }
    if (!hit) { tip.hidden = true; return; }
    const usage = data.usage[hit.dataset.key] || data.usage[hit.dataset.key.split(":")[0] + ":all"];
    const grouped = usage ? chartGroup(usage, hit.dataset.group) : null;
    const bucket = grouped?.buckets[+hit.dataset.bucket];
    if (!bucket) { tip.hidden = true; return; }
    const metric = hit.dataset.metric;
    const pick = (v) => (metric === "tokens" ? v.tokens : v.cost);
    const show = (v) => (metric === "tokens" ? fmt.tokens(v) : fmt.usd(v));
    const rows = grouped.series.map((s) => ({ s, v: bucket.values[s.id] })).filter((e) => e.v && pick(e.v) > 0).reverse();
    const total = rows.reduce((sum, e) => sum + pick(e.v), 0);
    const when = usage.bucket === "hour" ? fmt.day(bucket.start, { weekday: "short", hour: "2-digit", minute: "2-digit" })
      : usage.bucket === "week" ? `Week of ${fmt.day(bucket.start, { month: "short", day: "numeric", year: "numeric" })}`
      : usage.bucket === "month" ? fmt.day(bucket.start, { month: "long", year: "numeric" })
      : fmt.day(bucket.start, { weekday: "short", month: "short", day: "numeric" });
    tip.innerHTML = `<b>${esc(when)} · <span class="mono">${esc(show(total))}</span></b>${rows.length ? rows.map((e) => `<div><span class="swatch" style="background:${e.s.color}"></span><span>${esc(e.s.name)}</span><span class="mono">${esc(show(pick(e.v)))}</span></div>`).join("") : `<div><span></span><span>No usage</span><span></span></div>`}`;
    placeTip(tip, event);
  });

"""##
}
