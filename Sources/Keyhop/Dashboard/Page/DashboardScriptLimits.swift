import Foundation

/// Limits: what the logins have left and how it went, then every saved login, grouped by tool, with
/// what each window has used and when it resets. Only what the tools reported; no guesses about
/// when a limit will run out.
extension DashboardPage {
    static let scriptLimits = ##"""
  // MARK: Limits

  function limitsPage(tools) {
    const adding = (id) => (data.state.adding || []).includes(id);
    const kept = tools.filter((tool) => tool.accounts.length || adding(tool.id));
    const total = kept.reduce((sum, tool) => sum + tool.accounts.length, 0);
    if (ui.quotaTool !== "all" && !kept.some((tool) => tool.id === ui.quotaTool)) ui.quotaTool = "all";
    const toolTabs = [["all", "All", total], ...kept.map((tool) => [tool.id, tool.name, tool.accounts.length])];
    const toolbar = kept.length > 1 ? `<div class="tabs lim-tabs" role="group" aria-label="Show tool" data-tabs="quota-tool">${toolTabs.map(([id, name, n]) =>
      `<button type="button" data-action="quota-tool" data-value="${esc(id)}" aria-pressed="${id === ui.quotaTool}">${id === "all" ? "" : mark(id)}<span>${esc(name)}</span><span class="n">${n}</span></button>`).join("")}</div>` : "";
    const shown = ui.quotaTool === "all" ? kept : kept.filter((tool) => tool.id === ui.quotaTool);
    // Tools that only count tokens have no limit to show; Usage has them.
    const measured = shown.filter((tool) => !adding(tool.id) && tool.accounts.length && tool.accounts.every((a) => !a.error && !a.limits?.length));
    const withLimits = shown.filter((tool) => !measured.includes(tool));
    const stuck = (tool) => { const active = tool.accounts.find((a) => a.active); return active && laneOf(active) === "needs" ? 1 : 0; };
    withLimits.sort((a, b) => stuck(b) - stuck(a));
    const groups = withLimits.map((tool) => loginGroup(tool, adding(tool.id))).join("");
    const note = measured.length
      ? `<p class="lim-foot">${esc(nameList(measured.map((tool) => tool.name)))} ${measured.length === 1 ? "has" : "have"} no limit to read. ${measured.length === 1 ? "It is" : "They are"} counted in Usage.</p>` : "";
    const unset = ui.quotaTool === "all" ? setupCard(tools.filter((tool) => !tool.accounts.length && !adding(tool.id))) : "";
    const empty = !kept.length ? `<section class="card"><p class="empty">No saved logins yet. Add one below.</p></section>` : "";
    return { toolbar, body: `<div class="lim-page">${kept.length ? quotaCard() : ""}${empty}${groups}${note}${unset}</div>` };
  }

  // MARK: What is left, and how it went

  const QUOTA_SPANS = { 24: "24 hours", 168: "7 days" };
  const quotaPool = (tool = ui.quotaTool) => data.quota?.pools?.find((pool) => pool.tool === tool) || null;

  // "Tue 22:00", or just the time when it is today.
  function when(date) {
    const at = new Date(date);
    return at.toDateString() === new Date().toDateString() ? fmt.clock(at) : fmt.day(at, { weekday: "short", hour: "2-digit", minute: "2-digit" });
  }

