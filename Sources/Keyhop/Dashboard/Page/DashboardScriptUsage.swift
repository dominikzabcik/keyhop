import Foundation

/// The Usage section: totals, breakdowns, the stacked chart, the heatmap and the tables.
extension DashboardPage {
    static let scriptUsage = ##"""
  // MARK: Usage

  function usagePage(tools) {
    const toolbar = rangePicker(data.usage[`${ui.range}:${ui.tool}`])
      + tabs("metric", [["tokens", "Tokens"], ["cost", "API value"]], ui.metric)
      + `<select class="field" data-action="tool" aria-label="Tool" ${isStatic ? "disabled" : ""}>${[["all", "All tools"], ...tools.map((t) => [t.id, t.name])].map(([v, l]) => `<option value="${v}" ${v === ui.tool ? "selected" : ""}>${esc(l)}</option>`).join("")}</select>`;
    const usage = data.usage[`${ui.range}:${ui.tool}`] || (isStatic ? data.usage[`${ui.range}:all`] : null);
    if (!usage) return { toolbar, body: `<div class="card">${loading("Reading usage", "empty")}</div>` };
    const stale = data.usageErrors[`${ui.range}:${ui.tool}`]
      ? `<div class="notice">${icon("alert")}<div><b>Showing the last complete reading</b><p>${esc(data.usageErrors[`${ui.range}:${ui.tool}`])}</p></div></div>` : "";

    const t = usage.total;
    const board = (main, side) => `<div class="usage-board"><div class="usage-side">${side}</div><div class="usage-main">${main}</div></div>`;
    if (!t.requests) {
      return { toolbar, body: `${stale}${board(`<div class="card"><p class="empty">No usage in this range. Keyhop reads Claude Code, Codex, Gemini CLI, OpenCode and Pi records on this computer, and Cursor's usage export after a refresh.</p></div>`, `${summaryCard(usage)}${heatCard(usage)}`)}` };
    }
    const grouped = chartGroup(usage);
    // The legend doubles as a filter: each entry hides or shows its part of every bar.
    const hidden = ui.hidden[ui.group] || [];
    const legend = `<ul class="legend">${grouped.series.map((s) => `<li><button type="button" class="legend-item" data-action="series" data-value="${esc(s.id)}" aria-pressed="${!hidden.includes(s.id)}" title="${hidden.includes(s.id) ? "Show" : "Hide"} ${esc(s.name)}"><span class="swatch" style="background:${s.color}"></span>${esc(s.name)}</button></li>`).join("")}</ul>`;
    const chart = `<section class="card">
      <div class="card-head"><h2>${ui.metric === "tokens" ? "Tokens" : "API value"} by ${usage.bucket}</h2>${tabs("group", [["account", "Accounts"], ["tool", "Tools"], ["model", "Models"]], ui.group)}</div>
      <div class="card-body chart-body">${legend}<div class="chart" style="view-transition-name:usage-chart">${stackedChart(usage, ui.metric, 260, "board", ui.group, hidden)}</div></div>
    </section>`;
    const mix = `<section class="card">
      <div class="card-head"><h2>Token mix</h2><span class="hint mono">${fmt.tokens(t.tokens)}</span></div>
      <div class="card-body">${mixBlock(t)}</div>
    </section>`;
    return { toolbar, body: `${stale}${board(`${totalCard(usage)}${chart}${mix}`, `${summaryCard(usage)}${heatCard(usage)}`)}${breakdownCard(usage)}` };
  }

  // The range's total, exact, set large; what it was worth; and how it splits across tools, or
  // across one tool's models once the page is narrowed to that tool.
  function totalCard(usage) {
    const t = usage.total, p = usage.previous;
    const tokens = ui.metric === "tokens";
    const exact = tokens ? fmt.count(t.tokens) : "$" + (t.cost || 0).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    const change = usage.compared === false ? "" : tokens ? fmt.change(t.tokens, p.tokens) : fmt.change(t.cost, p.cost);
    const inputSide = t.input + t.cacheRead + t.cacheWrite + (t.cacheWrite1h || 0);
    const facts = [
      tokens ? `${fmt.usd(t.cost)} at API prices` : `${fmt.tokens(t.tokens)} tokens`,
      `${fmt.count(t.requests)} requests`,
      inputSide ? `${Math.round((t.cacheRead / inputSide) * 100)}% from cache` : "",
      usage.cacheSavings > 0 ? `${fmt.usd(usage.cacheSavings)} saved by prompt caching` : "",
      t.billed > 0 ? `${fmt.usd(t.billed)} billed on demand` : "",
    ].filter(Boolean);
    const before = usage.compared === false
      ? `Since ${esc(fmt.day(usage.since || usage.start, { month: "short", day: "numeric", year: "numeric" }))}`
      : `vs ${tokens ? fmt.tokens(p.tokens) : fmt.usd(p.cost)} the period before`;

    const narrowed = ui.tool !== "all";
    const value = (x) => (tokens ? x.figures.tokens : x.figures.cost);
    const parts = narrowed
      ? usage.models.map((m) => ({ id: m.model, name: m.model, color: m.color, figures: m.figures, mono: true }))
      : (usage.tools || []).map((tool) => ({ id: tool.id, name: tool.name, color: tool.color, figures: tool.figures, tool: tool.id,
          models: usage.models.filter((m) => m.tool === tool.id).length }));
    parts.sort((a, b) => value(b) - value(a));
    // One tool's models share its colour, so each steps a shade lighter by rank to stay apart.
    if (narrowed) parts.forEach((x, i) => { x.color = shade(x.color, Math.min(0.6, i * 0.2)); });
    const sum = parts.reduce((s, x) => s + value(x), 0) || 1;
    const share = (x) => (value(x) / sum) * 100;
    const pct = (x) => { const v = share(x); return v > 0 && v < 1 ? "<1%" : `${Math.round(v)}%`; };
    const show = (x) => (tokens ? fmt.tokens(x.figures.tokens) : fmt.usd(x.figures.cost));
    const tipFor = (x) => tipAttr(x.name, [["Share", pct(x)], [tokens ? "Tokens" : "API value", show(x)], ["Requests", fmt.count(x.figures.requests)]]);
    const scope = `${ui.tool}:${ui.metric}`;
    const bar = `<div class="share-bar" role="img" aria-label="Share of ${tokens ? "tokens" : "API value"}">${parts.filter((x) => share(x) >= 0.4)
      .map((x) => `<span style="flex-grow:${share(x).toFixed(3)};background:${x.color}" data-grow="share:${esc(scope)}:${esc(x.id)}" data-grow-prop="flexGrow"${tipFor(x)}></span>`).join("")}</div>`;
    // Each part's line across the range, from the same buckets the chart draws.
    const buckets = narrowed ? usage.modelBuckets || [] : usage.toolBuckets || [];
    const trend = (x) => sparkline(buckets.map((b) => { const v = b.values[narrowed ? `${ui.tool}:${x.id}` : x.id]; return v ? (tokens ? v.tokens : v.cost) : 0; }), x.color, usage.bucket === "day" && buckets.length >= 21 ? 7 : 0);
    const tiles = parts.map((x) => {
      const inner = `<span class="tile-name">${x.tool ? mark(x.tool) : ""}<span class="${x.mono ? "mono" : ""}">${esc(x.name)}</span></span>
        <span class="tile-mid"><span class="tile-share" data-count="${share(x).toFixed(2)}" data-count-key="tile:${esc(scope)}:${esc(x.id)}" data-format="pct">${pct(x)}</span>${trend(x)}</span>
        <span class="tile-foot"><span class="swatch" style="background:${x.color}"></span>${show(x)}${x.models ? ` · ${x.models} ${x.models === 1 ? "model" : "models"}` : ""}</span>`;
      return x.tool && !isStatic
        ? `<button type="button" class="tile" data-action="filter-tool" data-value="${esc(x.tool)}" aria-label="Show only ${esc(x.name)}"${tipFor(x)}>${inner}</button>`
        : `<div class="tile"${tipFor(x)}>${inner}</div>`;
    }).join("");
    const title = `${tokens ? "Tokens" : "API value"}, ${esc((usage.title || "").toLowerCase() === "today" ? "today" : usage.title)}${narrowed ? ` · ${esc(toolName(ui.tool))}` : ""}`;
    return `<section class="card total-card">
      <div class="total-head"><span>${title}</span>${narrowed && !isStatic ? `<button type="button" class="btn sm ghost" data-action="filter-tool" data-value="all">All tools</button>` : `<span class="total-change">${change}<span class="subtle">${before}</span></span>`}</div>
      <div class="total-figure" data-count="${tokens ? t.tokens : (t.cost || 0).toFixed(2)}" data-count-key="total:${esc(ui.metric)}" data-format="${tokens ? "count" : "usdExact"}" data-count-intro>${exact}</div>
      <p class="total-facts">${facts.map(esc).join(" · ")}</p>
      ${parts.length ? bar : ""}
      <div class="tiles">${tiles}</div>
    </section>`;
  }

  // A hex colour mixed toward white by `amount` (0 to 1).
  function shade(hex, amount) {
    const m = /^#?([0-9a-f]{6})$/i.exec(hex || "");
    if (!m || !amount) return hex;
    const n = parseInt(m[1], 16), mix = (c) => Math.round(c + (255 - c) * amount);
    return `rgb(${mix(n >> 16)}, ${mix((n >> 8) & 255)}, ${mix(n & 255)})`;
  }

  // Quick figures from the daily record, whatever range is shown, and the models that carried it.
  function summaryCard(usage) {
    const days = usage.heatmap || [];
    const today = localDay(new Date());
    const upto = days.filter((d) => d.day <= today);
    const lastN = (n) => upto.slice(-n).reduce((s, d) => s + (ui.metric === "tokens" ? d.tokens : d.cost), 0);
    const active = upto.filter((d) => d.tokens > 0);
    const perDay = active.length ? active.reduce((s, d) => s + (ui.metric === "tokens" ? d.tokens : d.cost), 0) / active.length : 0;
    const show = (v) => (ui.metric === "tokens" ? fmt.tokens(v) : fmt.usd(v));
    const chips = [["Today", lastN(1)], ["7 days", lastN(7)], ["30 days", lastN(30)], ["Per active day", perDay]]
      .map(([label, v]) => `<div class="chip"><b data-count="${v}" data-count-key="chip:${label}:${ui.tool}:${ui.metric}" data-format="${ui.metric === "tokens" ? "tokens" : "usd"}" data-count-intro>${show(v)}</b><span>${label}</span></div>`).join("");
    const value = (m) => (ui.metric === "tokens" ? m.figures.tokens : m.figures.cost);
    const models = usage.models.slice().sort((a, b) => value(b) - value(a));
    const sum = models.reduce((s, m) => s + value(m), 0) || 1;
    const s = usage.streak;
    return `<section class="card summary-card">
      <div class="chips">${chips}</div>
      ${models.length ? rankedList(`summary:${ui.tool}:${ui.metric}`, models.slice(0, 5), (m) => value(m) / sum, (m) => `${m.tool ? mark(m.tool) : ""}<span class="mono">${esc(m.model)}</span>`) : `<p class="empty-inline subtle">No models in this range.</p>`}
      <div class="summary-foot"><span>${fmt.count(s.activeDays)} active days in 26 weeks</span><span>${s.current ? `${s.current}-day streak` : "No streak running"}</span></div>
    </section>`;
  }

  // A ranked list: place, name, share, and a track filled to that share.
  function rankedList(key, items, shareOf, nameOf) {
    return `<ol class="ranked">${items.map((item, i) => {
      const share = Math.max(0, Math.min(1, shareOf(item)));
      const pct = share > 0 && share < 0.01 ? "<1%" : `${Math.round(share * 100)}%`;
      return `<li><span class="place">${i + 1}</span><span class="ranked-name">${nameOf(item)}</span><span class="ranked-share">${pct}</span>
        <span class="ranked-track"><span style="width:${(share * 100).toFixed(1)}%" data-grow="${esc(key)}:${i}"></span></span></li>`;
    }).join("")}</ol>`;
  }

  // Everything under the chart, one table at a time.
  function breakdownCard(usage) {
    const step = { hour: "Hours", day: "Days", week: "Weeks", month: "Months" }[usage.bucket] || "Days";
    const placed = (usage.projects || []).filter((p) => p.path);
    const views = [["periods", step], ["models", "Models"], ["makers", "Makers"], ["projects", "Projects"], ["accounts", "Accounts"], ["sessions", "Sessions"]]
      .filter(([id]) => id !== "projects" || placed.length)
      .filter(([id]) => id !== "sessions" || (usage.sessions || []).length)
      .filter(([id]) => id !== "makers" || (usage.makers || []).length);
    const view = views.some(([id]) => id === ui.breakdown) ? ui.breakdown : "periods";
    const body = view === "models" ? rankedModelTable(usage.models, ui.metric)
      : view === "makers" ? makerTable(usage.makers, ui.metric)
      : view === "projects" ? projectTable(usage.projects, ui.metric)
      : view === "accounts" ? accountTable(usage.accounts, ui.metric)
      : view === "sessions" ? sessionTable(usage.sessions, ui.metric)
      : periodTable(usage);
    return `<section class="card">
      <div class="card-head">${tabs("breakdown", views, view)}${isStatic ? "" : `<button class="btn sm ghost" data-action="export-csv">Download CSV</button>`}</div>
      <div class="table-wrap">${body}</div>
    </section>`;
  }

  // Each period with usage, newest first, in full: a number here is to be read, not glanced at.
  function periodTable(usage) {
    const rows = usage.periods || [];
    if (!rows.length) return `<p class="empty">Nothing in this range.</p>`;
    const shown = ui.allPeriods ? rows : rows.slice(0, 14);
    const when = (start) => usage.bucket === "hour" ? fmt.day(start, { weekday: "short", hour: "2-digit", minute: "2-digit" })
      : usage.bucket === "week" ? `Week of ${fmt.day(start, { month: "short", day: "numeric", year: "numeric" })}`
      : usage.bucket === "month" ? fmt.day(start, { month: "long", year: "numeric" })
      : fmt.day(start, { weekday: "short", month: "short", day: "numeric" });
    const n = (v) => `<td class="right mono">${fmt.count(v)}</td>`;
    const body = shown.map((r) => { const f = r.figures; return `<tr>
      <td class="nowrap">${esc(when(r.start))}</td>
      <td class="right mono strong">${fmt.count(f.tokens)}</td>${n(f.input)}${n(f.output)}${n(f.cacheRead)}${n(f.cacheWrite + (f.cacheWrite1h || 0))}${n(f.requests)}
      <td class="right mono">${fmt.usd(f.cost)}</td>
    </tr>`; }).join("");
    const more = rows.length > shown.length
      ? `<div class="table-more"><button type="button" class="btn sm ghost" data-action="all-periods">Show all ${rows.length}</button></div>` : "";
    return `<table class="table data"><thead><tr><th>${{ hour: "Hour", day: "Day", week: "Week", month: "Month" }[usage.bucket] || "Day"}</th><th class="right">Total</th><th class="right">Input</th><th class="right">Output</th><th class="right">Cache read</th><th class="right">Cache write</th><th class="right">Requests</th><th class="right">API value</th></tr></thead><tbody>${body}</tbody></table>${more}`;
  }

  // Every model in one ranking, whichever tool ran it.
  function rankedModelTable(models, metric) {
    const value = (m) => (metric === "tokens" ? m.figures.tokens : m.figures.cost);
    const sorted = models.slice().sort((a, b) => value(b) - value(a));
    const sum = sorted.reduce((s, m) => s + value(m), 0) || 1;
    const peak = Math.max(0.000001, ...sorted.map(value));
    const rows = sorted.map((m, i) => `<tr${isStatic ? "" : ` class="clickable" data-action="filter-tool" data-value="${esc(m.tool || "")}"`}>
      <td class="place-cell mono subtle">${i + 1}</td>
      <td><div class="cell-name">${mark(m.tool)}<span class="mono">${esc(m.model)}</span></div></td>
      <td class="bar-cell">${progress((value(m) / peak) * 100, null, "plain", `row:${ui.tool}:${metric}:${m.tool || ""}:${m.model || m.name}`)}</td>
      <td class="right mono">${metric === "tokens" ? fmt.tokens(m.figures.tokens) : fmt.usd(m.figures.cost)}</td>
      <td class="right mono subtle">${Math.round((value(m) / sum) * 100)}%</td>
    </tr>`).join("");
    return `<table class="table"><thead><tr><th></th><th>Model</th><th></th><th class="right">${metric === "tokens" ? "Tokens" : "API value"}</th><th class="right">Share</th></tr></thead><tbody>${rows}</tbody></table>`;
  }

  // One button for the range, opening the fixed ranges and a pair of dates. Tabs for seven ranges
  // plus dates would crowd everything else out of the toolbar.
  const RANGES = [["today", "Today"], ["week", "7 days"], ["month", "This month"], ["30d", "30 days"], ["90d", "90 days"], ["12m", "12 months"], ["all", "All time"]];
  const localDay = (date) => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
  function rangePicker(usage) {
    const preset = RANGES.find(([value]) => value === ui.range);
    const label = preset ? preset[1] : usage?.title || "Chosen dates";
    const today = localDay(new Date());
    const [from, to] = ui.range.includes("..") ? ui.range.split("..") : [usage ? localDay(new Date(usage.start)) : today, today];
    const offered = RANGES.filter(([value]) => !isStatic || data.usage[`${value}:all`]);
    const menu = ui.rangeOpen ? `<div class="range-menu">
      <div class="range-list" role="group" aria-label="Range">${offered.map(([value, name]) => `<button type="button" data-action="range" data-value="${value}" aria-checked="${value === ui.range}" role="menuitemradio">${esc(name)}</button>`).join("")}</div>
      ${isStatic ? "" : `<form class="range-dates" data-form="range">
        <label>From<input class="field" type="date" name="from" value="${esc(from)}" max="${today}" required></label>
        <label>To<input class="field" type="date" name="to" value="${esc(to)}" max="${today}" required></label>
        <button class="btn sm secondary">Show these days</button>
      </form>`}
    </div>` : "";
    return `<div class="range-pick"><button type="button" class="range-button" data-action="range-menu" aria-haspopup="true" aria-expanded="${ui.rangeOpen}">${esc(label)}<svg viewBox="0 0 10 10" aria-hidden="true"><path d="M2 3.6 5 6.6 8 3.6" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg></button>${menu}</div>`;
  }

  function niceCeiling(value) {
    if (value <= 0) return 1;
    const magnitude = Math.pow(10, Math.floor(Math.log10(value)));
    for (const step of [1, 2, 2.5, 5, 10]) if (step * magnitude >= value) return step * magnitude;
    return 10 * magnitude;
  }

  /// Drawn at the width it's shown at, so text stays its intended size.
  function chartWidth(size) {
    const page = Math.min(1320, ($("#main")?.clientWidth || 1200) - 48);
    const columns = matchMedia("(max-width: 1180px)").matches ? 1 : 2;
    const gap = 12;
    const side = columns === 2 ? Math.round(page * 0.34) : page;
    const board = columns === 2 ? page - gap - side : page;
    const half = columns === 2 ? (page - 16) / 2 : page;
    const widths = { full: page, half, wide: columns === 2 ? (page - 16) * 0.608 : page, narrow: columns === 2 ? (page - 16) * 0.392 : page, side, board };
    // Card padding and borders, with a little room so rounding never adds a scrollbar.
    const raw = Math.floor((widths[size] || page) - 40);
    return Math.max(size === "side" ? 220 : 420, raw);
  }

  function roundedTop(x, y, w, h) {
    const r = Math.min(3, h, w / 2);
    return `M${x},${y + h}V${y + r}Q${x},${y} ${x + r},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + h}Z`;
  }

  function stackedChart(usage, metric, height, size, group, hidden = []) {
    const grouped = chartGroup(usage, group);
    const series = grouped.series.filter((s) => !hidden.includes(s.id)), buckets = grouped.buckets;
    const W = chartWidth(size), H = height, L = 52, R = 4, T = 8, B = 26;
    const pw = W - L - R, ph = H - T - B;
    const pick = (v) => (v ? (metric === "tokens" ? v.tokens : v.cost) : 0);
    const columns = buckets.map((b) => series.map((s) => pick(b.values[s.id])));
    const ceiling = niceCeiling(Math.max(0, ...columns.map((c) => c.reduce((a, b) => a + b, 0))));
    const slot = pw / Math.max(1, buckets.length);
    const bw = Math.max(3, Math.min(slot * 0.58, 30));
    const label = (v) => (metric === "tokens" ? fmt.tokens(v) : v === 0 ? "$0" : v < 10 ? "$" + v.toFixed(2) : fmt.usd(v));
    // As many labels as fit at about 64px each, on a step that reads naturally for hours.
    const fits = Math.max(2, Math.floor(pw / 64));
    const every = Math.max(usage.bucket === "hour" ? 3 : 1, Math.ceil(buckets.length / fits));
    const spansYears = buckets.length > 1 && new Date(buckets[0].start).getFullYear() !== new Date(buckets[buckets.length - 1].start).getFullYear();
    const axisOptions = usage.bucket === "hour" ? { hour: "2-digit" }
      : usage.bucket === "month" ? (spansYears ? { month: "short", year: "2-digit" } : { month: "short" })
      : usage.bucket === "week" || buckets.length > 10 ? { month: "short", day: "numeric" }
      : { weekday: "short" };
    let grid = "", bars = "", hits = "";
    for (let i = 0; i <= 4; i++) {
      const value = (ceiling / 4) * i, y = (T + ph - (value / ceiling) * ph).toFixed(1);
      grid += `<line class="${i ? "grid" : "base"}" x1="${L}" x2="${W - R}" y1="${y}" y2="${y}"/><text class="axis" x="${L - 8}" y="${y}" text-anchor="end" dominant-baseline="central">${label(value)}</text>`;
    }
    buckets.forEach((bucket, i) => {
      const cx = L + slot * (i + 0.5), x = cx - bw / 2;
      const present = series.map((s, j) => ({ s, v: columns[i][j] })).filter((e) => e.v > 0);
      let base = 0;
      bars += `<g class="col" data-col="${i}">`;
      present.forEach((entry, k) => {
        const y0 = T + ph - (base / ceiling) * ph, y1 = T + ph - ((base + entry.v) / ceiling) * ph;
        base += entry.v;
        const gap = k ? Math.min(1.5, (y0 - y1) / 2) : 0;
        const h = y0 - gap - y1;
        if (h < 0.3) return;
        bars += k === present.length - 1
          ? `<path d="${roundedTop(+x.toFixed(1), +y1.toFixed(1), +bw.toFixed(1), +h.toFixed(1))}" fill="${entry.s.color}"/>`
          : `<rect x="${x.toFixed(1)}" y="${y1.toFixed(1)}" width="${bw.toFixed(1)}" height="${h.toFixed(1)}" fill="${entry.s.color}"/>`;
      });
      bars += `</g>`;
      if (i % every === 0) {
        grid += `<text class="axis" x="${cx.toFixed(1)}" y="${H - 7}" text-anchor="middle">${esc(fmt.day(bucket.start, axisOptions))}</text>`;
      }
      hits += `<rect class="hit" x="${(L + slot * i).toFixed(1)}" y="${T}" width="${slot.toFixed(1)}" height="${ph}" data-bucket="${i}" data-metric="${metric}" data-group="${group || "account"}" data-key="${usage.range}:${usage.tool}"/>`;
    });
    return `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="${metric === "tokens" ? "Tokens" : "API value"} by ${usage.bucket}">${grid}<g>${bars}</g>${hits}</svg>`;
  }

  function chartGroup(usage, group) {
    const which = group || ui.group || "account";
    if (which === "tool" && usage.toolSeries && usage.toolBuckets) return { series: usage.toolSeries, buckets: usage.toolBuckets };
    if (which === "model" && usage.modelSeries && usage.modelBuckets) return { series: usage.modelSeries, buckets: usage.modelBuckets };
    return { series: usage.series, buckets: usage.buckets };
  }

  function heatCard(usage) {
    const s = usage.streak;
    return `<section class="card">
      <div class="card-head"><h2>Activity</h2><span class="scale">Less <i style="background:hsl(var(--on) / .05)"></i><i style="background:hsl(var(--on) / .18)"></i><i style="background:hsl(var(--on) / .36)"></i><i style="background:hsl(var(--on) / .6)"></i><i style="background:hsl(var(--on) / .9)"></i> More</span></div>
      <div class="card-body chart">${heatmap(usage.heatmap)}</div>
      <div class="facts">
        <div><b>${s.current}</b><span>day streak</span></div>
        <div><b>${s.longest}</b><span>longest streak</span></div>
        <div><b>${s.activeDays}</b><span>active days, 26 weeks</span></div>
      </div>
    </section>`;
  }

  function heatmap(days) {
    if (!days.length) return "";
    const parse = (day) => new Date(day + "T00:00:00");
    const offset = (parse(days[0].day).getDay() + 6) % 7;
    const columns = Math.ceil((days.length + offset) / 7);
    const gap = 3, top = 18;
    const size = Math.max(9, Math.min(16, Math.floor((chartWidth("side") - (columns - 1) * gap) / columns)));
    const active = days.map((d) => d.tokens).filter((v) => v > 0).sort((a, b) => a - b);
    const quartile = (q) => (active.length ? active[Math.min(active.length - 1, Math.floor(q * active.length))] : 0);
    const cuts = [quartile(0.25), quartile(0.5), quartile(0.75)];
    let cells = "", lastMonth = -1;
    const labels = [];
    days.forEach((day, i) => {
      const slot = i + offset, col = Math.floor(slot / 7), row = slot % 7;
      const level = !day.tokens ? 0 : day.tokens <= cuts[0] ? 1 : day.tokens <= cuts[1] ? 2 : day.tokens <= cuts[2] ? 3 : 4;
      const date = parse(day.day);
      if (row === 0 && date.getMonth() !== lastMonth && col < columns - 2) {
        labels.push({ col, text: fmt.day(date, { month: "short" }) });
        lastMonth = date.getMonth();
      }
      cells += `<rect class="l${level}" x="${col * (size + gap)}" y="${top + row * (size + gap)}" width="${size}" height="${size}" rx="2.5"${day.tokens && !isStatic && ui.section === "usage" ? ` data-action="day" data-value="${day.day}"` : ""}${tipAttr(fmt.day(date, { weekday: "short", month: "short", day: "numeric" }), day.tokens ? [["Tokens", fmt.tokens(day.tokens)], ["API value", fmt.usd(day.cost)], ["Requests", fmt.count(day.requests)]] : [["No usage", ""]])}/>`;
    });
    // A month that starts a column or two before the next one has no room for its name; the
    // next month's name wins rather than the two running into each other.
    const months = labels.filter((label, i) => !labels[i + 1] || labels[i + 1].col - label.col >= 3)
      .map((label) => `<text x="${label.col * (size + gap)}" y="11">${esc(label.text)}</text>`).join("");
    const width = columns * (size + gap) - gap, height = top + 7 * (size + gap) - gap;
    return `<svg class="heat" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" role="img" aria-label="Daily activity over 26 weeks">${months}${cells}</svg>`;
  }

  function mixBlock(t) {
    const parts = [
      ["Input", t.input, "m1"],
      ["Output", t.output, "m2"],
      ["Cache reads", t.cacheRead, "m3"],
      ["Cache writes", t.cacheWrite, "m4"],
      ["1h cache writes", t.cacheWrite1h || 0, "m5"],
    ];
    const sum = parts.reduce((s, p) => s + p[1], 0) || 1;
    const rows = parts.filter((p) => p[1] > 0 || p[0] !== "1h cache writes");
    const reasoning = t.reasoning
      ? `<p class="subtle" style="margin:10px 0 0;font-size:12px">Reasoning is ${fmt.tokens(t.reasoning)} of output, counted once.</p>`
      : "";
    return `<div class="mix-bar">${rows.filter((p) => p[1] > 0).map((p) => `<span class="${p[2]}" style="width:${((p[1] / sum) * 100).toFixed(2)}%" data-grow="mix:${esc(ui.tool)}:${p[2]}"${tipAttr(p[0], [["Tokens", fmt.tokens(p[1])], ["Share", `${Math.round((p[1] / sum) * 100)}%`]])}></span>`).join("")}</div>
      <table class="table" style="margin:0 -16px -16px;width:calc(100% + 32px)"><tbody>${rows.map((p) => `<tr><td><div class="cell-name"><span class="swatch ${p[2]}"></span><span>${p[0]}</span></div></td><td class="right mono">${fmt.tokens(p[1])}</td><td class="right mono subtle">${Math.round((p[1] / sum) * 100)}%</td></tr>`).join("")}</tbody></table>${reasoning}`;
  }


  // Whose models did the work, whichever tool ran them, with each maker's share of the range.
  function makerTable(makers, metric) {
    const value = (m) => (metric === "tokens" ? m.figures.tokens : m.figures.cost);
    const sum = makers.reduce((s, m) => s + value(m), 0) || 1;
    const peak = Math.max(0.000001, ...makers.map(value));
    const rows = makers.slice().sort((a, b) => value(b) - value(a)).map((m) => `<tr>
      <td><b>${esc(m.name)}</b><div class="subtle" style="font-size:11.5px" title="${esc(m.models.join(", "))}">${m.models.length} model${m.models.length === 1 ? "" : "s"}</div></td>
      <td class="bar-cell">${progress((value(m) / peak) * 100, null, "plain", `row:${ui.tool}:${metric}:${m.tool || ""}:${m.model || m.name}`)}</td>
      <td class="right mono">${metric === "tokens" ? fmt.tokens(m.figures.tokens) : fmt.usd(m.figures.cost)}</td>
      <td class="right mono subtle">${Math.round((value(m) / sum) * 100)}%</td>
    </tr>`).join("");
    return `<table class="table"><thead><tr><th>Maker</th><th></th><th class="right">${metric === "tokens" ? "Tokens" : "API value"}</th><th class="right">Share</th></tr></thead><tbody>${rows}</tbody></table>`;
  }

  // Each repository or folder, most used first. Usage no tool placed in a folder closes the list
  // and says so, rather than being left out and making the rows add up to less than the total.
  function projectTable(projects, metric) {
    const value = (p) => (metric === "tokens" ? p.figures.tokens : p.figures.cost);
    const peak = Math.max(0.000001, ...projects.map(value));
    const shown = projects.slice(0, 12);
    const rows = shown.map((p) => `<tr>
      <td>${p.path ? `<b>${esc(p.name)}</b><div class="subtle mono" style="font-size:11px">${esc(p.path)}</div>` : `<span class="subtle">${esc(p.name)}</span>`}</td>
      <td class="bar-cell">${progress((value(p) / peak) * 100, null, "plain", `project:${ui.tool}:${metric}:${p.path || ""}`)}</td>
      <td class="right mono">${metric === "tokens" ? fmt.tokens(p.figures.tokens) : fmt.usd(p.figures.cost)}</td>
    </tr>`).join("");
    const more = projects.length > shown.length ? `<p class="empty-inline" style="padding:10px 16px">and ${projects.length - shown.length} more</p>` : "";
    return `<table class="table"><thead><tr><th>Project</th><th></th><th class="right">${metric === "tokens" ? "Tokens" : "API value"}</th></tr></thead><tbody>${rows}</tbody></table>${more}`;
  }


  function sessionTable(sessions, metric) {
    const rows = sessions.map((s) => `<tr>
      <td><div class="cell-name">${mark(s.tool)}<span>${esc(toolName(s.tool))}</span></div><div class="subtle" style="font-size:12px;margin-left:26px">${esc(s.account)}</div></td>
      <td><span class="mono">${esc(s.model)}</span></td>
      <td class="subtle">${esc(fmt.clock(s.from))} to ${esc(fmt.clock(s.to))}</td>
      <td class="right mono">${metric === "tokens" ? fmt.tokens(s.figures.tokens) : fmt.usd(s.figures.cost)}</td>
    </tr>`).join("");
    return `<table class="table"><thead><tr><th>Session</th><th>Model</th><th>When</th><th class="right">${metric === "tokens" ? "Tokens" : "API value"}</th></tr></thead><tbody>${rows}</tbody></table>`;
  }

  function exportCSV(usage) {
    const cell = (v) => `"${String(v ?? "").replace(/"/g, '""')}"`;
    const lines = [["Kind", "Name", "Tool", "Tokens", "API value", "Requests", "Input", "Output", "Cache read", "Cache write"].map(cell).join(",")];
    (usage.periods || []).slice().reverse().forEach((r) => { const f = r.figures; lines.push([usage.bucket[0].toUpperCase() + usage.bucket.slice(1), new Date(r.start).toISOString(), usage.tool, f.tokens, f.cost.toFixed(4), f.requests, f.input, f.output, f.cacheRead, f.cacheWrite + (f.cacheWrite1h || 0)].map(cell).join(",")); });
    (usage.tools || []).forEach((t) => lines.push(["Tool", t.name, t.id, t.figures.tokens, t.figures.cost.toFixed(4), t.figures.requests].map(cell).join(",")));
    (usage.models || []).forEach((m) => lines.push(["Model", m.model, m.tool || "", m.figures.tokens, m.figures.cost.toFixed(4), m.figures.requests].map(cell).join(",")));
    (usage.accounts || []).forEach((a) => lines.push(["Account", a.name, a.tool, a.figures.tokens, a.figures.cost.toFixed(4), a.figures.requests].map(cell).join(",")));
    (usage.sessions || []).forEach((s) => lines.push(["Session", s.model, s.tool, s.figures.tokens, s.figures.cost.toFixed(4), s.figures.requests].map(cell).join(",")));
    const blob = new Blob([lines.join("\n")], { type: "text/csv" });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `keyhop-usage-${usage.range}.csv`;
    link.click();
    URL.revokeObjectURL(link.href);
    toast(`Saved keyhop-usage-${usage.range}.csv`);
  }

  function accountTable(accounts, metric) {
    const value = (a) => (metric === "tokens" ? a.figures.tokens : a.figures.cost);
    const sorted = accounts.slice().sort((a, b) => value(b) - value(a));
    const rows = sorted.map((a) => `<tr>
      <td><div class="cell-name"><span class="swatch" style="background:${a.color}"></span><span>${esc(a.name)}</span></div><div class="subtle" style="font-size:12px;margin-left:16px">${esc(toolName(a.tool))}${a.active ? " · in use" : ""}</div></td>
      <td class="right mono">${metric === "tokens" ? fmt.tokens(a.figures.tokens) : fmt.usd(a.figures.cost)}</td>
    </tr>`).join("");
    return `<table class="table"><thead><tr><th>Account</th><th class="right">${metric === "tokens" ? "Tokens" : "API value"}</th></tr></thead><tbody>${rows}</tbody></table>`;
  }

"""##
}
