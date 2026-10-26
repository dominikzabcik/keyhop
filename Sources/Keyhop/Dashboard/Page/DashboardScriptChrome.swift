import Foundation

/// The title bar, the view bar, motion and progress: what stays while sections change.
extension DashboardPage {
    static let scriptChrome = ##"""
  // MARK: Motion

  // Motion only ever carries a change the page already shows. Every value is written into the
  // markup first, then eased there from where it was, so a skipped, throttled or reduced animation
  // leaves the page right, never blank or half-way.
  const still = matchMedia("(prefers-reduced-motion: reduce)");
  const memory = new Map();
  const ease = (t) => 1 - Math.pow(1 - t, 3);
  const FORMATS = {
    count: fmt.count,
    tokens: fmt.tokens,
    usd: fmt.usd,
    usdExact: (v) => "$" + (v || 0).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 }),
    pct: (v) => (v > 0 && v < 1 ? "<1%" : `${Math.round(v)}%`),
  };

  // Numbers count from their last value to the new one; on first sight, marked ones count up.
  function countNumbers(root) {
    for (const el of root.querySelectorAll("[data-count]")) {
      const key = "n:" + el.dataset.countKey, to = +el.dataset.count, final = el.textContent;
      const from = memory.has(key) ? memory.get(key) : el.hasAttribute("data-count-intro") ? to * 0.35 : to;
      memory.set(key, to);
      if (still.matches || !isFinite(from) || !isFinite(to) || from === to) continue;
      const format = FORMATS[el.dataset.format] || fmt.count;
      const began = performance.now(), length = 760;
      const frame = (now) => {
        if (!el.isConnected) return;
        const t = Math.min(1, (now - began) / length);
        el.textContent = t < 1 ? format(from + (to - from) * ease(t)) : final;
        if (t < 1) requestAnimationFrame(frame);
      };
      requestAnimationFrame(frame);
      // Whatever happens to the frames, the exact value is back when the count should be done.
      setTimeout(() => { if (el.isConnected) el.textContent = final; }, length + 240);
    }
  }

  // Bars grow from their last length to the new one, and from nothing the first time.
  function growBars(root) {
    const grown = [];
    for (const el of root.querySelectorAll("[data-grow]")) {
      const key = "g:" + el.dataset.grow, prop = el.dataset.growProp || "width";
      const to = el.style[prop];
      const from = memory.has(key) ? memory.get(key) : prop === "flexGrow" ? "0" : "0%";
      memory.set(key, to);
      if (still.matches || from === to) continue;
      el.style.transition = "none";
      el.style[prop] = from;
      grown.push([el, prop, to]);
    }
    if (!grown.length) return;
    // One layout read, so every bar starts from its old length before easing to the new one.
    void document.body.offsetWidth;
    for (const [el, prop, to] of grown) { el.style.transition = ""; el.style[prop] = to; }
  }

  // A segmented control's pressed option sits on a thumb that slides between options.
  function slideThumbs(root) {
    for (const group of root.querySelectorAll(".tabs[data-tabs]")) {
      const on = group.querySelector('[aria-pressed="true"]');
      if (!on || !on.offsetWidth) continue;
      const key = "t:" + group.dataset.tabs, next = { x: on.offsetLeft, w: on.offsetWidth };
      placeThumb(group, key, next, "--thumb-x", "--thumb-w", (p) => `${p.x}px`, (p) => `${p.w}px`);
    }
  }

  function placeThumb(group, key, next, xVar, sizeVar, x, size) {
    const last = memory.get(key);
    memory.set(key, next);
    group.classList.add("has-thumb");
    const set = (p) => { group.style.setProperty(xVar, x(p)); group.style.setProperty(sizeVar, size(p)); };
    if (last && !still.matches && (last.x !== next.x || last.w !== next.w)) {
      group.classList.add("no-slide");
      set(last);
      group.getBoundingClientRect();
      group.classList.remove("no-slide");
    }
    set(next);
  }

  function animate(root = document) {
    growBars(root);
    countNumbers(root);
    slideThumbs(root);
  }

  // Moving between views cross-fades and settles the page, where the browser can. Elsewhere the
  // page simply changes, as it always has.
  function transition(change) {
    if (!document.startViewTransition || still.matches) { change(); return; }
    try { document.startViewTransition(change); } catch { change(); }
  }

  // A small line of how something moved across the range, drawn to fill its box. Long ranges are
  // averaged into fewer steps, so it shows the trend rather than every weekday dip.
  function sparkline(values, color, per) {
    if (values.length < 3 || !values.some((v) => v > 0)) return "";
    // `per` groups a fixed number of buckets into one step, like whole weeks of days.
    const steps = per ? Math.ceil(values.length / per) : Math.min(20, values.length), size = values.length / steps;
    const points = Array.from({ length: steps }, (_, i) => {
      const slice = values.slice(Math.floor(i * size), Math.max(Math.floor(i * size) + 1, Math.floor((i + 1) * size)));
      return slice.reduce((s, v) => s + v, 0) / slice.length;
    });
    const peak = Math.max(...points) || 1, n = points.length - 1;
    const xy = points.map((v, i) => [(i / n) * 100, 21 - (v / peak) * 18]);
    // Through the midpoints between samples, so the line bends instead of kinking.
    let line = `M${xy[0][0].toFixed(1)},${xy[0][1].toFixed(1)}`;
    for (let i = 1; i < xy.length; i++) {
      const [px, py] = xy[i - 1], [x, y] = xy[i];
      line += `Q${px.toFixed(1)},${py.toFixed(1)} ${((px + x) / 2).toFixed(1)},${((py + y) / 2).toFixed(1)}`;
    }
    line += `L${xy[n][0].toFixed(1)},${xy[n][1].toFixed(1)}`;
    return `<svg class="spark" viewBox="0 0 100 24" preserveAspectRatio="none" aria-hidden="true">
      <path d="${line}L100,24L0,24Z" fill="${color}" fill-opacity=".14"/>
      <path d="${line}" fill="none" stroke="${color}" stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke"/>
    </svg>`;
  }

  // A hover card's content, kept in the element and shown by the shared tip.
  const tipAttr = (title, lines = []) => ` data-tip="${esc(`<b>${esc(title)}</b>${lines.map(([k, v]) => `<div><span></span><span>${esc(k)}</span><span class="mono">${esc(v)}</span></div>`).join("")}`)}"`;

  // MARK: Shell

  // Whether a section can open: the cloud's sections need the website, and all but the
  // leaderboard a linked account.
  function sectionShown(section) {
    if (!CLOUD_SECTIONS.includes(section)) return true;
    const cloud = data.state?.cloud;
    const cloudOn = !isStatic && !!cloud?.available;
    return section === "leaderboard" ? cloudOn : cloudOn && !!cloud.linked && !cloud.linking;
  }

  let linkPoll = null;

  function render() {
    renderChrome();
    if (!data.state) return;
    const tools = data.state.status.tools;
    const cloud = data.state.cloud;
    if (!sectionShown(ui.section)) ui.section = "home";
    // While a link waits for approval in the browser, check every few seconds instead of every 20.
    if (cloud?.linking && !linkPoll) {
      linkPoll = setTimeout(async () => {
        linkPoll = null;
        try { await loadState(); if (data.state.cloud.linked) await loadSection(); } catch {}
        render();
      }, 3000);
    }
    const page = { home: homePage, usage: usagePage, limits: limitsPage, coach: coachPage, plans: plansPage, budgets: budgetsPage, leaderboard: leaderboardPage, season: seasonPage, teams: teamsPage, profile: profilePage, settings: settingsPage }[ui.section](tools);
    renderViewbar(page.toolbar || "");
    const offline = ui.offline ? `<div class="notice">${icon("alert")}<div><p>${esc(ui.offline)}</p></div></div>` : "";
    $("#main").innerHTML = ui.section === "home" ? `${offline ? `<div class="page">${offline}</div>` : ""}${page.body}` : `<div class="page">${offline}${page.body}</div>`;
    $("#main").setAttribute("aria-busy", (ui.loadingUsage || data.state.refreshing) ? "true" : "false");
    applyPending();
    renderActivity();
    animate();
  }

  // The view bar names the demoted view, offers its sections, and holds its controls. The core
  // screen needs none of it.
  function renderViewbar(controls) {
    const bar = $("#viewbar");
    if (!bar) return;
    const home = ui.section === "home";
    bar.hidden = home;
    $("#gear")?.setAttribute("aria-current", ui.section === "settings" ? "page" : "false");
    if (home) return;
    const group = groupOf(ui.section);
    ui.lastIn[group.id] = ui.section;
    $("#title").textContent = group.title;
    const shown = group.sections.filter(sectionShown);
    const tabsHTML = shown.length > 1 ? `<div class="tabs" role="group" aria-label="${esc(group.title)}" data-tabs="view">${shown.map((section) =>
      `<button type="button" data-action="goto" data-section="${section}" aria-pressed="${section === ui.section}">${esc(TITLES[section])}</button>`).join("")}</div>` : "";
    const viewtabs = $("#viewtabs");
    if (viewtabs.dataset.drawn !== tabsHTML) { viewtabs.innerHTML = tabsHTML; viewtabs.dataset.drawn = tabsHTML; }
    // The bar's controls are only redrawn when they change, so a press is never lost to a redraw.
    const toolbar = $("#toolbar");
    if (toolbar.dataset.drawn !== controls) { toolbar.innerHTML = controls; toolbar.dataset.drawn = controls; }
  }

  // The title bar: the mode, the views, a word when a tool's service is in trouble, the read
  // time, refresh. The views sit here the way an app's do: always on, quiet until current.
  function renderChrome() {
    const state = data.state;
    const nav = $("#topnav");
    if (nav) {
      const groups = GROUPS.filter((group) => group.id !== "settings" && group.sections.some(sectionShown));
      const current = groupOf(ui.section).id;
      const html = groups.map((group) =>
        `<button type="button" data-action="goto-group" data-group="${group.id}" aria-current="${current === group.id ? "page" : "false"}">${group.id === "home" ? "Home" : esc(group.title)}</button>`).join("");
      if (nav.dataset.drawn !== html) { nav.innerHTML = html; nav.dataset.drawn = html; }
    }
    const mode = $("#mode");
    if (mode) {
      mode.innerHTML = isStatic ? `<span class="badge">Saved</span>` : state?.mode === "sample" ? `<span class="badge sample">Sample</span>` : "";
      mode.hidden = !mode.textContent.trim();
    }
    const out = $("#status-outage");
    const troubled = (data.services || []).find((service) => serviceShort[service.level]);
    if (out) {
      out.hidden = !troubled;
      if (troubled) {
        const incident = troubled.incidents && troubled.incidents[0];
        out.href = incident?.link || troubled.page || "#";
        out.innerHTML = `${mark(troubled.tool)}${esc(`${toolName(troubled.tool)} ${serviceShort[troubled.level]}`)}`;
      }
    }
    for (const refresh of [$("#refresh")]) {
      if (!refresh) continue;
      refresh.disabled = isStatic;
      refresh.classList.toggle("spin", !!state?.refreshing);
      refresh.setAttribute("aria-busy", state?.refreshing ? "true" : "false");
    }
    renderReadtime();
    renderActivity();
  }

  // "read 6 s ago", living in the title bar and ticking on its own; amber once it goes stale.
  function renderReadtime() {
    const el = $("#readtime");
    if (!el) return;
    const read = data.state?.status?.refreshedAt;
    if (!read) { el.textContent = isStatic ? "" : "not read yet"; el.classList.remove("stale"); return; }
    const seconds = Math.max(0, Math.round((Date.now() - new Date(read)) / 1000));
    el.textContent = seconds < 60 ? `read ${seconds} s ago` : seconds < 5400 ? `read ${Math.round(seconds / 60)} min ago` : `read ${fmt.relative(read)}`;
    el.classList.toggle("stale", seconds > 120);
  }
  setInterval(renderReadtime, 5000);

  // MARK: Progress

  // How long a new login has been awaited, as a clock that ticks in place ("0:42").
  const waited = (tool) => {
    const since = data.state?.addingSince?.[tool];
    return since ? `<span class="num subtle" data-since="${esc(since)}">${clock(since)}</span>` : "";
  };
  function clock(since) {
    const seconds = Math.max(0, Math.floor((Date.now() - new Date(since).getTime()) / 1000));
    return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
  }
  setInterval(() => { for (const node of document.querySelectorAll("[data-since]")) node.textContent = clock(node.dataset.since); }, 1000);

  // Updates every progress display in place, so a running refresh never re-draws the page.
  function renderActivity() {
    const state = data.state;
    const step = state?.activity;
    const busyNow = !!(state?.refreshing || step || ui.loadingUsage);
    const read = state?.status?.refreshedAt;
    const label = step ? `${step.title}${step.count ? ` · ${step.count}` : ""}` : state?.refreshing ? "Starting…" : ui.loadingUsage ? "Reading usage" : read ? `Limits read ${fmt.relative(read)}` : "Limits not read yet";
    const refresh = $("#refresh");
    if (refresh) refresh.title = busyNow ? label : `${label}. Read again`;
    $("#main")?.setAttribute("aria-busy", busyNow ? "true" : "false");
    for (const meter of [$("#top-meter")]) {
      if (!meter) continue;
      const known = step?.fraction != null;
      meter.classList.toggle("unknown", busyNow && !known);
      meter.firstElementChild.style.width = known ? `${(step.fraction * 100).toFixed(1)}%` : "";
      meter.classList.toggle("on", busyNow);
      meter.setAttribute("aria-hidden", busyNow ? "false" : "true");
      if (known) meter.setAttribute("aria-valuenow", Math.round(step.fraction * 100)); else meter.removeAttribute("aria-valuenow");
    }
    for (const node of document.querySelectorAll("[data-loading]")) node.innerHTML = loadingInner(node.dataset.loading);
  }

  // While Keyhop is working, ask how far it has got a few times a second; otherwise every 20 seconds.
  let watching = false;
  async function watchActivity() {
    if (watching || isStatic) return;
    watching = true;
    try {
      const busyNow = () => data.state?.refreshing || data.state?.activity || ui.loadingUsage || ui.pending.size;
      // A new login can take minutes to arrive, so that wait is checked less often.
      while (busyNow() || data.state?.adding?.length) {
        await new Promise((resolve) => setTimeout(resolve, busyNow() ? 450 : 1500));
        try {
          const wasRefreshing = data.state?.refreshing;
          const wasAdding = (data.state?.adding || []).join();
          await loadState();
          renderActivity();
          const addingChanged = wasAdding !== (data.state.adding || []).join();
          if ((wasRefreshing && !data.state.refreshing || addingChanged) && !ui.pending.size) {
            await loadSection();
            if (!editing()) render(); else renderChrome();
          }
        } catch {
          // Keyhop stopped answering: whatever was running is no longer known to be running, and a
          // bar that keeps moving would say otherwise.
          if (data.state) { data.state.refreshing = false; data.state.activity = null; }
          break;
        }
      }
    } finally {
      watching = false;
      renderActivity();
    }
  }

  // Buttons whose work is still running, keyed by what they act on, so a re-drawn page keeps them busy.
  const pendingKey = (el) => [el.dataset.action, el.dataset.id || el.dataset.tool || el.dataset.scope || el.dataset.value || ""].join(":");
  function applyPending() {
    for (const el of document.querySelectorAll("button[data-action]")) {
      const label = ui.pending.get(pendingKey(el));
      if (label === undefined) continue;
      el.disabled = true;
      el.classList.add("working");
      el.setAttribute("aria-busy", "true");
      el.innerHTML = `<span class="ring" aria-hidden="true"></span>${esc(label || el.textContent.trim())}`;
    }
  }

  function tabs(name, options, current, disabled = false) {
    return `<div class="tabs" role="group" data-tabs="${esc(name)}">${options.map(([value, label]) =>
      `<button type="button" data-action="${name}" data-value="${value}" aria-pressed="${value === current}" ${disabled ? "disabled" : ""}>${esc(label)}</button>`).join("")}</div>`;
  }

  // `grow`, when given, names the bar so it grows from its last length (see growBars).
  function progress(percent, pace, tone, grow) {
    const width = Math.min(100, Math.max(0, percent));
    // "plain" is for rankings, where a full bar means the largest, not a limit running out.
    // A limit reads by how full it is, nothing more: amber from 75%, red from 90%.
    void pace;
    const state = tone === "plain" ? "" : tone || (width >= 90 ? "bad" : width >= 75 ? "warn" : "");
    return `<div class="progress ${state}"><span style="width:${width.toFixed(1)}%"${grow ? ` data-grow="${esc(ui.section + ":" + grow)}"` : ""}></span></div>`;
  }

  function limitFoot(limit) {
    return limit.resetsAt ? `Resets in ${fmt.until(limit.resetsAt)}` : "";
  }

  function closest(tools) {
    let best = null;
    for (const tool of tools) for (const account of tool.accounts) {
      if (!account.active || !account.limits?.length) continue;
      const top = account.limits.reduce((a, b) => (b.usedPercent > a.usedPercent ? b : a));
      if (!best || top.usedPercent > best.limit.usedPercent) best = { tool, account, limit: top };
    }
    return best;
  }

  // Where a tool would hop: Keyhop's own Smart Hop pick, the same one the menu and the
  // notifications offer, when it is another login with clearly more room.
  function alternative(tool, current) {
    const rec = (data.state?.status?.recommendations || []).find((item) => item.tool === tool.id);
    const pick = rec && !rec.active ? tool.accounts.find((account) => account.id === rec.account) : null;
    if (!pick || pick.error || rec.room < 20) return null;
    const here = current && !current.error ? leftOf(current) : null;
    return here == null || rec.room > here + 10 ? pick : null;
  }

"""##
}