  // The pooled figure beside the measured history: readings only, nothing projected.
  function quotaCard() {
    if (!data.quota) {
      if (isStatic) return "";
      if (data.quotaError) return `<div class="notice">${icon("alert")}<div><b>The history isn't available</b><p>${esc(data.quotaError)}</p></div></div>`;
      return `<div class="lim-top"><section class="card lim-total skel-card" style="min-height:300px"></section><section class="card qcard skel-card" style="min-height:300px"></section></div>`;
    }
    const pool = quotaPool();
    if (!pool || !pool.accounts) return "";
    const share = pool.capacity ? pool.remaining / pool.capacity : 0;
    const tone = share <= 0.15 ? "bad" : share <= 0.35 ? "warn" : "";
    const one = pool.accounts === 1;
    const scope = ui.quotaTool === "all" ? `${pool.accounts} login${one ? "" : "s"} with limits` : `${pool.accounts} ${esc(pool.name)} login${one ? "" : "s"}`;
    const drain = (pool.drain || []).filter((v) => v != null);
    const lastHour = drain.slice(-2).reduce((sum, v) => sum + v, 0) / Math.max(1, drain.slice(-2).length);
    const tools = (data.state?.status.tools || []).filter((tool) => ui.quotaTool === "all" || tool.id === ui.quotaTool);
    const logins = tools.flatMap((tool) => tool.accounts).filter((account) => account.limits?.length && !account.error);
    const roomy = logins.filter((account) => leftOf(account) >= 20).length;
    const figure = (name, value, sub, cls = "") => `<div class="lim-fig"><span class="lim-fig-name">${name}</span><b class="${cls}">${value}</b><span class="lim-fig-sub">${sub}</span></div>`;
    const figures = [
      figure("Last hour", lastHour >= 0.05 ? `${lastHour >= 10 ? Math.round(lastHour) : lastHour.toFixed(1)}% used` : "Nothing used", one ? "by this login" : "across the logins"),
      pool.nextReset
        ? figure("Next reset", `+${Math.round(pool.nextReset.gain)}%`, `at ${esc(when(pool.nextReset.at))} · ${esc(pool.nextReset.account)}`, "up")
        : figure("Next reset", "None soon", "no window resets this week"),
      figure("With room", `${roomy} of ${logins.length}`, "logins with 20% or more left", roomy ? "" : "bad"),
    ].join("");
    const summary = `<section class="card lim-total" aria-labelledby="lim-total-h">
      <span class="lim-total-title"><span class="lab">${scope}${one ? "" : ` · out of ${Math.round(pool.capacity)}%`}</span><h2 id="lim-total-h">What your logins have left</h2></span>
      <div class="lim-big ${tone}"><b data-count="${pool.remaining}" data-count-key="quota:${esc(pool.tool)}" data-format="pct">${Math.round(pool.remaining)}%</b><span>left${one ? "" : " across them all"}</span></div>
      ${one ? "" : `<p class="lim-note">Each login keeps its own limits. This adds up what each one has left, so 100% is one full login.</p>`}
      <div class="lim-figs">${figures}</div>
    </section>`;
    const hours = QUOTA_SPANS[ui.quotaHours] ? ui.quotaHours : 24;
    const legend = ui.quotaView === "drain" ? `<span><i class="bar"></i>Used per hour</span>` : `<span><i class="solid"></i>Left</span><span><i class="reset"></i>Reset</span>`;
    const history = `<section class="card qcard" aria-labelledby="lim-hist-h">
      <div class="lim-fore-head"><h2 id="lim-hist-h">The last ${esc(QUOTA_SPANS[hours])}</h2><span class="qlegend">${legend}</span></div>
      <div class="qchart chart">${ui.quotaView === "drain" ? drainChart(pool, hours) : leftChart(pool, hours)}</div>
      <div class="lim-fore-tools">${tabs("quota-hours", Object.entries(QUOTA_SPANS), String(hours))}${tabs("quota-view", [["left", "Left"], ["drain", "Used per hour"]], ui.quotaView)}</div>
    </section>`;
    return `<div class="lim-top">${summary}${history}</div>`;
  }

  // The history sits beside the summary, so its chart is drawn to that card's width.
  function historyWidth() {
    const main = Math.min(1480, ($("#main")?.clientWidth || 1200) - 56);
    const wide = !matchMedia("(max-width: 1020px)").matches;
    return Math.max(420, Math.floor((wide ? (main - 18) * 1.3 / 2.3 : main) - 54));
  }

