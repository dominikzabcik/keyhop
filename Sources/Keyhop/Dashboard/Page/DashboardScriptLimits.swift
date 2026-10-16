import Foundation

/// Limits: every saved login in one place, the pooled quota they share, where it is headed, and
/// each login's windows with what to do next.
extension DashboardPage {
    static let scriptLimits = ##"""
  // MARK: Limits

  const QUOTA_SPANS = { 24: { past: 12, label: "24 hours" }, 168: { past: 72, label: "7 days" } };

  function quotaPool(tool = ui.quotaTool) {
    return data.quota?.pools?.find((pool) => pool.tool === tool) || null;
  }

  const quotaAccount = (id) => data.quota?.accounts?.find((account) => account.id === id) || null;

  // "Tue 22:00", or just the time when it is today.
  function when(date) {
    const at = new Date(date), now = new Date();
    const sameDay = at.toDateString() === now.toDateString();
    return sameDay ? fmt.clock(at) : fmt.day(at, { weekday: "short", hour: "2-digit", minute: "2-digit" });
  }

  const perHour = (rate) => (rate >= 10 ? Math.round(rate) : rate.toFixed(1)) + "% an hour";

  function limitsPage(tools) {
    const adding = (id) => (data.state.adding || []).includes(id);
    const kept = tools.filter((tool) => tool.accounts.length || adding(tool.id));
    const total = kept.reduce((sum, tool) => sum + tool.accounts.length, 0);
    if (ui.quotaTool !== "all" && !kept.some((tool) => tool.id === ui.quotaTool)) ui.quotaTool = "all";
    const toolTabs = [["all", "All", total], ...kept.map((tool) => [tool.id, tool.name, tool.accounts.length])];
    // The tool filter leads the top bar, as one segmented control with each tool's mark and count.
    const toolbar = `<div class="tabs lim-tabs" role="group" aria-label="Show tool" data-tabs="quota-tool">${toolTabs.map(([id, name, n]) =>
      `<button type="button" data-action="quota-tool" data-value="${esc(id)}" aria-pressed="${id === ui.quotaTool}">${id === "all" ? "" : mark(id)}<span>${esc(name)}</span><span class="n">${n}</span></button>`).join("")}</div>`;
    const shown = ui.quotaTool === "all" ? kept : kept.filter((tool) => tool.id === ui.quotaTool);
    // A tool with one login and nothing wrong has nothing to hop to, so it is a tile; the rest get a group.
    const single = (tool) => ui.quotaTool === "all" && tool.accounts.length === 1 && !adding(tool.id)
      && !tool.accounts[0].error && tool.accounts[0].limits?.length && laneOf(tool.accounts[0]) !== "needs";
    const measured = shown.filter((tool) => !adding(tool.id) && tool.accounts.length && tool.accounts.every((a) => !a.error && !a.limits?.length));
    const grouped = shown.filter((tool) => !single(tool) && !(ui.quotaTool === "all" && measured.includes(tool) && tool.accounts.length === 1));
    const atWall = (tool) => { const active = tool.accounts.find((a) => a.active); return active && laneOf(active) === "needs" && !active.error && !alternative(tool, active) ? 1 : 0; };
    grouped.sort((a, b) => atWall(b) - atWall(a));
    const groups = grouped.map((tool) => loginGroup(tool, adding(tool.id))).join("");
    const singles = shown.filter(single);
    const unset = ui.quotaTool === "all" ? setupCard(tools.filter((tool) => !tool.accounts.length && !adding(tool.id))) : "";
    const empty = !kept.length ? `<section class="card"><p class="empty">No saved logins yet. Add one below and Keyhop keeps it.</p></section>` : "";
    return { toolbar, body: `<div class="lim-page">${quotaCard()}${empty}${groups}${singlesBlock(singles, measured)}${unset}</div>` };
  }

