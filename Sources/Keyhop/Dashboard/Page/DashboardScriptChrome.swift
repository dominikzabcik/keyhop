import Foundation

/// The sidebar, status bar, motion, the Hop palette and progress: what stays while sections change.
extension DashboardPage {
    static let scriptChrome = ##"""
  // MARK: Shell

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

  // The sidebar's current section, on the same kind of thumb, running down the list.
  function labelNav() {
    [...document.querySelectorAll("#nav a, .side-foot a[data-section]")].filter((a) => !a.hidden).forEach((link, i) => {
      const name = link.dataset.group ? GROUPS.find((item) => item.id === link.dataset.group).title : TITLES[link.dataset.section];
      link.title = i < 9 ? `${name} · press ${i + 1}` : name;
    });
  }

  // Whether a section can open: the cloud's sections need the website, and all but the
  // leaderboard a linked account.
  function sectionShown(section) {
    if (!CLOUD_SECTIONS.includes(section)) return true;
    const cloud = data.state?.cloud;
    const cloudOn = !isStatic && !!cloud?.available;
    return section === "leaderboard" ? cloudOn : cloudOn && !!cloud.linked && !cloud.linking;
  }

  // A place with several sections shows them as tabs beside its title.
  function subnavHTML() {
    const group = groupOf(ui.section);
    const shown = group.sections.filter(sectionShown);
    if (shown.length < 2) return "";
    return `<div class="tabs subnav" role="group" aria-label="${esc(group.title)}" data-tabs="subnav-${esc(group.id)}">${shown.map((section) =>
      `<button type="button" data-action="goto" data-section="${section}" aria-pressed="${section === ui.section}">${esc(TITLES[section])}</button>`).join("")}</div>`;
  }

  function slideNav() {
    const nav = $("#nav"), on = nav?.querySelector('a[aria-current="page"]');
    if (!nav) return;
    if (!on || !on.offsetHeight) { nav.classList.remove("has-thumb"); return; }
    placeThumb(nav, "nav", { x: on.offsetTop, w: on.offsetHeight }, "--nav-y", "--nav-h", (p) => `${p.x}px`, (p) => `${p.w}px`);
  }

  function animate(root = document) {
    growBars(root);
    countNumbers(root);
    slideThumbs(root);
  }

  // Moving between sections cross-fades and settles the page, where the browser can. Elsewhere the
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

  // MARK: Jump to