  // A series as [time, value] points, from its first time and the report's step.
  function seriesPoints(start, values) {
    const t0 = new Date(start).getTime(), step = (data.quota.step || 1800) * 1000;
    return values.map((value, i) => [t0 + i * step, value]);
  }

  function timeAxis(from, to, x, H, B) {
    let labels = "";
    if ((to - from) / 3600_000 <= 48) {
      const every = 4 * 3600_000;
      // A label centred too close to the right edge would clip mid-word.
      for (let t = Math.ceil(from / every) * every; t <= to; t += every) {
        if (x(t) > x(to) - 30) continue;
        labels += `<text class="axis" x="${x(t).toFixed(1)}" y="${H - 7}" text-anchor="middle">${esc(fmt.clock(new Date(t)))}</text>`;
      }
    } else {
      const day = new Date(from); day.setHours(24, 0, 0, 0);
      for (let t = day.getTime(); t <= to; t += 86400_000) {
        const label = t + 43200_000 <= to ? `<text class="axis" x="${x(t + 43200_000).toFixed(1)}" y="${H - 7}" text-anchor="middle">${esc(fmt.day(t, { weekday: "short" }))}</text>` : "";
        labels += `<line class="grid day" x1="${x(t).toFixed(1)}" x2="${x(t).toFixed(1)}" y1="8" y2="${H - B}"/>${label}`;
      }
    }
    return labels;
  }

  // What was left at each reading, with a mark where a reset lifted it.
  function leftChart(pool, hours) {
    const W = historyWidth(), H = 240, L = 48, R = 14, T = 12, B = 26;
    const now = new Date(data.quota.forecastStart).getTime();
    const from = now - hours * 3600_000;
    const top = Math.max(100, pool.capacity);
    const x = (t) => L + ((t - from) / (now - from)) * (W - L - R);
    const y = (v) => T + (1 - Math.max(0, Math.min(top, v)) / top) * (H - T - B);
    const points = seriesPoints(data.quota.pastStart, pool.past).filter(([t, v]) => v != null && t >= from && t <= now);
    if (points.length < 2) return `<p class="empty">Keyhop draws this once it has read the limits for a while.</p>`;
    let grid = "";
    for (let i = 0; i <= 4; i++) {
      const value = (top / 4) * i, yy = y(value).toFixed(1);
      grid += `<line class="${i ? "grid" : "base"}" x1="${L}" x2="${W - R}" y1="${yy}" y2="${yy}"/><text class="axis" x="${L - 8}" y="${yy}" text-anchor="end" dominant-baseline="central">${Math.round(value)}%</text>`;
    }
    grid += timeAxis(from, now, x, H, B);
    const line = points.map(([t, v], i) => `${i ? "L" : "M"}${x(t).toFixed(1)},${y(v).toFixed(1)}`).join("");
    const area = `${line}L${x(points[points.length - 1][0]).toFixed(1)},${y(0).toFixed(1)}L${x(points[0][0]).toFixed(1)},${y(0).toFixed(1)}Z`;
    // Resets close together read as one, so only the first in any three hours is marked.
    let resets = "", lastReset = -Infinity;
    for (let i = 1; i < points.length; i++) {
      const gain = points[i][1] - points[i - 1][1];
      if (gain >= Math.max(10, top * 0.05) && points[i][0] - lastReset >= 3 * 3600_000) {
        lastReset = points[i][0];
        const rx = x(points[i][0]).toFixed(1);
        resets += `<line class="qreset" x1="${rx}" x2="${rx}" y1="${y(points[i - 1][1]).toFixed(1)}" y2="${y(points[i][1]).toFixed(1)}"/>`;
      }
    }
    // Hover strips, one per half hour by day or per two hours across a week, each with its reading.
    const strip = hours > 48 ? 2 * 3600_000 : 1800_000;
    let hits = "";
    for (let t = from; t < now; t += strip) {
      const mid = t + strip / 2;
      const point = points.reduce((best, p) => (!best || Math.abs(p[0] - mid) < Math.abs(best[0] - mid) ? p : best), null);
      if (!point || Math.abs(point[0] - mid) > strip) continue;
      hits += `<rect class="hit" x="${x(t).toFixed(1)}" y="${T}" width="${(x(Math.min(now, t + strip)) - x(t)).toFixed(1)}" height="${H - T - B}"${tipAttr(fmt.day(point[0], { weekday: "short", hour: "2-digit", minute: "2-digit" }), [["Left", `${Math.round(point[1])}%${pool.accounts > 1 ? ` of ${Math.round(pool.capacity)}%` : ""}`]])}/>`;
    }
    return `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="${esc(pool.name)} left over the last ${esc(QUOTA_SPANS[hours])}">
      ${grid}<path class="qarea" d="${area}"/><path class="qline" d="${line}"/>${resets}${hits}
    </svg>`;
  }

