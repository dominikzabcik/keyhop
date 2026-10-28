import Foundation

/// The page script's first part: state, formatting helpers and the data loaders every section shares.
extension DashboardPage {
    static let scriptCore = ##"""
  "use strict";
  const SECTIONS = ["home", "usage", "limits", "coach", "plans", "budgets", "leaderboard", "season", "teams", "profile", "settings"];
  const TITLES = { home: "Keyhop", usage: "Usage", limits: "Limits", coach: "Coach", plans: "Plans", budgets: "Budgets", leaderboard: "Leaderboard", season: "Season", teams: "Teams", profile: "Profile", settings: "Settings" };
  const CLOUD_SECTIONS = ["leaderboard", "season", "teams", "profile"];
  // The sidebar's sets: every view in the open, grouped the way the product thinks.
  // The core trio sits on top with no heading: hopping between logins and the token
  // overview are the product, everything under a heading is a side function.
  const GROUPS = [
    { id: "core", title: "Keyhop", sections: ["home", "usage", "limits"] },
    { id: "insights", title: "Insights", sections: ["coach", "plans", "budgets"] },
    { id: "community", title: "Community", sections: ["leaderboard", "season", "teams", "profile"] },
    { id: "settings", title: "Settings", sections: ["settings"] },
  ];
  // Links from before the core screen still land where they meant to.
  const SECTION_ALIASES = { overview: "home", accounts: "limits" };
  const asSection = (name) => SECTION_ALIASES[name] || name;
  const $ = (selector, root = document) => root.querySelector(selector);
  const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  const store = {
    get(key) { try { return sessionStorage.getItem(key); } catch { return null; } },
    set(key, value) { try { sessionStorage.setItem(key, value); } catch {} },
  };

  const boot = JSON.parse($("#boot").textContent || "null");
  const isStatic = !!boot;
  const params = new URLSearchParams(location.hash.slice(1));
  if (params.get("w") === "mac") document.documentElement.classList.add("mac-window");
  let token = params.get("k") || store.get("keyhop-token");
  if (params.get("k")) store.set("keyhop-token", token);
  const wanted = asSection(params.get("s") || location.hash.slice(1));
  const ui = {
    section: SECTIONS.includes(wanted) ? wanted : asSection(boot?.section || "home"),
    menu: null, hidden: { account: [], tool: [], model: [] },
    range: "week", rangeOpen: false, metric: "tokens", tool: "all", group: "account", breakdown: "periods", allPeriods: false,
    boardPeriod: "week", boardMetric: "efficiency", boardDivision: "", boardTeam: "", boardView: "ranks", boardDate: "", boardSeason: "",
    editing: null, confirming: null, budgetEdit: null, offline: null,
    settingsPane: "activity", checkingUpdate: false,
    quotaTool: "all", quotaHours: 24, quotaView: "left",
    pending: new Map(), loadingUsage: 0,
    // The hop the verdict just made: the verdict confirms it and offers the way back for 7 seconds.
    hopped: null,
  };
  if (!SECTIONS.includes(ui.section)) ui.section = "home";
  history.replaceState(null, "", "#" + ui.section);
  const data = { state: boot?.state || null, usage: {}, usageErrors: {}, doctor: null, update: null, updateError: null, pet: null, petError: null };
  if (isStatic) for (const [range, doc] of Object.entries(boot.usage || {})) data.usage[range + ":all"] = doc;

  // Share bars step through greys, lightest for the largest part; a hue would read as a state.
  const SHARE_GREYS = ["#cfcbc3", "#b3afa7", "#96928a", "#78746d", "#5a5751", "#3a3731"];

  // MARK: Formatting

