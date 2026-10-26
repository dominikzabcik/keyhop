import Foundation

/// Event handling for every control, and the start-up sequence.
extension DashboardPage {
    static let scriptActions = ##"""
  // MARK: Actions

  const editing = () => ui.editing || ui.confirming || ui.rangeOpen || ui.menu || ["INPUT", "SELECT"].includes(document.activeElement?.tagName);

  // `morph` cross-fades the page into its new state once the call is done, for changes that move
  // things around, like switching which login is in use.
  async function act(button, call, label, morph = false) {
    const key = button ? pendingKey(button) : null;
    if (key) { ui.pending.set(key, label || ""); applyPending(); }
    try {
      const running = call();
      watchActivity();
      const result = await running;
      if (result && result.message) toast(result.note ? `${result.message} ${result.note}` : result.message);
      await loadState();
      await loadSection();
    } catch (error) {
      toast(error.message, true);
      if (data.state) { data.state.refreshing = false; data.state.activity = null; }
    } finally {
      if (key) ui.pending.delete(key);
      if (morph) transition(render); else render();
      watchActivity();
    }
  }

  // The verdict's hop: the one control on the core screen. The row swaps its login in place, the
  // verdict confirms it and holds the way back for 7 seconds, then settles.
  let hopTimers = [];
  async function hopVerdict(button, id, from, tool) {
    const key = button ? pendingKey(button) : null;
    if (key) { ui.pending.set(key, "Hopping"); applyPending(); }
    try {
      await api("/api/switch", { id });
      await loadState();
      await loadSection();
      const now = (data.state?.status.tools || []).find((item) => item.id === tool);
      const to = now?.accounts.find((account) => account.id === id);
      ui.hopped = { tool, to: id, from, name: to?.name || "", at: Date.now() };
      for (const timer of hopTimers) clearTimeout(timer);
      hopTimers = [setTimeout(() => { if (!editing()) render(); }, 2300), setTimeout(() => { ui.hopped = null; if (!editing()) render(); }, 7100)];
    } catch (error) {
      toast(error.message, true);
    } finally {
      if (key) ui.pending.delete(key);
      transition(render);
      watchActivity();
    }
  }