  // How much was used in each hour, or each four hours across a week.
  function drainChart(pool, hours) {
    const W = historyWidth(), H = 240, L = 48, R = 14, T = 12, B = 26;
    const now = new Date(data.quota.forecastStart).getTime();
    const from = now - hours * 3600_000;
    const points = seriesPoints(data.quota.pastStart, pool.drain || []).filter(([t, v]) => v != null && t >= from && t <= now);
    if (!points.length) return `<p class="empty">Keyhop draws this once it has read the limits for a while.</p>`;
    const block = hours > 48 ? 4 * 3600_000 : 3600_000;
    const buckets = new Map();
    for (const [t, v] of points) {
      const key = Math.floor(t / block) * block;
      const entry = buckets.get(key) || { sum: 0, n: 0 };
      entry.sum += v; entry.n += 1;
      buckets.set(key, entry);
    }
    const rows = [...buckets.entries()].map(([t, e]) => [t, e.sum / e.n]);
    const ceiling = niceCeiling(Math.max(1, ...rows.map(([, v]) => v)));
    const x = (t) => L + ((t - from) / (now + block - from)) * (W - L - R);
    const y = (v) => T + (1 - v / ceiling) * (H - T - B);
    let grid = "";
    for (let i = 0; i <= 4; i++) {
      const value = (ceiling / 4) * i, yy = y(value).toFixed(1);
      grid += `<line class="${i ? "grid" : "base"}" x1="${L}" x2="${W - R}" y1="${yy}" y2="${yy}"/><text class="axis" x="${L - 8}" y="${yy}" text-anchor="end" dominant-baseline="central">${value < 10 && value % 1 ? value.toFixed(1) : Math.round(value)}%</text>`;
    }
    grid += timeAxis(from, now + block, x, H, B);
    const bw = Math.max(2, (x(from + block) - x(from)) * 0.62);
    const per = (v) => `${v >= 10 ? Math.round(v) : v.toFixed(1)}% an hour`;
    const bars = rows.map(([t, v]) => {
      const cx = x(t + block / 2), h = Math.max(0, y(0) - y(v));
      return `<rect class="qbar" x="${(cx - bw / 2).toFixed(1)}" y="${y(v).toFixed(1)}" width="${bw.toFixed(1)}" height="${h.toFixed(1)}" rx="1.5"${tipAttr(fmt.day(t, { weekday: "short", hour: "2-digit", minute: "2-digit" }), [["Used", per(v)]])}/>`;
    }).join("");
    return `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="${esc(pool.name)} used per hour">${grid}${bars}</svg>`;
  }

  // MARK: Logins