  const fmt = {
    tokens(n) {
      const value = Math.abs(n || 0);
      const trim = (x, s) => { const t = x >= 100 ? x.toFixed(0) : x.toFixed(1); return (t.endsWith(".0") ? t.slice(0, -2) : t) + s; };
      return value >= 1e9 ? trim(n / 1e9, "B") : value >= 1e6 ? trim(n / 1e6, "M") : value >= 1e3 ? trim(n / 1e3, "K") : String(Math.round(n || 0));
    },
    usd(amount) {
      const a = amount || 0;
      return a >= 1000 ? "$" + Math.round(a).toLocaleString("en-US") : a >= 100 ? "$" + a.toFixed(0) : "$" + a.toFixed(2);
    },
    count(n) { return Math.round(n || 0).toLocaleString("en-US"); },
    relative(date) {
      const s = Math.round((Date.now() - new Date(date)) / 1000);
      const formatter = new Intl.RelativeTimeFormat(undefined, { numeric: "auto", style: "narrow" });
      if (s < 60) return formatter.format(0, "second");
      if (s < 3600) return formatter.format(-Math.floor(s / 60), "minute");
      if (s < 86400) return formatter.format(-Math.floor(s / 3600), "hour");
      return formatter.format(-Math.floor(s / 86400), "day");
    },
    until(date) {
      const s = Math.max(0, Math.round((new Date(date) - Date.now()) / 1000));
      const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
      return d ? `${d}d ${h}h` : h ? `${h}h ${m}m` : `${m}m`;
    },
    clock(date) { return new Intl.DateTimeFormat(undefined, { hour: "2-digit", minute: "2-digit" }).format(new Date(date)); },
    day(date, options) { return new Intl.DateTimeFormat(undefined, options).format(new Date(date)); },
    // `earlier` is the previous amount in words. A multiple past 99× is that amount: the
    // period before was nearly empty, and the multiple itself is noise.
    change(now, before, earlier) {
      if (!before) return "";
      const pct = Math.round(((now - before) / before) * 100);
      if (pct >= 900) {
        const times = Math.round(now / before);
        if (times > 99) return earlier ? `<span class="mono subtle">from ${earlier}</span>` : "";
        return `<span class="mono up">${times}×</span>`;
      }
      return pct === 0 ? `<span class="mono subtle">0%</span>` : `<span class="mono ${pct > 0 ? "up" : "down"}">${pct > 0 ? "+" : ""}${pct}%</span>`;
    },
  };
  const windowName = (label) => ({ "5h": "5-hour", "Week": "Weekly", "Opus": "Opus weekly", "Sonnet": "Sonnet weekly", "Auto": "Auto", "API": "API", "Plan": "Plan" })[label] || label;
  const mark = (tool) => `<svg class="mark" aria-hidden="true"><use href="#mark-${esc(tool)}"/></svg>`;
  // Every wait looks the same: the three-dot pulse, then what is being read. The words are always
  // there; only the dots move.
  const busy = (text, cls = "empty-inline") => `<p class="${cls} busy" role="status"><span class="pulse" aria-hidden="true"><i></i><i></i><i></i></span>${text}</p>`;
  // A wait that can say how far it has got: the step Keyhop is on, a count and a bar, updated in
  // place while the step runs. Before the first report it reads like any other wait.
  const loading = (text, cls = "empty-inline") => `<div class="loading ${cls === "empty" ? "empty" : ""}" data-loading="${esc(text)}">${loadingInner(text)}</div>`;
  function loadingInner(text) {
    const step = data.state?.activity;
    const title = step ? step.title : text;
    const count = step?.count ? `<span class="count">${esc(step.count)}</span>` : "";
    const hints = {
      history: "The first read goes through every log on this computer. After that, only what is new.",
      repositories: "The first index reads every repository you have. After that, only the ones that changed.",
    };
    const hint = hints[step?.step] ? `<small>${hints[step.step]}</small>` : step?.detail ? `<small>${esc(step.detail)}</small>` : "";
    const width = step?.fraction != null ? `style="width:${(step.fraction * 100).toFixed(1)}%"` : "";
    return `<p class="busy" role="status"><span class="pulse" aria-hidden="true"><i></i><i></i><i></i></span><b>${esc(title)}</b>${count}</p>
      <div class="meter${step?.fraction != null ? "" : " unknown"}" role="progressbar" aria-label="${esc(title)}" ${step?.fraction != null ? `aria-valuemin="0" aria-valuemax="100" aria-valuenow="${Math.round(step.fraction * 100)}"` : ""}><span ${width}></span></div>${hint}`;
  }
  // A report that couldn't be read says why, and offers to read it again.
  const failed = (message) => `<div class="notice">${icon("alert")}<div><p>${esc(message)}</p></div>${isStatic ? "" : `<button class="btn sm secondary" type="button" data-action="section-retry">Try again</button>`}</div>`;
  const icon = (name) => `<svg class="icon" aria-hidden="true"><use href="#i-${name}"/></svg>`;
  const maxUsed = (account) => Math.max(0, ...(account.limits || []).map((l) => l.usedPercent));
  // What a login has left on its tightest window, as Keyhop reads it (its `room`), or null when
  // there is no limit to read.
  const leftOf = (account) => !account?.limits?.length ? null
    : Math.round(Math.max(0, Math.min(100, account.room ?? (100 - maxUsed(account)))));
  const toolName = (id) => (data.state?.status.tools.find((t) => t.id === id) || {}).name || id;