  // One keystroke to anywhere: a section, a range, a tool, an account to switch to, or an action.
  let palette = null;
  const isMac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent);

  // The sections the sidebar shows, in its order; key 1 opens the first, 2 the second, and so on.
  const shownSections = () => [...document.querySelectorAll("#nav a, .side-foot a[data-section]")].filter((a) => !a.hidden).map((a) => a.dataset.section);

  function paletteItems() {
    const items = [];
    const tools = data.state?.status.tools || [];
    const icons = { overview: "home", limits: "limits" };
    for (const section of SECTIONS) {
      if (section === "accounts" || !sectionShown(section)) continue;
      const place = shownSections().indexOf(section);
      const group = groupOf(section);
      items.push({ group: "Go to", label: TITLES[section], detail: group.sections.length > 1 ? group.title : "", icon: icons[section] || section, key: place >= 0 && place < 9 ? String(place + 1) : "", run: () => go(section) });
    }
    for (const [value, label] of RANGES) {
      if (isStatic && !data.usage[`${value}:all`]) continue;
      items.push({ group: "Usage over", label, run: () => showUsage({ range: value }) });
    }
    items.push({ group: "Usage for", label: "All tools", run: () => showUsage({ tool: "all" }) });
    if (!isStatic) for (const tool of tools) items.push({ group: "Usage for", label: tool.name, mark: tool.id, run: () => showUsage({ tool: tool.id }) });
    items.push({ group: "Usage in", label: "Tokens", run: () => showUsage({ metric: "tokens" }) });
    items.push({ group: "Usage in", label: "API value", run: () => showUsage({ metric: "cost" }) });
    if (!isStatic) {
      for (const tool of tools) {
        for (const account of tool.accounts.filter((a) => !a.active)) {
          items.push({ group: "Switch", label: account.name, detail: tool.name, mark: tool.id,
            run: () => act(null, () => api("/api/switch", { id: account.id }), "Switching") });
        }
      }
      items.push({ group: "Do", label: "Read limits and usage now", icon: "refresh", run: () => { if (!data.state?.refreshing) act(null, () => { data.state.refreshing = true; renderActivity(); return api("/api/refresh", {}); }); } });
      items.push({ group: "Do", label: "Check for updates", icon: "update", run: () => { ui.settingsPane = "app"; go("settings"); } });
      if (data.state?.cloud?.linked) items.push({ group: "Go to", label: "Today's work", icon: "teams", run: () => showDay() });
    }
    return items;
  }

  async function showUsage(change) {
    Object.assign(ui, change);
    if (ui.section !== "usage") { await go("usage"); return; }
    render();
    await loadSection();
    render();
  }

  if ($("#hop-key")) $("#hop-key").textContent = isMac ? "⌘K" : "Ctrl K";

  function openPalette() {
    palette = { query: "", index: 0 };
    drawPalette();
    $("#palette input")?.focus();
  }

  function closePalette() {
    palette = null;
    $("#palette").innerHTML = "";
    $("#palette").hidden = true;
  }

  function paletteMatches() {
    const words = palette.query.toLowerCase().split(/\s+/).filter(Boolean);
    return paletteItems().filter((item) => {
      const text = `${item.group} ${item.label} ${item.detail || ""}`.toLowerCase();
      return words.every((w) => text.includes(w));
    });
  }

  function drawPalette() {
    const host = $("#palette");
    const matches = paletteMatches();
    palette.index = Math.max(0, Math.min(palette.index, matches.length - 1));
    let group = "";
    const rows = matches.map((item, i) => {
      const head = item.group !== group ? `<div class="palette-group">${esc((group = item.group))}</div>` : "";
      const glyph = item.mark ? mark(item.mark) : item.icon ? `<svg class="icon"><use href="#i-${item.icon}"/></svg>` : `<span class="palette-dot"></span>`;
      return `${head}<button type="button" class="palette-item" role="option" data-palette="${i}" aria-selected="${i === palette.index}">${glyph}<span>${esc(item.label)}</span>${item.detail ? `<small>${esc(item.detail)}</small>` : ""}${item.key ? `<kbd>${item.key}</kbd>` : ""}</button>`;
    }).join("");
    const list = rows || `<p class="palette-empty">Nothing matches "${esc(palette.query)}".</p>`;
    if (!host.firstElementChild) {
      host.hidden = false;
      host.innerHTML = `<div class="palette-scrim" data-palette-close></div>
        <div class="palette" role="dialog" aria-modal="true" aria-label="Hop">
          <label class="palette-search"><svg class="icon"><use href="#i-hop"/></svg><input type="text" name="hop-search" autocomplete="off" spellcheck="false" placeholder="Search sections, ranges, tools, or accounts…" aria-label="Search Hop"></label>
          <div class="palette-list" role="listbox"></div>
          <div class="palette-foot"><span><kbd>↑</kbd><kbd>↓</kbd> move</span><span><kbd>↵</kbd> open</span><span><kbd>esc</kbd> close</span></div>
        </div>`;
    }
    host.querySelector(".palette-list").innerHTML = list;
    host.querySelector('[aria-selected="true"]')?.scrollIntoView({ block: "nearest" });
  }

  function runPalette(index) {
    const item = paletteMatches()[index];
    closePalette();
    if (item) item.run();
  }

  let linkPoll = null;

  function render() {
    if (data.state) applyTheme();
    renderSidebar();
    if (!data.state) return;
    const tools = data.state.status.tools;
    const cloud = data.state.cloud;
    const cloudOn = !isStatic && !!cloud?.available;
    const linked = cloudOn && !!cloud.linked && !cloud.linking;
    const community = $('#nav a[data-group="community"]');
    if (community) community.hidden = !cloudOn;
    if (!sectionShown(ui.section)) ui.section = "overview";
    void linked;
    // While a link waits for approval in the browser, check every few seconds instead of every 20.
    if (cloud?.linking && !linkPoll) {
      linkPoll = setTimeout(async () => {
        linkPoll = null;
        try { await loadState(); if (data.state.cloud.linked) await loadSection(); } catch {}
        render();
      }, 3000);
    }
    const page = { overview: overviewPage, limits: limitsPage, accounts: limitsPage, usage: usagePage, budgets: budgetsPage, plans: plansPage, coach: coachPage, leaderboard: leaderboardPage, season: seasonPage, teams: teamsPage, profile: profilePage, settings: settingsPage }[ui.section](tools);
    $("#title").textContent = groupOf(ui.section).title;
    const subnav = $("#subnav");
    if (subnav) subnav.innerHTML = subnavHTML();
    const tabbed = !!subnav?.innerHTML;
    $("#toolbar").innerHTML = tabbed ? "" : page.toolbar || "";
    const pageTools = tabbed && page.toolbar ? `<div class="page-tools">${page.toolbar}</div>` : "";
    const offline = ui.offline ? `<div class="notice">${icon("alert")}<div><p>${esc(ui.offline)}</p></div></div>` : "";
    parkHero();
    $("#main").innerHTML = ui.section === "overview" ? `<div class="home">${offline}${page.body}</div>` : `<div class="page">${offline}${pageTools}${page.body}</div>`;
    placeHero();
    $("#main").setAttribute("aria-busy", (ui.loadingUsage || data.state.refreshing) ? "true" : "false");
    applyPending();
    renderActivity();
    animate();
  }

  // Home's wallpaper is one element that lives across renders, so the field and any scene keep
  // painting instead of starting over every time the page is drawn again.
  function parkHero() {
    const art = $("#hero-art");
    if (art && art.parentElement !== $("#content")) { art.hidden = true; $("#content").prepend(art); }
  }

  function placeHero() {
    const art = $("#hero-art"), slot = $("[data-hero]");
    if (!art || !slot) return;
    slot.replaceWith(art);
    art.hidden = false;
    requestAnimationFrame(paintField);
  }

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
    $("#read").textContent = label;
    $("#main")?.setAttribute("aria-busy", busyNow ? "true" : "false");
    for (const meter of [$("#foot-meter"), $("#top-meter")]) {
      if (!meter) continue;
      const known = step?.fraction != null;
      meter.classList.toggle("unknown", busyNow && !known);
      meter.firstElementChild.style.width = known ? `${(step.fraction * 100).toFixed(1)}%` : "";
      if (meter.id === "foot-meter") meter.hidden = !busyNow; else meter.classList.toggle("on", busyNow);
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
            if (!editing()) render(); else renderSidebar();
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

  function renderSidebar() {
    // A place remembers the section last open in it, so its link returns there.
    const here = groupOf(ui.section);
    ui.lastIn[here.id] = ui.section;
    for (const link of document.querySelectorAll("#nav a, .side-foot a[data-section]")) {
      const group = link.dataset.group;
      if (group) {
        const place = GROUPS.find((item) => item.id === group);
        const remembered = ui.lastIn[group];
        link.dataset.section = remembered && sectionShown(remembered) ? remembered : place.sections.find(sectionShown) || place.sections[0];
        link.href = "#" + link.dataset.section;
      }
      if ((group || link.dataset.section) === (group ? here.id : ui.section)) link.setAttribute("aria-current", "page"); else link.removeAttribute("aria-current");
    }
    const state = data.state;
    // A beta says so beside the name, the way a browser's Beta does.
    const channelBadge = $("#channel-badge");
    if (channelBadge) channelBadge.hidden = !String(state?.version || "").includes("-");
    const mode = $("#mode");
    if (mode) {
      mode.innerHTML = isStatic ? `<span class="badge">Saved</span>` : state?.mode === "sample" ? `<span class="badge sample">Sample</span>` : "";
      mode.hidden = !mode.textContent.trim();
    }
    const refresh = $("#refresh");
    if (refresh) {
      refresh.disabled = isStatic;
      refresh.classList.toggle("spin", !!state?.refreshing);
      refresh.setAttribute("aria-busy", state?.refreshing ? "true" : "false");
    }
    renderActivity();
    labelNav();
    slideNav();
    renderChrome();
  }

  function tabs(name, options, current, disabled = false) {
    return `<div class="tabs" role="group" data-tabs="${esc(name)}">${options.map(([value, label]) =>
      `<button type="button" data-action="${name}" data-value="${value}" aria-pressed="${value === current}" ${disabled ? "disabled" : ""}>${esc(label)}</button>`).join("")}</div>`;
  }

  // `grow`, when given, names the bar so it grows from its last length (see growBars).
  function progress(percent, pace, tone, grow) {
    const width = Math.min(100, Math.max(0, percent));
    // "plain" is for rankings, where a full bar means the largest, not a limit running out.
    const state = tone === "plain" ? "" : tone || (width >= 90 ? "bad" : pace != null && width > pace * 100 + 6 ? "warn" : "");
    return `<div class="progress ${state}"><span style="width:${width.toFixed(1)}%"${grow ? ` data-grow="${esc(ui.section + ":" + grow)}"` : ""}></span>${pace != null ? `<i style="left:${Math.min(100, pace * 100).toFixed(1)}%" title="Time passed"></i>` : ""}</div>`;
  }

  function limitFoot(limit) {
    if (limit.runsOutAt && new Date(limit.runsOutAt) > Date.now() && (!limit.resetsAt || new Date(limit.runsOutAt) < new Date(limit.resetsAt))) {
      return `Runs out ~${fmt.clock(limit.runsOutAt)}`;
    }
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

  function alternative(tool, current) {
    const pick = tool.accounts.filter((a) => !a.active && a.limits?.length).sort((a, b) => maxUsed(a) - maxUsed(b))[0];
    return pick && (!current || maxUsed(pick) + 15 < maxUsed(current)) ? pick : null;
  }

"""##
}
