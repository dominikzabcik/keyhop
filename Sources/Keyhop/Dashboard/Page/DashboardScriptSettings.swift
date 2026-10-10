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
    else if (update) updateRow = `<div class="setting-row"><div><b>Keyhop is up to date</b><p>Version ${esc(update.current)} is the latest release.</p></div><button class="btn sm secondary" data-action="check-update">Check Again</button></div>`;
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
      general: `<div class="settings-intro"><h2>Window Appearance</h2><p>Choose how Keyhop sits alongside the rest of your Mac.</p></div>${isStatic ? "" : appearanceCard()}`,
      activity: `<div class="settings-intro"><h2>Activity</h2><p>Control what Keyhop reads locally and see where each tool is signed in.</p></div>${isStatic ? "" : workCard(state.work)}<section class="card"><div class="card-head"><h2>Tools on This Mac</h2></div>${tools}</section>`,
      cloud: `<div class="settings-intro"><h2>Keyhop Cloud</h2><p>The link, what this computer sends, and who else can read it.</p></div>${cloudCard(state.cloud)}`,
      app: `<div class="settings-intro"><h2>App & Privacy</h2><p>Version ${esc(state.version)} on ${esc(state.platform)}. Updates and limit refreshes stay independent.</p></div><section class="card"><div class="card-head"><h2>Updates</h2></div><div class="card-body">${updateRow}</div></section>${privacy}`,
    };
    if (ui.settingsPane === "cloud" && (isStatic || !state.cloud?.available)) ui.settingsPane = "general";
    const choices = [["general", "settings", "Appearance"], ["activity", "usage", "Activity"]];
    if (!isStatic && state.cloud?.available) choices.push(["cloud", "leaderboard", "Cloud"]);
    choices.push(["app", "update", "App & Privacy"]);
    const nav = choices.map(([value, glyph, label]) => `<button type="button" data-action="settings-pane" data-value="${value}" aria-current="${value === ui.settingsPane ? "page" : "false"}">${icon(glyph)}<span>${label}</span></button>`).join("");
    return { body: `<div class="settings-shell"><nav class="card settings-nav" aria-label="Settings categories">${nav}</nav><div class="settings-pane">${panes[ui.settingsPane]}</div></div>` };
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