  // Tools with one login each, as tiles, then a word on the tools that have no limit at all.
  function singlesBlock(tools, measured) {
    const note = measured.length
      ? `<p class="lim-foot">${esc(nameList(measured.map((tool) => tool.name)))} ${measured.length === 1 ? "measures" : "measure"} tokens only, so there is no limit to read. ${measured.length === 1 ? "It is" : "They are"} counted in Usage.</p>` : "";
    if (!tools.length) return note ? `<section class="lim-singles">${note}</section>` : "";
    const tiles = tools.map((tool) => {
      const account = tool.accounts[0];
      const top = tightest(account);
      const used = top ? top.usedPercent : 0;
      const left = Math.max(0, Math.round(100 - used));
      const back = top?.resetsAt ? ` · back in ${fmt.until(top.resetsAt)}` : "";
      const name = ui.editing === account.id
        ? `<form class="rename" data-form="rename" data-id="${esc(account.id)}"><input class="field" name="name" value="${esc(account.label || "")}" placeholder="${esc(account.email)}" maxlength="60" aria-label="Name"><button class="btn sm">Save</button><button type="button" class="btn sm ghost" data-action="cancel-edit">Cancel</button></form>`
        : `<span class="lim-tile-name">${mark(tool.id)}<b>${esc(tool.name)}</b></span><span class="lim-tile-left">${left}% left</span>${tileMenu(account, tool)}`;
      return `<div class="card lim-tile" role="listitem" title="${esc(account.name)}">
        <div class="lim-tile-head">${name}</div>
        ${progress(used, top?.pace, undefined, `limits:${account.id}:tile`)}
        <span class="lim-tile-sub">${esc(account.name)} · ${esc(top ? windowName(top.label) : "")}${esc(back)}</span>
      </div>`;
    }).join("");
    return `<section class="lim-singles" aria-labelledby="one-h">
      <div class="lim-group-head"><h2 id="one-h">One login each</h2><span class="lim-sum">nothing to hop to yet</span></div>
      <div class="lim-tiles" role="list">${tiles}</div>${note}
    </section>`;
  }

  // A tile's menu: name the login, or add a second one to hop to.
  function tileMenu(account, tool) {
    if (isStatic) return "";
    const open = ui.menu === account.id;
    const menu = open ? `<div class="row-menu" role="menu">
        <button type="button" role="menuitem" data-action="edit" data-id="${esc(account.id)}">Rename</button>
        <button type="button" role="menuitem" data-action="add" data-tool="${esc(tool.id)}">Add another login</button>
      </div>` : "";
    return `<span class="menu-anchor"><button type="button" class="btn sm ghost icon-only" data-action="account-menu" data-id="${esc(account.id)}" aria-haspopup="true" aria-expanded="${open}" aria-label="More for ${esc(account.name)}">${icon("more")}</button>${menu}</span>`;
  }

  // MARK: Pooled quota