  // A hop made from the Limits view says where it went in a toast, with the way back.
  async function hopTo(button, id) {
    const tools = data.state?.status.tools || [];
    const tool = tools.find((item) => item.accounts.some((account) => account.id === id));
    const from = tool?.accounts.find((account) => account.active && account.id !== id) || null;
    await act(button, () => api("/api/switch", { id }), "Switching", true);
    const now = (data.state?.status.tools || []).find((item) => item.id === tool?.id);
    const to = now?.accounts.find((account) => account.id === id);
    if (!to?.active) return;
    const windows = (to.limits || []).map((limit) => `${windowName(limit.label).toLowerCase()} ${Math.round(limit.usedPercent)}%`).join(" · ");
    const node = $("#toast");
    node.classList.remove("error");
    node.innerHTML = `<span class="toast-check" aria-hidden="true">${icon("check")}</span><span class="toast-copy"><b>${esc(now.name)} hopped to ${esc(to.name)}</b>${windows ? `<small>${esc(windows)} used</small>` : ""}</span>${from && !isStatic ? `<button class="btn sm secondary" type="button" data-action="switch" data-id="${esc(from.id)}">Undo</button>` : ""}`;
    node.classList.add("rich");
    node.classList.remove("away");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { node.classList.add("away"); node.classList.remove("rich"); }, 6000);
  }

  async function showDay() {
    ui.boardView = "day";
    ui.boardDate = "";
    data.day = null;
    if (ui.section !== "teams") { await go("teams"); return; }
    render();
    await loadSection();
    render();
  }

  async function showUsage(change) {
    Object.assign(ui, change);
    if (ui.section !== "usage") { await go("usage"); return; }
    render();
    await loadSection();
    render();
  }

  async function go(section) {
    ui.section = asSection(section);
    section = ui.section;
    data.boardError = null;
    data.dayError = null;
    history.replaceState(null, "", "#" + section);
    transition(() => { render(); $("#main").scrollTop = 0; });
    await loadSection();
    render();
  }

  document.addEventListener("click", async (event) => {
    // A click anywhere outside the open range menu closes it.
    if (ui.rangeOpen && !event.target.closest(".range-pick")) { ui.rangeOpen = false; render(); }
    if (ui.menu && !event.target.closest(".menu-anchor")) { ui.menu = null; render(); }
    const el = event.target.closest("[data-action]");
    if (!el || el.disabled || el.tagName === "SELECT") return;
    if (el.tagName === "A") event.preventDefault();
    const id = el.dataset.id;
    switch (el.dataset.action) {
      case "goto": go(el.dataset.section); break;
      case "section-retry": data.coachError = data.plansError = null; render(); await loadSection(); render(); break;
      case "quota-tool": ui.quotaTool = el.dataset.value; transition(render); break;
      case "quota-hours": ui.quotaHours = +el.dataset.value; render(); break;
      case "quota-view": ui.quotaView = el.dataset.value; render(); break;
      case "skip-content": $("#main")?.focus(); break;
      case "settings-pane": ui.settingsPane = el.dataset.value; render(); break;
      case "refresh":
        if (data.state?.refreshing) break;
        act(null, () => { data.state.refreshing = true; renderActivity(); return api("/api/refresh", {}); });
        break;
      case "hop": hopVerdict(el, id, el.dataset.from, el.dataset.tool); break;
      case "unhop": {
        const back = ui.hopped;
        ui.hopped = null;
        for (const timer of hopTimers) clearTimeout(timer);
        hopVerdict(el, id, back?.to, el.dataset.tool).then(() => { ui.hopped = null; render(); });
        break;
      }
      case "switch": hopTo(el, id); break;
      case "account-menu": ui.menu = ui.menu === id ? null : id; ui.confirming = null; render(); break;
      case "add": act(el, () => api("/api/add", { tool: el.dataset.tool }), "Signing out"); break;
      case "add-stop": act(el, () => api("/api/add/stop", { tool: el.dataset.tool }), "Stopping"); break;
      case "edit": ui.editing = id; ui.confirming = null; ui.menu = null; render(); $("form[data-form=rename] input")?.focus(); break;
      case "cancel-edit": ui.editing = null; render(); break;
      case "confirm-remove": ui.confirming = id; ui.editing = null; ui.menu = null; render(); break;
      case "cancel-remove": ui.confirming = null; render(); break;
      case "remove": act(el, () => api("/api/remove", { id }).finally(() => { ui.confirming = null; }), "Removing"); break;
      case "reserve": ui.menu = null; act(null, () => api("/api/reserve", { id, on: el.dataset.value === "on" })); break;
      case "range-menu":
        ui.rangeOpen = !ui.rangeOpen;
        render();
        if (ui.rangeOpen) $(".range-list [aria-checked=true]")?.focus();
        break;
      case "all-periods": ui.allPeriods = true; render(); break;
      case "series": {
        const hidden = ui.hidden[ui.group] || (ui.hidden[ui.group] = []);
        const at = hidden.indexOf(el.dataset.value);
        const total = chartGroup(data.usage[`${ui.range}:${ui.tool}`] || {}, ui.group).series?.length || 0;
        if (at >= 0) hidden.splice(at, 1);
        else if (hidden.length < total - 1) hidden.push(el.dataset.value); // At least one part stays.
        transition(render);
        break;
      }
      case "day": showUsage({ range: `${el.dataset.value}..${el.dataset.value}` }); break;
      case "breakdown": ui.breakdown = el.dataset.value; ui.allPeriods = false; render(); break;
      case "range": case "metric": case "group":
        ui[el.dataset.action] = el.dataset.value;
        if (el.dataset.action === "range") ui.rangeOpen = false;
        if (el.dataset.action === "group") transition(render); else render();
        if (el.dataset.action === "range") { await loadSection(); render(); }
        break;
      case "filter-tool":
        if (!el.dataset.value || el.dataset.value === ui.tool) break;
        ui.tool = el.dataset.value;
        render();
        await loadSection();
        render();
        break;
      case "export-csv": {
        const usage = data.usage[`${ui.range}:${ui.tool}`];
        if (usage) exportCSV(usage);
        break;
      }
      case "work-on": act(el, () => api("/api/work", { enabled: true }), "Turning on"); break;
      case "work-off": act(el, () => api("/api/work", { enabled: false }), "Stopping"); break;
      case "work-subjects-on": act(el, () => api("/api/work", { shareSubjects: true }), "Sharing"); break;
      case "work-subjects-off": act(el, () => api("/api/work", { shareSubjects: false }), "Keeping here"); break;
      case "work-remove": act(el, () => api("/api/work", { remove: el.dataset.path }), "Removing"); break;
      case "work-index": act(el, () => api("/api/work", { index: true }), "Reading"); break;
      case "edit-budget": ui.budgetEdit = el.dataset.scope; render(); $("form[data-form=budget] input[name=amount]")?.focus(); break;
      case "cancel-budget": ui.budgetEdit = null; render(); break;
      case "delete-budget": act(el, () => api("/api/budget", { scope: el.dataset.scope === "all" ? "all" : el.dataset.scope.replace("account:", ""), amount: null })); break;
      case "check-update": await loadUpdate(true); break;
      case "copy":
        try { await navigator.clipboard.writeText(el.dataset.value); toast("Copied."); } catch { toast(el.dataset.value); }
        break;
      case "browser-install": await act(el, () => api("/api/browser/install", {}), "Setting up"); break;
      case "browser-remove": await act(el, () => api("/api/browser/remove", {}), "Removing"); break;
      case "install-update": act(el, () => api("/api/update", {}), "Installing"); break;
      case "cloud-link": act(el, () => api("/api/cloud/link", {}), "Opening GitHub"); break;
      case "cloud-sync": act(el, () => api("/api/cloud/sync", {}), "Syncing"); break;
      case "streak-claim": act(el, () => api("/api/cloud/streak", {}), "Claiming"); break;
      case "cloud-unlink": data.board = null; act(el, () => api("/api/cloud/unlink", {}), "Unlinking"); break;
      case "cloud-limits-on": act(el, () => api("/api/cloud/limits", { on: true }), "Turning on"); break;
      case "cloud-limits-off": act(el, () => api("/api/cloud/limits", { on: false }), "Stopping"); break;
      case "update-channel":
        if (data.update?.channel === el.dataset.value) break;
        ui.checkingUpdate = true;
        render();
        try { data.update = await api("/api/update/channel", { channel: el.dataset.value }); data.updateError = null; }
        catch (error) { data.updateError = error.message; }
        ui.checkingUpdate = false;
        render();
        break;
      case "team-digest-off":
        act(el, async () => { const result = await api("/api/cloud/team", { digestOff: ui.boardTeam }); data.board = null; data.day = null; return result; }, "Turning off");
        break;
      case "cloud-live-on": act(el, () => api("/api/cloud/live", { on: true }), "Turning on"); break;
      case "cloud-live-off": act(el, () => api("/api/cloud/live", { on: false }), "Stopping"); break;
      case "cloud-show-data":
        data.outbound = null;
        data.outboundError = null;
        try { data.outbound = await api("/api/cloud/show-data"); } catch (error) { data.outboundError = error.message; }
        render();
        break;
      case "board-division":
        ui.boardDivision = el.dataset.value;
        data.board = null;
        render();
        await loadSection();
        render();
        break;
      case "board-season":
        if (el.dataset.value === ui.boardSeason) break;
        ui.boardSeason = el.dataset.value;
        data.board = null;
        render();
        await loadSection();
        render();
        break;
      case "board-period": case "board-metric":
        ui[el.dataset.action === "board-period" ? "boardPeriod" : "boardMetric"] = el.dataset.value;
        data.board = null;
        render();
        await loadSection();
        render();
        break;
      case "board-view":
        if (el.dataset.value === ui.boardView) break;
        ui.boardView = el.dataset.value;
        if (ui.boardView === "day") ui.boardDate = "";
        data.day = null;
        render();
        await loadSection();
        render();
        break;
      case "day-step":
        ui.boardDate = el.dataset.value;
        data.day = null;
        render();
        await loadSection();
        render();
        break;
      case "board-pick":
        ui.boardTeam = el.dataset.value;
        ui.boardView = "day";
        ui.boardDate = "";
        data.invite = null;
        data.day = null;
        if (ui.section !== "teams") { await go("teams"); break; }
        render();
        await loadSection();
        render();
        break;
      case "team-invite":
        act(el, async () => {
          const result = await api("/api/cloud/team", { invite: ui.boardTeam });
          data.invite = result.url;
          return result;
        }, "Creating link");
        break;
      case "team-revoke":
        data.invite = null;
        act(el, () => api("/api/cloud/team", { revoke: ui.boardTeam }), "Turning off");
        break;
      case "team-leave": {
        const slug = ui.boardTeam;
        ui.boardTeam = "";
        data.invite = null;
        data.board = null;
        data.day = null;
        act(el, () => api("/api/cloud/team", { leave: slug }), "Leaving");
        break;
      }
      case "team-remove":
        act(el, () => api("/api/cloud/team", { slug: ui.boardTeam, member: el.dataset.login }), "Removing");
        break;
      case "app-revoke":
        act(el, async () => {
          const result = await api("/api/cloud/apps", { id: el.dataset.id });
          data.apps = null;
          if (result.unlinked) { data.board = null; data.profile = null; }
          return result;
        }, "Unlinking");
        break;
    }
  });

  document.addEventListener("change", async (event) => {
    const publish = event.target.closest("[data-action=team-public]");
    if (publish) {
      act(publish, () => api("/api/cloud/team", { slug: ui.boardTeam, public: publish.checked }), publish.checked ? "Publishing" : "Hiding");
      return;
    }
    const team = event.target.closest("select[data-action=board-team]");
    if (team) {
      ui.boardTeam = team.value;
      if (!team.value) ui.boardView = "ranks";
      team.blur();
      data.board = null;
      data.day = null;
      render();
      await loadSection();
      render();
      return;
    }
    const select = event.target.closest("select[data-action=tool]");
    if (!select) return;
    ui.tool = select.value;
    select.blur();
    render();
    await loadSection();
    render();
  });

  document.addEventListener("submit", (event) => {
    const form = event.target;
    event.preventDefault();
    const button = form.querySelector("button:not([type=button])");
    if (form.dataset.form === "rename") {
      const id = form.dataset.id, name = form.elements.name.value;
      ui.editing = null;
      act(button, () => api("/api/rename", { id, name }));
    }
    if (form.dataset.form === "budget") {
      const amount = parseFloat(String(form.elements.amount.value).replace(/[$,\s]/g, ""));
      if (!(amount > 0)) { toast("Type an amount in dollars, like 200.", true); return; }
      const scope = form.elements.scope.value, period = form.elements.period.value;
      ui.budgetEdit = null;
      act(button, () => api("/api/budget", { scope, amount, period }));
    }
    if (form.dataset.form === "range") {
      const from = form.elements.from.value, to = form.elements.to.value;
      if (!from || !to) { toast("Pick both days.", true); return; }
      ui.range = from <= to ? `${from}..${to}` : `${to}..${from}`;
      ui.rangeOpen = false;
      render();
      loadSection().then(render);
    }
    if (form.dataset.form === "profile") {
      act(button, async () => {
        const result = await api("/api/cloud/profile", {
          displayName: form.elements.displayName.value,
          bio: form.elements.bio.value,
          link: form.elements.link.value,
          public: form.elements.public.checked,
        });
        data.profile = null;
        return result;
      }, "Saving");
    }
    if (form.dataset.form === "team-create") {
      const name = String(form.elements.name.value || "").trim();
      if (name.length < 2) { toast("Give the team a name of at least 2 characters.", true); return; }
      act(button, async () => {
        const result = await api("/api/cloud/team", { name });
        if (result.slug) { ui.boardTeam = result.slug; ui.boardView = "day"; ui.boardDate = ""; data.day = null; data.board = null; }
        return result;
      }, "Creating");
    }
    if (form.dataset.form === "team-join") {
      const code = String(form.elements.code.value || "").trim();
      if (!code) { toast("Paste an invite link or its code.", true); return; }
      act(button, async () => {
        const result = await api("/api/cloud/team", { code });
        if (result.slug) { ui.boardTeam = result.slug; ui.boardView = "day"; ui.boardDate = ""; data.day = null; data.board = null; }
        return result;
      }, "Joining");
    }
    if (form.dataset.form === "team-digest") {
      const url = String(form.elements.url.value || "").trim();
      const hour = Number(form.elements.hour.value);
      if (!Number.isInteger(hour) || hour < 0 || hour > 23) { toast("The hour is 0 to 23, in UTC.", true); return; }
      act(button, async () => {
        const result = await api("/api/cloud/team", { slug: ui.boardTeam, digestUrl: url, digestHour: hour });
        data.board = null;
        data.day = null;
        return result;
      }, "Saving");
    }
    if (form.dataset.form === "team-delete") {
      const slug = ui.boardTeam;
      const confirm = String(form.elements.confirm.value || "").trim();
      if (confirm.toLowerCase() !== slug.toLowerCase()) { toast(`Type ${slug} to delete this team.`, true); return; }
      ui.boardTeam = "";
      data.invite = null;
      data.board = null;
      data.day = null;
      act(button, () => api("/api/cloud/team", { delete: slug, confirm }), "Deleting");
    }
    if (form.dataset.form === "account-delete") {
      const confirm = String(form.elements.confirm.value || "").trim();
      const login = data.profile?.login || data.state?.cloud?.login || "";
      if (confirm.toLowerCase() !== login.toLowerCase()) { toast(`Type ${login} to delete your account.`, true); return; }
      act(button, async () => {
        const result = await api("/api/cloud/account", { confirm });
        data.board = null;
        data.profile = null;
        data.apps = null;
        return result;
      }, "Deleting");
    }
    if (form.dataset.form === "work-folder") {
      const folder = String(form.elements.folder.value || "").trim();
      if (!folder) { toast("Type a folder to scan, like ~/Projects.", true); return; }
      act(button, () => api("/api/work", { add: folder }));
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && ui.menu) { ui.menu = null; render(); return; }
    if (event.key === "Escape" && ui.rangeOpen) { ui.rangeOpen = false; render(); $(".range-button")?.focus(); return; }
    if (event.key === "Escape" && (ui.editing || ui.confirming || ui.budgetEdit)) { ui.editing = ui.confirming = ui.budgetEdit = null; render(); return; }
    // Escape anywhere else steps back to the core screen.
    if (event.key === "Escape" && ui.section !== "home" && !["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement?.tagName || "")) go("home");
  });
  const followVisibility = () => document.documentElement.toggleAttribute("data-away", document.hidden);
  async function resumeRefresh() {
    followVisibility();
    if (document.hidden || isStatic || !data.state) return;
    try {
      await loadState();
      if (["home", "usage", "limits"].includes(ui.section)) await loadSection();
      if (!editing()) render(); else renderChrome();
    } catch (error) {
      ui.offline = error.message;
      if (!editing()) render();
    }
  }
  document.addEventListener("visibilitychange", resumeRefresh);
  followVisibility();
  addEventListener("hashchange", () => {
    // The hash is a plain section, or the launch form "s=<section>&k=<key>" a reopened link keeps.
    const raw = location.hash.slice(1);
    const section = asSection(raw.includes("=") ? new URLSearchParams(raw).get("s") || "" : raw);
    if (SECTIONS.includes(section) && section !== ui.section) go(section);
  });
  let resizeTimer;
  addEventListener("resize", () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(() => { if (!editing()) render(); }, 150); });

  // MARK: Start

  async function start() {
    if (isStatic) { render(); return; }
    if (!token) {
      $("#main").innerHTML = `<div class="page"><div class="card"><p class="empty">This window isn't connected to Keyhop. Open it from the tray, or run keyhop dashboard.</p></div></div>`;
      return;
    }
    try {
      await loadState();
      render();
      watchActivity();
      await loadSection();
      render();
    } catch (error) {
      $("#main").innerHTML = `<div class="page"><div class="notice">${icon("alert")}<div><p>${esc(error.message)}</p></div></div></div>`;
      return;
    }
    setInterval(async () => {
      if (document.hidden) return;
      try {
        await loadState();
        if (["home", "usage", "limits"].includes(ui.section)) await loadSection();
        if (!editing()) render(); else renderChrome();
        watchActivity();
      } catch (error) {
        ui.offline = error.message;
        if (!editing()) render();
      }
    }, 20000);
  }
  if (document.documentElement.classList.contains("mac-window")) {
    addEventListener("mousedown", (event) => {
      if (event.button !== 0 || !event.target.closest(".titlebar, .side-brand")) return;
      if (event.target.closest("button, a, input, select, textarea, label")) return;
      window.webkit?.messageHandlers?.keyhopWindow?.postMessage(event.detail === 2 ? "zoom" : "drag");
    });
  }
  start();
"""##
}