  // MARK: Data

  // Most answers come at once; a report over a month of history can wait on the logs being read.
  async function api(path, body, wait = 30_000) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), wait);
    const init = { method: body === undefined ? "GET" : "POST", headers: { Authorization: "Bearer " + token }, signal: controller.signal };
    if (body !== undefined) { init.headers["Content-Type"] = "application/json"; init.body = JSON.stringify(body); }
    let response;
    try {
      response = await fetch(path, init);
    } catch (error) {
      if (error.name === "AbortError") throw new Error("Keyhop took too long to answer. Try again.");
      throw new Error("Keyhop isn't running anymore. Open it again from the tray or with keyhop dashboard.");
    } finally {
      clearTimeout(timeout);
    }
    let payload = {};
    try { payload = await response.json(); } catch {}
    if (!response.ok) throw new Error(payload.error || `Keyhop answered ${response.status}.`);
    return payload;
  }

  async function loadState() {
    if (isStatic) return;
    data.state = await api("/api/state");
    ui.offline = null;
    for (const message of data.state.messages || []) toast(message);
  }

  async function loadUsage(range, tool = "all") {
    const key = `${range}:${tool}`;
    if (isStatic) return data.usage[key] || data.usage[`${range}:all`];
    // Only a first read shows a wait: after that the last figures stay up while new ones come in.
    const first = !data.usage[key];
    if (first) { ui.loadingUsage = (ui.loadingUsage || 0) + 1; watchActivity(); }
    try {
      data.usage[key] = await api(`/api/usage?range=${encodeURIComponent(range)}&tool=${encodeURIComponent(tool)}`);
      delete data.usageErrors[key];
    } catch (error) {
      data.usageErrors[key] = error.message;
      if (!data.usage[key]) throw error;
    } finally {
      if (first) ui.loadingUsage -= 1;
    }
    return data.usage[key];
  }

  // The providers' status pages are read on their own, so a slow page never holds the core up.
  // Read again at most every two minutes; Keyhop caches each page for five.
  let servicesLoading = false;
  function loadServices() {
    if (isStatic || servicesLoading || (data.servicesAt && Date.now() - data.servicesAt < 120_000)) return;
    servicesLoading = true;
    api("/api/services")
      .then((list) => { data.services = list; data.servicesAt = Date.now(); if (ui.section === "home" || ui.section === "limits") render(); })
      .catch(() => {})
      .finally(() => { servicesLoading = false; });
  }

  // Release checks have their own state. They never borrow the progress bar or make the
  // rest of the window look busy.
  async function loadUpdate(force = false) {
    if (isStatic || ui.checkingUpdate || (!force && (data.update || data.updateError))) return;
    ui.checkingUpdate = true;
    data.updateError = null;
    if (ui.section === "settings") render();
    try {
      data.update = await api("/api/update");
    } catch (error) {
      data.updateError = error.message;
    } finally {
      ui.checkingUpdate = false;
      if (ui.section === "settings") render();
    }
  }

  async function loadPet() {
    try {
      data.pet = await api("/api/cloud/pet");
      data.petError = null;
    } catch (error) {
      data.petError = error.message;
    }
  }

  // What every login had left at each reading, kept 8 days: Limits draws it, measured only.
  async function loadQuota() {
    if (isStatic) return;
    try { data.quota = await api("/api/quota"); data.quotaError = null; }
    catch (error) { data.quotaError = error.message; }
  }

  async function loadSection() {
    try {
      if (ui.section === "home" || ui.section === "limits") loadServices();
      // The core screen draws at once; the runway fills in when the history arrives.
      if (ui.section === "home") loadQuota().then(() => { if (ui.section === "home" && !editing()) render(); });
      if (ui.section === "home") await loadUsage("today");
      // Limits draws its logins at once; the history fills in when it arrives.
      if (ui.section === "limits") loadQuota().then(() => { if (ui.section === "limits" && !editing()) render(); });
      if (ui.section === "usage") await loadUsage(ui.range, ui.tool);
      if (ui.section === "budgets") await loadUsage("month");
      if (ui.section === "coach" && !isStatic) {
        try { data.coach = await api("/api/coach", undefined, 180_000); data.coachError = null; } catch (error) { data.coachError = error.message; }
      }
      if (ui.section === "plans" && !isStatic) {
        try { data.plans = await api("/api/plans", undefined, 180_000); data.plansError = null; } catch (error) { data.plansError = error.message; }
      }
      if (!isStatic && data.state?.cloud?.linked && CLOUD_SECTIONS.includes(ui.section)) {
        const petReady = ui.section === "profile" ? loadPet() : null;
        const boardURL = (team) => `/api/cloud/leaderboard?period=${ui.boardPeriod}&metric=${ui.boardMetric}&division=${ui.boardDivision}&team=${encodeURIComponent(team)}&season=${encodeURIComponent(ui.boardSeason)}`;
        try {
          if (ui.section === "teams" && ui.boardView === "day") {
            data.day = await api(`/api/cloud/day?team=${encodeURIComponent(ui.boardTeam)}&date=${encodeURIComponent(ui.boardDate)}`);
            data.dayError = null;
            if (data.day.team) ui.boardTeam = data.day.team.slug;
            if (data.day.day) ui.boardDate = data.day.day;
          } else if (ui.section === "teams" && ui.boardTeam) {
            data.board = await api(boardURL(ui.boardTeam));
            data.boardError = null;
          } else {
            data.board = await api(boardURL(""));
            data.boardError = null;
          }
          // A website older than the efficiency board answers with the measure it knows; the tabs follow it.
          const answered = data.board?.board?.metric;
          if (answered && answered !== ui.boardMetric) ui.boardMetric = answered;
        } catch (error) {
          if (ui.section === "teams" && ui.boardView === "day") data.dayError = error.message;
          else data.boardError = error.message;
        }
        if (petReady) await petReady;
      }
      if (ui.section === "settings" && !isStatic) {
        const doctor = api("/api/doctor");
        api("/api/browser").then((report) => { data.browser = report; data.browserError = null; }, (error) => { data.browserError = error.message; })
          .finally(() => { if (ui.section === "settings" && !editing()) render(); });
        loadUpdate();
        data.doctor = await doctor;
        if (data.state?.cloud?.linked) {
          try { data.profile = await api("/api/cloud/profile"); } catch (error) { data.profileError = error.message; }
          try { data.apps = await api("/api/cloud/apps"); data.appsError = null; } catch (error) { data.appsError = error.message; }
        }
      }
    } catch (error) {
      ui.offline = error.message;
    }
  }

"""##
}