  function quotaCard() {
    if (!data.quota) {
      if (data.quotaError) return `<div class="notice">${icon("alert")}<div><b>The forecast isn't available</b><p>${esc(data.quotaError)}</p></div></div>`;
      if (isStatic) return "";
      return `<section class="card qcard">${loading("Reading the limits' history", "empty")}</section>`;
    }
    const pool = quotaPool();
    if (!pool || !pool.accounts) {
      return `<section class="card qcard"><p class="empty">${ui.quotaTool === "all" ? "No saved login has a limit to read yet." : `${esc(toolName(ui.quotaTool))} doesn't report a limit Keyhop can read, so there is nothing to pool.`}</p></section>`;
    }
    const span = QUOTA_SPANS[ui.quotaHours] || QUOTA_SPANS[168];
    const share = pool.capacity ? pool.remaining / pool.capacity : 0;
    const tone = share <= 0.15 ? "bad" : share <= 0.35 ? "warn" : "";
    const rate = pool.drainPerHour || 0;
    const scope = ui.quotaTool === "all" ? `${pool.accounts} login${pool.accounts === 1 ? "" : "s"} with limits` : `${pool.accounts} ${esc(pool.name)} login${pool.accounts === 1 ? "" : "s"}`;
    const rateText = rate >= 10 ? Math.round(rate) : rate.toFixed(1);
    const empties = pool.emptyAt ? new Date(pool.emptyAt) - Date.now() : null;
    const pace = empties == null || empties <= 0
      ? { value: ui.quotaHours > 48 ? "7+ days" : "24+ hours", sub: `before ${pool.accounts === 1 ? "it runs" : "they run"} out`, tone: "" }
      : { value: empties >= 2 * 86400_000 ? `${Math.round(empties / 86400_000)} days` : fmt.until(pool.emptyAt), sub: `before ${pool.accounts === 1 ? "it runs" : "all run"} out · ${when(pool.emptyAt)}`, tone: empties < 6 * 3600_000 ? "bad" : empties < 24 * 3600_000 ? "warn" : "" };
    const figure = (name, value, sub, cls = "") => `<div class="lim-fig"><span class="lim-fig-name">${name}</span><b class="${cls}">${value}</b><span class="lim-fig-sub">${sub}</span></div>`;
    const figures = [
      figure("Draining", rate >= 0.05 ? `${rateText}%/h` : "Not now", rate >= 0.05 ? `this hour, ${pool.accounts === 1 ? "this login" : "all logins"}` : "nothing is being used"),
      pool.nextReset
        ? figure("Next reset", `+${Math.round(pool.nextReset.gain)}%`, `at ${esc(when(pool.nextReset.at))} · ${esc(pool.nextReset.account)}`, "up")
        : figure("Next reset", "None soon", `within ${esc(span.label)}`),
      figure("At this pace", esc(pace.value), esc(pace.sub), pace.tone),
    ].join("");
    const summary = `<section class="card lim-total" aria-labelledby="lim-total-h">
      <span class="lim-total-title"><span class="lab">${scope} · out of ${Math.round(pool.capacity)}%</span><h2 id="lim-total-h">What your logins have left</h2></span>
      <div class="lim-big ${tone}"><b data-count="${pool.remaining}" data-count-key="quota:${esc(pool.tool)}" data-format="pct">${Math.round(pool.remaining)}%</b><span>left across ${pool.accounts === 1 ? "it" : "them all"}</span></div>
      <p class="lim-note">Each login keeps its own limits. This adds up what each one has left, so 100% is one full login.</p>
      <div class="lim-figs">${figures}</div>
    </section>`;
    const title = ui.quotaHours > 48 ? "This week and next" : "Today and tomorrow";
    const legend = ui.quotaView === "drain" ? `<span><i class="bar"></i>Drain per hour</span>` : `<span><i class="solid"></i>Measured</span><span><i class="dash"></i>Projected</span><span><i class="reset"></i>Reset</span>`;
    const forecast = `<section class="card qcard" aria-labelledby="lim-fore-h">
      <div class="lim-fore-head"><h2 id="lim-fore-h">${title}</h2><span class="qlegend">${legend}</span></div>
      <div class="qchart chart">${ui.quotaView === "drain" ? drainChart(pool, span) : quotaChart(pool, span)}</div>
      <div class="lim-fore-tools">${tabs("quota-hours", Object.entries(QUOTA_SPANS).map(([hours, s]) => [hours, s.label]), String(ui.quotaHours))}${tabs("quota-view", [["remaining", "Remaining"], ["drain", "Drain rate"]], ui.quotaView)}</div>
    </section>`;
    return `<div class="lim-top">${summary}${forecast}</div>`;
  }

  // The forecast sits beside the summary, so its chart is drawn to that card's width.
  function forecastWidth() {
    const main = Math.min(1480, ($("#main")?.clientWidth || 1200) - 56);
    const wide = !matchMedia("(max-width: 1180px)").matches;
    return Math.max(420, Math.floor((wide ? (main - 18) * 1.3 / 2.3 : main) - 54));
  }

  // Points of a series as [time, value], from its first time and the report's step.
  function seriesPoints(start, values) {
    const t0 = new Date(start).getTime(), step = (data.quota.step || 1800) * 1000;
    return values.map((value, i) => [t0 + i * step, value]);
  }