  function loginGroup(tool, adding) {
    const order = (account) => (account.active ? -1 : 0) * 1000 + (account.error ? 500 : 0) + maxUsed(account);
    const active = tool.accounts.find((account) => account.active);
    const best = alternative(tool, active);
    const rows = tool.accounts.slice().sort((a, b) => order(a) - order(b)).map((account) => loginRow(account, tool, best)).join("");
    const waiting = adding ? `<div class="lim-row waiting-row"><div class="waiting"><span class="pulse"><i></i><i></i><i></i></span><span>Waiting for a new ${esc(tool.name)} login ${waited(tool.id)}<br><small>${esc(tool.signInHint)}</small></span></div>
        ${isStatic ? "" : `<button class="btn sm ghost" data-action="add-stop" data-tool="${esc(tool.id)}">Stop</button>`}</div>` : "";
    const service = serviceFor(tool.id);
    const count = `${tool.accounts.length} login${tool.accounts.length === 1 ? "" : "s"}`;
    const summary = `<span class="lim-sum${service ? " bad" : ""}">${esc(service ? `${count} · ${serviceShort[service.level]}` : count)}</span>`;
    return `<section class="lim-group" aria-label="${esc(tool.name)}">
      <header class="lim-group-head"><span class="tile-mark">${mark(tool.id)}</span><h2>${esc(tool.name)}</h2>${summary}
        ${isStatic ? "" : `<button class="btn sm ghost" data-action="add" data-tool="${esc(tool.id)}" ${adding ? "disabled" : ""}>${icon("plus")}Add login</button>`}</header>
      <div class="card lim-list">${waiting}${rows}</div>
    </section>`;
  }

  function windowBars(account, tool) {
    if (account.error) return `<p class="lnote">Signed out. Sign in to ${esc(tool.name)} again to read its limits.</p>`;
    const limits = (account.limits || []).slice(0, 3);
    if (!limits.length && account.limitsWait) return `<p class="lnote">${esc(account.limitsWait)}</p>`;
    if (!limits.length && account.limitsRetryAt) return `<p class="lnote">${esc(tool.name)} is rate limiting usage checks. Keyhop reads this login again in ${esc(fmt.until(account.limitsRetryAt))}.</p>`;
    if (!limits.length && account.readError) return `<p class="lnote">Couldn't read the limits just now. Keyhop tries again on the next refresh.</p>`;
    if (!limits.length) return `<p class="lnote">${esc(tool.limitsNote || "No limit to read.")}</p>`;
    return limits.map((limit) => {
      const used = Math.round(limit.usedPercent);
      return `<div class="lwin">
        <span class="lwin-name">${esc(windowName(limit.label))}</span>
        ${progress(limit.usedPercent, null, undefined, `limits:${account.id}:${limit.label}`)}
        <span class="lwin-pct${used >= 90 ? " bad" : ""}">${used}% used</span>
        <span class="lwin-foot">${!limit.resetsAt ? "" : new Date(limit.resetsAt) <= new Date() ? "reset since this reading" : `resets in ${esc(fmt.until(limit.resetsAt))}`}</span>
      </div>`;
    }).join("");
  }

  // One saved login: who it is, its windows, and one thing to do with it.
  function loginRow(account, tool, best) {
    const lane = laneOf(account);
    const editing = ui.editing === account.id;
    // A failed reading keeps the last good one, and says how old it is.
    const read = account.error || !account.limitsReadAt ? "" : `${account.readError || account.limitsWait ? "last read" : "read"} ${fmt.relative(account.limitsReadAt)}`;
    const meta = [account.plan, account.label ? account.email : "", account.keepForLast ? "kept for last" : "", read].filter(Boolean).join(" · ");
    const pill = account.error ? `<span class="lim-pill bad">Signed out</span>`
      : account.active ? `<span class="lim-pill in-use" style="view-transition-name:in-use-${esc(tool.id)}">In use</span>`
      : best && best.id === account.id ? `<span class="lim-pill good">Most room</span>` : "";
    const dotTone = account.error || lane === "needs" ? "bad" : lane === "hot" ? "warn" : "good";
    const who = editing
      ? `<form class="rename" data-form="rename" data-id="${esc(account.id)}"><input class="field" name="name" value="${esc(account.label || "")}" placeholder="${esc(account.email)}" maxlength="60" aria-label="Name"><button class="btn sm">Save</button><button type="button" class="btn sm ghost" data-action="cancel-edit">Cancel</button></form>`
      : `<div class="lim-name"><i class="lim-dot ${dotTone}" aria-hidden="true"></i><b>${esc(account.name)}</b>${pill}</div>
         <div class="lim-meta" title="${esc(account.error || account.readError || "")}">${esc(meta)}</div>`;
    return `<div class="lim-row${account.active ? " active" : ""}" style="view-transition-name:acct-${esc(account.id)}">
      <div class="lim-who">${who}</div>
      <div class="lwins">${windowBars(account, tool)}</div>
      <div class="lim-side"><div class="row-actions">${loginActions(account, editing, best, tool)}</div></div>
    </div>`;
  }