  function timeAxis(from, to, x, H, B) {
    let labels = "";
    const hours = (to - from) / 3600_000;
    if (hours <= 48) {
      const every = 6 * 3600_000;
      for (let t = Math.ceil(from / every) * every; t <= to; t += every) {
        const date = new Date(t);
        labels += `<text class="axis" x="${x(t).toFixed(1)}" y="${H - 7}" text-anchor="middle">${esc(fmt.clock(date))}</text>`;
      }
    } else {
      const day = new Date(from); day.setHours(24, 0, 0, 0);
      for (let t = day.getTime(); t <= to; t += 86400_000) {
        labels += `<line class="grid day" x1="${x(t).toFixed(1)}" x2="${x(t).toFixed(1)}" y1="8" y2="${H - B}"/><text class="axis" x="${x(t + 43200_000).toFixed(1)}" y="${H - 7}" text-anchor="middle">${esc(fmt.day(t, { weekday: "short" }))}</text>`;
      }
    }
    return labels;
  }

  function quotaChart(pool, span) {
    const W = forecastWidth(), H = 240, L = 48, R = 14, T = 12, B = 26;
    const now = new Date(data.quota.forecastStart).getTime();
    const from = now - span.past * 3600_000, to = now + ui.quotaHours * 3600_000;
    const top = Math.max(100, pool.capacity);
    const x = (t) => L + ((t - from) / (to - from)) * (W - L - R);
    const y = (v) => T + (1 - Math.max(0, Math.min(top, v)) / top) * (H - T - B);
    const past = seriesPoints(data.quota.pastStart, pool.past).filter(([t, v]) => v != null && t >= from && t <= now);
    const ahead = seriesPoints(data.quota.forecastStart, pool.forecast).filter(([t]) => t >= now && t <= to);
    let grid = "";
    for (let i = 0; i <= 4; i++) {
      const value = (top / 4) * i, yy = y(value).toFixed(1);
      grid += `<line class="${i ? "grid" : "base"}" x1="${L}" x2="${W - R}" y1="${yy}" y2="${yy}"/><text class="axis" x="${L - 8}" y="${yy}" text-anchor="end" dominant-baseline="central">${Math.round(value)}%</text>`;
    }
    grid += timeAxis(from, to, x, H, B);
    // Steps, not slopes: a reset lifts the line at once.
    const path = (points) => points.map(([t, v], i) => `${i ? "L" : "M"}${x(t).toFixed(1)},${y(v).toFixed(1)}`).join("");
    const pastLine = past.length > 1 ? path(past) : "";
    const pastArea = pastLine ? `${pastLine}L${x(past[past.length - 1][0]).toFixed(1)},${y(0).toFixed(1)}L${x(past[0][0]).toFixed(1)},${y(0).toFixed(1)}Z` : "";
    const aheadLine = ahead.length > 1 ? path(ahead) : "";
    const aheadArea = aheadLine ? `${aheadLine}L${x(ahead[ahead.length - 1][0]).toFixed(1)},${y(0).toFixed(1)}L${x(ahead[0][0]).toFixed(1)},${y(0).toFixed(1)}Z` : "";
    // Where the projection steps up is a reset; a small mark says so.
    // Resets close together read as one, so only the first in any three hours is marked.
    let resets = "", lastReset = -Infinity;
    for (let i = 1; i < ahead.length; i++) {
      const gain = ahead[i][1] - ahead[i - 1][1];
      if (gain >= Math.max(10, top * 0.05) && ahead[i][0] - lastReset >= 3 * 3600_000) {
        lastReset = ahead[i][0]; const rx = x(ahead[i][0]).toFixed(1); resets += `<line class="qreset" x1="${rx}" x2="${rx}" y1="${y(ahead[i - 1][1]).toFixed(1)}" y2="${y(ahead[i][1]).toFixed(1)}"/>`; }
    }
    const nowX = x(now).toFixed(1);
    const marker = `<line class="qnow" x1="${nowX}" x2="${nowX}" y1="${T - 4}" y2="${H - B}"/><text class="qnow-label" x="${nowX}" y="${T + 6}" dx="5">Now</text>`;
    // Hover strips, one per couple of hours, each with the value at its middle.
    const strip = ui.quotaHours > 48 ? 2 * 3600_000 : 1800_000;
    const all = [...past, ...ahead];
    let hits = "";
    for (let t = from; t < to; t += strip) {
      const mid = t + strip / 2;
      const point = all.reduce((best, p) => (!best || Math.abs(p[0] - mid) < Math.abs(best[0] - mid) ? p : best), null);
      if (!point || Math.abs(point[0] - mid) > strip) continue;
      const label = point[0] <= now ? "Measured" : "Projected";
      hits += `<rect class="hit" x="${x(t).toFixed(1)}" y="${T}" width="${(x(t + strip) - x(t)).toFixed(1)}" height="${H - T - B}"${tipAttr(fmt.day(point[0], { weekday: "short", hour: "2-digit", minute: "2-digit" }), [[label, `${Math.round(point[1])}% of ${Math.round(pool.capacity)}%`]])}/>`;
    }
    return `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="${esc(pool.name)} remaining, measured and projected">
      ${grid}
      ${pastArea ? `<path class="qarea" d="${pastArea}"/>` : ""}
      ${aheadArea ? `<path class="qarea ahead" d="${aheadArea}"/>` : ""}
      ${pastLine ? `<path class="qline" d="${pastLine}"/>` : ""}
      ${aheadLine ? `<path class="qline ahead" d="${aheadLine}"/>` : ""}
      ${resets}${marker}${hits}
    </svg>`;
  }

  function drainChart(pool, span) {
    const W = forecastWidth(), H = 240, L = 48, R = 14, T = 12, B = 26;
    const now = new Date(data.quota.forecastStart).getTime();
    const from = now - Math.max(span.past, ui.quotaHours === 24 ? 24 : 168) * 3600_000;
    const points = seriesPoints(data.quota.pastStart, pool.drain || []).filter(([t, v]) => v != null && t >= from && t <= now);
    if (!points.length) return `<p class="empty">Keyhop needs a few readings before it can say how fast the limits drain.</p>`;
    // Half-hour steps are grouped into hours, or into four-hour blocks across a week.
    const block = ui.quotaHours > 48 ? 4 * 3600_000 : 3600_000;
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
    const bars = rows.map(([t, v]) => {
      const cx = x(t + block / 2), h = Math.max(0, y(0) - y(v));
      return `<rect class="qbar" x="${(cx - bw / 2).toFixed(1)}" y="${y(v).toFixed(1)}" width="${bw.toFixed(1)}" height="${h.toFixed(1)}" rx="1.5"${tipAttr(fmt.day(t, { weekday: "short", hour: "2-digit", minute: "2-digit" }), [["Drain", perHour(v)]])}/>`;
    }).join("");
    return `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="${esc(pool.name)} drain per hour">${grid}${bars}</svg>`;
  }

  // MARK: Logins