  // Claude Code and Codex can run under one login in one terminal (keyhop run), with no hop.
  const runnable = { claude: "claude", codex: "codex" };
  const shellWord = (text) => /^[\w@.+-]+$/.test(text) ? text : `'${text.replace(/'/g, `'\\''`)}'`;

  function loginActions(account, editing, best, tool) {
    if (isStatic || editing) return "";
    if (ui.confirming === account.id) {
      return `<span class="subtle" style="font-size:12.5px">Remove this login?</span><button class="btn sm secondary danger" data-action="remove" data-id="${esc(account.id)}">Remove</button><button class="btn sm ghost" data-action="cancel-remove">Keep</button>`;
    }
    const open = ui.menu === account.id;
    const menu = open ? `<div class="row-menu" role="menu">
        <button type="button" role="menuitem" data-action="edit" data-id="${esc(account.id)}">Rename</button>
        ${tool.accounts.length > 1 ? `<button type="button" role="menuitem" data-action="reserve" data-id="${esc(account.id)}" data-value="${account.keepForLast ? "off" : "on"}" title="${account.keepForLast ? "Smart Hop offers it in turn again" : "Smart Hop offers it only when no other login has room"}">${account.keepForLast ? "Use in turn" : "Keep for last"}</button>` : ""}
        ${runnable[tool.id] && !account.error ? `<button type="button" role="menuitem" data-action="copy" data-value="${esc(`keyhop run ${shellWord(account.email)} --tool ${tool.id} -- ${runnable[tool.id]}`)}" title="Copies a command that runs ${esc(tool.name)} as this login in one terminal, without a hop">Copy terminal command</button>` : ""}
        ${account.active ? "" : `<button type="button" role="menuitem" class="danger" data-action="confirm-remove" data-id="${esc(account.id)}">Remove</button>`}
      </div>` : "";
    const lead = best && best.id === account.id;
    const main = account.active ? "" : `<button class="btn sm ${lead ? "" : "secondary"}" data-action="switch" data-id="${esc(account.id)}">${account.error ? "Sign in" : "Switch"}</button>`;
    return `${main}
      <span class="menu-anchor"><button type="button" class="btn sm ghost icon-only" data-action="account-menu" data-id="${esc(account.id)}" aria-haspopup="true" aria-expanded="${open}" aria-label="More for ${esc(account.name)}">${icon("more")}</button>${menu}</span>`;
  }

  // Tools with no saved login, folded away so they don't crowd the ones in use.
  function setupCard(tools) {
    if (!tools.length) return "";
    const rows = tools.map((tool) => `<div class="row setup-row"><div class="account-id"><span class="tile-mark">${mark(tool.id)}</span><div class="account-copy"><div class="account-name"><b>${esc(tool.name)}</b></div><div class="account-line">${esc(tool.signInHint)}</div></div></div>
      ${isStatic ? "" : `<button class="btn sm ghost" data-action="add" data-tool="${esc(tool.id)}">${icon("plus")}Add login</button>`}</div>`).join("");
    return `<details class="card setup"><summary>${icon("plus")}<span>Add another tool</span><span class="subtle">${esc(nameList(tools.map((tool) => tool.name)))}</span></summary><div class="list">${rows}</div></details>`;
  }

"""##
}