  function loginGroup(tool, adding) {
    const pool = quotaPool(tool.id);
    const order = (account) => (account.active ? -1 : 0) * 1000 + (account.error ? 500 : 0) + maxUsed(account);
    const active = tool.accounts.find((account) => account.active);
    const best = active ? alternative(tool, active) : null;
    const rows = tool.accounts.slice().sort((a, b) => order(a) - order(b)).map((account) => loginRow(account, tool, best)).join("");
    const waiting = adding ? `<div class="lim-row waiting-row"><div class="waiting"><span class="pulse"><i></i><i></i><i></i></span><span>Waiting for a new ${esc(tool.name)} login ${waited(tool.id)}<br><small>${esc(tool.signInHint)} Keyhop saves it the moment it appears.</small></span></div>
        ${isStatic ? "" : `<button class="btn sm ghost" data-action="add-stop" data-tool="${esc(tool.id)}">Stop waiting</button>`}</div>` : "";
    const wall = active && !active.error && laneOf(active) === "needs" && !best;
    const service = serviceFor(tool.id);
    const parts = [];
    if (pool && pool.accounts) parts.push(`${Math.round(pool.remaining)}% of ${Math.round(pool.capacity)}% left`);
    else if (!tool.accounts.some((account) => account.limits?.length)) parts.push("No limit to read");
    if (service) parts.push(serviceShort[service.level]);
    else if (pool && pool.drainPerHour >= 0.05) parts.push(`about ${pool.drainPerHour >= 10 ? Math.round(pool.drainPerHour) : pool.drainPerHour.toFixed(1)}%/h`);
    const summary = parts.length ? `<span class="lim-sum${wall || service ? " bad" : ""}">${esc(parts.join(" · "))}</span>` : "";
    return `<section class="lim-group" aria-label="${esc(tool.name)}">
      <header class="lim-group-head"><span class="tile-mark">${mark(tool.id)}</span><h2>${esc(tool.name)}</h2>${summary}
        ${isStatic ? "" : `<button class="btn sm secondary" data-action="add" data-tool="${esc(tool.id)}" ${adding ? "disabled" : ""}>Add account</button>`}</header>
      <div class="card lim-list">${waiting}${rows}</div>
    </section>`;
  }

  // What happens next for one login, from the forecast: back, empty, or how fast it goes.
  function loginOutlook(account) {
    if (account.error) return { text: "Sign in again", tone: "bad" };
    const forecast = quotaAccount(account.id);
    if (!account.limits?.length) return { text: "", tone: "" };
    if (forecast?.backAt) return { text: `Back in ${fmt.until(forecast.backAt)}`, tone: "bad" };
    if (maxUsed(account) >= 100) {
      const top = tightest(account);
      return { text: top?.resetsAt ? `Back in ${fmt.until(top.resetsAt)}` : "At its limit", tone: "bad" };
    }
    const empty = forecast?.emptyAt || tightest(account)?.runsOutAt;
    if (empty && new Date(empty) - Date.now() < 7 * 86400_000) {
      return { text: `Empty around ${when(empty)}`, tone: new Date(empty) - Date.now() < 6 * 3600_000 ? "warn" : "" };
    }
    if (forecast && forecast.drainPerHour >= 0.05) return { text: `~${perHour(forecast.drainPerHour)}`, tone: "" };
    return { text: account.active ? "Idle" : "Resting", tone: "subtle" };
  }

  function windowBars(account, tool) {
    if (account.error) return `<p class="lnote">Switch to it and sign in to ${esc(tool.name)} again to read its limits.</p>`;
    const limits = (account.limits || []).slice(0, 3);
    if (!limits.length) return `<p class="lnote">${esc(tool.limitsNote || "No limit to read.")}</p>`;
    return limits.map((limit) => {
      const used = Math.round(limit.usedPercent);
      const foot = runsOutSoon(limit) ? `runs out ${fmt.clock(limit.runsOutAt)}` : limit.resetsAt ? `back in ${fmt.until(limit.resetsAt)}` : "";
      return `<div class="lwin">
        <span class="lwin-name">${esc(windowName(limit.label))}</span>
        ${progress(limit.usedPercent, limit.pace, undefined, `limits:${account.id}:${limit.label}`)}
        <span class="lwin-pct${used >= 90 ? " bad" : ""}">${used}%</span>
        <span class="lwin-foot">${esc(foot)}</span>
      </div>`;
    }).join("");
  }

  // One saved login: who it is, its windows, what happens next, and what you can do with it.
  function loginRow(account, tool, best) {
    const lane = laneOf(account);
    const editing = ui.editing === account.id;
    const wall = account.active && !account.error && lane === "needs" && !best;
    let outlook = loginOutlook(account);
    if (wall) outlook = { text: `No other ${tool.name} login`, tone: "bad" };
    else if (best && best.id === account.id && outlook.tone !== "bad") outlook = { text: "Has the most room", tone: "good" };
    const meta = [account.plan, account.label ? account.email : "", account.error ? "login expired" : account.limitsReadAt ? `read ${fmt.relative(account.limitsReadAt)}` : ""].filter(Boolean).join(" · ");
    const pill = account.error ? `<span class="lim-pill bad">Signed out</span>` : account.active ? `<span class="lim-pill in-use" style="view-transition-name:in-use-${esc(tool.id)}">In use</span>` : "";
    const dotTone = account.error || wall ? "bad" : lane === "needs" || lane === "hot" ? "warn" : "good";
    const who = editing
      ? `<form class="rename" data-form="rename" data-id="${esc(account.id)}"><input class="field" name="name" value="${esc(account.label || "")}" placeholder="${esc(account.email)}" maxlength="60" aria-label="Name"><button class="btn sm">Save</button><button type="button" class="btn sm ghost" data-action="cancel-edit">Cancel</button></form>`
      : `<div class="lim-name"><i class="lim-dot ${dotTone}" aria-hidden="true"></i><b>${esc(account.name)}</b>${pill}</div>
         <div class="lim-meta" title="${esc(account.error || "")}">${esc(meta)}</div>`;
    return `<div class="lim-row${wall ? " wall" : ""}${account.active ? " active" : ""}" style="view-transition-name:acct-${esc(account.id)}">
      <div class="lim-who">${who}</div>
      <div class="lwins">${windowBars(account, tool)}</div>
      <div class="lim-side"><span class="loutlook ${outlook.tone}">${esc(outlook.text)}</span><div class="row-actions">${loginActions(account, editing, tool, wall, best)}</div></div>
    </div>`;
  }

  function loginActions(account, editing, tool, wall, best) {
    if (isStatic || editing) return "";
    if (ui.confirming === account.id) {
      return `<span class="subtle" style="font-size:12.5px">Delete this saved login?</span><button class="btn sm secondary danger" data-action="remove" data-id="${esc(account.id)}">Remove</button><button class="btn sm ghost" data-action="cancel-remove">Keep</button>`;
    }
    const open = ui.menu === account.id;
    const menu = open ? `<div class="row-menu" role="menu">
        <button type="button" role="menuitem" data-action="edit" data-id="${esc(account.id)}">Rename</button>
        ${account.active ? "" : `<button type="button" role="menuitem" class="danger" data-action="confirm-remove" data-id="${esc(account.id)}">Remove saved login</button>`}
      </div>` : "";
    const hop = best && best.id === account.id && !account.error;
    const main = wall ? `<button class="btn sm secondary" data-action="add" data-tool="${esc(tool.id)}">Add account</button>`
      : account.active ? "" : `<button class="btn sm ${hop ? "" : "secondary"}" data-action="switch" data-id="${esc(account.id)}">${account.error ? "Switch and sign in" : hop ? "Hop here" : "Switch"}</button>`;
    return `${main}
      <span class="menu-anchor"><button type="button" class="btn sm ghost icon-only" data-action="account-menu" data-id="${esc(account.id)}" aria-haspopup="true" aria-expanded="${open}" aria-label="More for ${esc(account.name)}">${icon("more")}</button>${menu}</span>`;
  }

  // Tools with no saved login, folded away so they don't crowd the ones in use.
  function setupCard(tools) {
    if (!tools.length) return "";
    const rows = tools.map((tool) => `<div class="row setup-row"><div class="account-id"><span class="tile-mark">${mark(tool.id)}</span><div class="account-copy"><div class="account-name"><b>${esc(tool.name)}</b></div><div class="account-line">${esc(tool.signInHint)}</div></div></div>
      ${isStatic ? "" : `<button class="btn sm ghost" data-action="add" data-tool="${esc(tool.id)}">${icon("plus")}Add account</button>`}</div>`).join("");
    return `<details class="card setup"><summary>${icon("plus")}<span>Add another tool</span><span class="subtle">${esc(nameList(tools.map((tool) => tool.name)))}</span></summary><div class="list">${rows}</div></details>`;
  }

"""##
}
