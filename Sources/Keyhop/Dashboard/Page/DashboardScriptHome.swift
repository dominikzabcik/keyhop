import Foundation

/// The core screen: one verdict sentence with the one hop button, the logins ranked by runway,
/// and today's figure. Everything else in the window is a quiet link away.
extension DashboardPage {
    static let scriptHome = ##"""
  // MARK: Core screen

  const servicePhrase = {
    maintenance: "is under maintenance",
    degraded: "has degraded performance",
    partial: "is in a partial outage",
    major: "is in a major outage",
  };
  const serviceShort = {
    maintenance: "under maintenance",
    degraded: "degraded",
    partial: "partial outage",
    major: "major outage",
  };

  function tightest(account) {
    const limits = account.limits || [];
    if (!limits.length) return null;
    return limits.reduce((a, b) => (b.usedPercent > a.usedPercent ? b : a));
  }

  // needs: the login in use is signed out or has 15% or less left on its tightest window.
  // hot: any other login that low. quiet: nothing to read. active: the login in use, with room.
  function laneOf(account) {
    if (account.error) return account.active ? "needs" : "hot";
    const left = leftOf(account);
    if (left == null) return "quiet";
    if (left <= 15) return account.active ? "needs" : "hot";
    if (account.active) return "active";
    return left <= 40 ? "hot" : "room";
  }

  // The hop most worth making now: a tool whose login in use needs one and has somewhere to go.
  function bestHop(tools) {
    let best = null;
    for (const tool of tools) {
      const active = tool.accounts.find((a) => a.active);
      if (!active || laneOf(active) !== "needs") continue;
      const alt = alternative(tool, active);
      if (!alt) continue;
      const gap = leftOf(alt) - (active.error ? 0 : leftOf(active) ?? 0);
      if (!best || gap > best.gap) best = { tool, from: active, to: alt, gap };
    }
    return best;
  }

  function serviceFor(toolId) {
    return (data.services || []).find((s) => s.tool === toolId && servicePhrase[s.level]) || null;
  }

  function outageSentence(service) {
    const phrase = servicePhrase[service.level];
    if (!phrase) return "";
    const advice = service.level === "maintenance" ? "" : " Every login is affected, so hopping won't help.";
    return `${toolName(service.tool)} ${phrase}.${advice}`;
  }

  function nameList(names) {
    if (names.length < 2) return names.join("");
    return `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
  }

  // Durations the way the row reads them: "1 h 20 m", "14 h", "13 d".
  function untilWords(date) {
    const s = Math.max(0, Math.round((new Date(date) - Date.now()) / 1000));
    const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
    if (s >= 48 * 3600) return `${d} d`;
    if (s >= 10 * 3600) return `${d * 24 + h} h`;
    if (s >= 3600) return `${h} h ${String(m).padStart(2, "0")} m`;
    return `${Math.max(1, m)} m`;
  }
  const aboutWords = (date) => {
    const minutes = Math.max(1, Math.round((new Date(date) - Date.now()) / 60000));
    if (minutes < 55) return `about ${Math.max(5, Math.round(minutes / 5) * 5)} minutes`;
    const hours = Math.round(minutes / 60);
    return hours < 36 ? `about ${hours} hour${hours === 1 ? "" : "s"}` : `about ${Math.round(hours / 24)} days`;
  };

  // One row per tool: the login in use and its tightest window. Nothing here is a control; the
  // verdict's button is the one hop.
  function coreRow(tool) {
    const active = tool.accounts.find((a) => a.active) || tool.accounts[0];
    if (!active) return null;
    const alt = alternative(tool, active);
    const left = active.error ? null : leftOf(active);
    const tight = tightest(active);
    const windows = (active.limits || []).filter((l) => !l.resetsAt || new Date(l.resetsAt) > new Date());
    const runsOut = windows.map((l) => l.runsOutAt).filter(Boolean).sort()[0] || null;
    const idle = !active.error && !tight;
    const state = active.error || (left != null && left <= 15) ? "crit" : left != null && left <= 40 ? "low" : "";
    // The tag answers "can I hop out of this?" exactly when that matters.
    const spare = tool.accounts.some((a) => !a.active && !a.error && (a.limits || []).length);
    const noSpare = state && !active.error && !spare ? `<em class="flag">no spare</em>` : "";
    const resets = tight?.resetsAt && new Date(tight.resetsAt) > new Date() ? untilWords(tight.resetsAt) : "";
    const value = active.error ? `signed out`
      : idle || left == null ? ""
      : `${left}%${resets ? ` · <span class="rw">resets in </span>${esc(resets)}` : ""}`;
    const plan = !active.error && !idle && active.plan ? ` <span class="plan">· ${esc(active.plan)}</span>` : "";
    const spent = active.today && active.today.tokens > 0 ? `${fmt.tokens(active.today.tokens)} · ${fmt.usd(active.today.cost)}` : "";
    let title = "";
    if (active.error) title = `Signed out. Sign in to ${tool.name} again to read its limits.`;
    else if (idle) title = tool.limitsNote || `${tool.name} publishes no limits; Keyhop measures its usage only.`;
    else if (runsOut && tight?.resetsAt && new Date(runsOut) < new Date(tight.resetsAt)) {
      title = `At this pace the window empties around ${fmt.clock(runsOut)}, before it resets.${!spare ? " No second login to hop to." : ""}`;
    } else if (resets) title = `On pace to make its reset in ${resets}.`;
    const order = active.error ? -1 : left == null ? 9999 : left;
    const html = `<li class="row ${state}${idle ? " idle" : ""}${ui.hopped && ui.hopped.tool === tool.id && Date.now() - ui.hopped.at < 2200 ? " hopped" : ""}" style="view-transition-name:row-${esc(tool.id)}"${title ? ` title="${esc(title)}"` : ""}>
      <span class="dot" aria-hidden="true"></span>
      <span class="tool">${esc(tool.name)}</span>
      <span class="login">${esc(idle ? "measured only" : active.name)}${plan}${noSpare}</span>
      <span class="tdy">${spent}</span>
      ${idle || left == null ? `<span class="runway" aria-hidden="true"></span>` : `<span class="runway" role="img" aria-label="${left}% of the window left"><i style="width:${left}%" data-grow="core:${esc(tool.id)}"></i></span>`}
      <span class="left">${value}</span>
    </li>`;
    return { order, html };
  }

  // The verdict: one sentence, and at most one action.
  function verdictFor(tools) {
    const hopped = ui.hopped && Date.now() - ui.hopped.at < 7000 ? ui.hopped : null;
    if (hopped) {
      const tool = tools.find((t) => t.id === hopped.tool);
      const to = tool?.accounts.find((a) => a.id === hopped.to);
      const left = to ? leftOf(to) : null;
      return {
        text: `Hopped ${esc(toolName(hopped.tool))} to ${esc(hopped.name)}.${left != null ? ` <span class="detail">${left}% of the window left.</span>` : ""}`,
        button: isStatic || !hopped.from ? "" : `<button class="btn ghost" type="button" data-action="unhop" data-id="${esc(hopped.from)}" data-tool="${esc(hopped.tool)}">Undo</button>`,
      };
    }
    const outage = (data.services || []).find((s) => servicePhrase[s.level] && tools.some((t) => t.id === s.tool && t.accounts.some((a) => a.active)));
    if (outage) return { text: esc(outageSentence(outage)), button: "" };
    const hop = bestHop(tools);
    if (hop) {
      const tight = tightest(hop.from);
      const runsOut = !hop.from.error && (hop.from.limits || []).map((l) => l.runsOutAt).filter(Boolean).sort()[0];
      const lead = hop.from.error ? `${esc(hop.tool.name)} is signed out.`
        : runsOut ? `${esc(hop.tool.name)} runs out in ${esc(aboutWords(runsOut))}.`
        : `${esc(hop.tool.name)} is down to ${leftOf(hop.from)}%${tight?.resetsAt ? `, ${esc(untilWords(tight.resetsAt))} before its reset` : ""}.`;
      return {
        text: `${lead} <span class="detail">${esc(hop.to.name)} has ${leftOf(hop.to)}% left.</span>`,
        button: isStatic ? "" : `<button class="btn" type="button" data-action="hop" data-id="${esc(hop.to.id)}" data-from="${esc(hop.from.id)}" data-tool="${esc(hop.tool.id)}">
          <svg class="icon" viewBox="0 0 16 16" aria-hidden="true"><path d="M2.5 8h10M9 4.5 13.5 8 9 11.5"/></svg>Hop ${esc(hop.tool.name)}</button>`,
      };
    }
    // Nothing worth a hop: name the next concern, with its real figures.
    const rows = tools.flatMap((tool) => {
      const active = tool.accounts.find((a) => a.active);
      if (!active) return [];
      const left = active.error ? -1 : leftOf(active);
      return left == null ? [] : [{ tool, active, left }];
    }).sort((a, b) => a.left - b.left);
    const next = rows[0];
    if (!next) return { text: `No limits to read yet. <span class="detail">Add a login ${isStatic ? "in Limits" : "below"}.</span>`, button: "" };
    if (next.active.error) {
      return { text: `${esc(next.tool.name)} is signed out. <span class="detail">Sign in again from Limits.</span>`, button: "" };
    }
    if (next.left <= 15) {
      const tight = tightest(next.active);
      const resets = tight?.resetsAt ? ` Resets in ${esc(untilWords(tight.resetsAt))}.` : "";
      return { text: `${esc(next.tool.name)} is almost out, with no spare login. <span class="detail">${next.left}% left.${resets}</span>`, button: "" };
    }
    const runsOut = (next.active.limits || []).map((l) => l.runsOutAt).filter(Boolean).sort()[0];
    const spare = next.tool.accounts.some((a) => !a.active && !a.error && (a.limits || []).length);
    const concern = runsOut ? `${esc(next.tool.name)} in ${esc(aboutWords(runsOut))}${spare ? "" : ", with no spare login"}.`
      : `${esc(next.tool.name)} at ${next.left}%${spare ? "" : ", with no spare login"}.`;
    return { text: `Nothing runs out soon. <span class="detail">Next concern: ${concern}</span>`, button: "" };
  }

  // MARK: The runway

  // What the pool has left and where it is heading: the recorded line from the limit samples,
  // then the projected one with its resets stepping it back up. The one chart on the core screen.
  function runwayPanel() {
    if (isStatic) return "";
    if (!data.quota) return data.quotaError ? "" : `<section class="runway-panel skel-card" style="min-height:240px;border:0" aria-hidden="true"></section>`;
    const pool = data.quota.pools?.find((p) => p.tool === "all");
    if (!pool || !pool.accounts) return "";
    const one = pool.accounts === 1;
    const drain = pool.drainPerHour || 0;
    const kpis = `<div class="kpis">
      <div class="kpi lead"><div class="kpi-v">${Math.round(pool.remaining)}%</div><div class="kpi-l">${one ? "of the window left" : `left of ${Math.round(pool.capacity)}% · ${pool.accounts} logins with limits`}</div></div>
      ${pool.nextReset ? `<div class="kpi"><div class="kpi-v"><span class="up">+${Math.round(pool.nextReset.gain)}%</span></div><div class="kpi-l">resets at ${esc(when(pool.nextReset.at))} · ${esc(pool.nextReset.account)}</div></div>` : ""}
      <div class="kpi"><div class="kpi-v">${pool.emptyAt ? esc(when(pool.emptyAt)) : "Not soon"}</div><div class="kpi-l">pool empty at this pace</div></div>
      <div class="kpi"><div class="kpi-v">${drain >= 0.05 ? `${drain >= 10 ? Math.round(drain) : drain.toFixed(1)}%/h` : "0%/h"}</div><div class="kpi-l">burning right now</div></div>
    </div>`;
    return `<section class="runway-panel" aria-label="Runway"><h2 class="sr-only">Runway</h2>${kpis}<div class="qchart chart">${runwayChart(pool)}</div></section>`;
  }

  // A day of readings, then two days ahead, dashed. Resets mark where a window turns over.
  function runwayChart(pool) {
    const W = Math.max(520, Math.min(1480, $("#main")?.clientWidth || 940) - 48), H = 210, L = 44, R = 14, T = 14, B = 26;
    const now = new Date(data.quota.forecastStart).getTime();
    const from = now - 24 * 3600_000, to = now + 48 * 3600_000;
    const top = Math.max(100, pool.capacity);
    const x = (t) => L + ((t - from) / (to - from)) * (W - L - R);
    const y = (v) => T + (1 - Math.max(0, Math.min(top, v)) / top) * (H - T - B);
    const past = seriesPoints(data.quota.pastStart, pool.past).filter(([t, v]) => v != null && t >= from && t <= now);
    if (past.length < 2) return `<p class="empty">Keyhop draws the runway once it has read the limits for a while.</p>`;
    const ahead = seriesPoints(data.quota.forecastStart, pool.forecast).filter(([t]) => t >= now && t <= to);
    let grid = "";
    for (let i = 0; i <= 4; i++) {
      const value = (top / 4) * i, yy = y(value).toFixed(1);
      grid += `<line class="${i ? "grid" : "base"}" x1="${L}" x2="${W - R}" y1="${yy}" y2="${yy}"/><text class="axis" x="${L - 8}" y="${yy}" text-anchor="end" dominant-baseline="central">${Math.round(value)}%</text>`;
    }
    grid += timeAxis(from, to, x, H, B);
    const path = (points) => points.map(([t, v], i) => `${i ? "L" : "M"}${x(t).toFixed(1)},${y(v).toFixed(1)}`).join("");
    const area = (points) => `${path(points)}L${x(points[points.length - 1][0]).toFixed(1)},${y(0).toFixed(1)}L${x(points[0][0]).toFixed(1)},${y(0).toFixed(1)}Z`;
    // The resets ahead, each one named by what it gives back.
    let gains = "", lastGain = -Infinity;
    for (let i = 1; i < ahead.length; i++) {
      const gain = ahead[i][1] - ahead[i - 1][1];
      if (gain >= Math.max(10, top * 0.05) && ahead[i][0] - lastGain >= 3 * 3600_000) {
        lastGain = ahead[i][0];
        gains += `<text class="qgain" x="${x(ahead[i][0]).toFixed(1)}" y="${(y(ahead[i][1]) - 7).toFixed(1)}" text-anchor="middle">+${Math.round(gain)}%</text>`;
      }
    }
    const nowX = x(now).toFixed(1);
    const marker = `<line class="qnow" x1="${nowX}" x2="${nowX}" y1="${T}" y2="${H - B}"/><text class="qnow-label" x="${nowX}" y="${T - 3}" text-anchor="middle">Now</text>`;
    // Hover strips: readings behind now, the projection ahead of it.
    const strip = 2 * 3600_000;
    let hits = "";
    for (let t = from; t < to; t += strip) {
      const mid = t + strip / 2, future = mid > now;
      const points = future ? ahead : past;
      const point = points.reduce((best, p) => (!best || Math.abs(p[0] - mid) < Math.abs(best[0] - mid) ? p : best), null);
      if (!point || Math.abs(point[0] - mid) > strip) continue;
      hits += `<rect class="hit" x="${x(t).toFixed(1)}" y="${T}" width="${(x(Math.min(to, t + strip)) - x(t)).toFixed(1)}" height="${H - T - B}"${tipAttr(fmt.day(point[0], { weekday: "short", hour: "2-digit", minute: "2-digit" }), [[future ? "Projected" : "Left", `${Math.round(point[1])}%${pool.accounts > 1 ? ` of ${Math.round(pool.capacity)}%` : ""}`]])}/>`;
    }
    return `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="The pool's runway: a day recorded, two days projected">
      ${grid}<path class="qarea" d="${area(past)}"/><path class="qline" d="${path(past)}"/><path class="qarea ahead" d="${area(ahead)}"/><path class="qline ahead" d="${path(ahead)}"/>${gains}${marker}${hits}
    </svg>`;
  }

  // Today's figures come from the status (always there); the cache share and the per-tool split
  // fill in once today's usage is read.
  function todayStrip() {
    const today = data.state.status.today || { tokens: 0, cost: 0, requests: 0 };
    const usage = data.usage["today:all"];
    const t = usage?.total;
    const inputSide = t ? t.input + t.cacheRead + t.cacheWrite + (t.cacheWrite1h || 0) : 0;
    const cached = inputSide ? Math.round((t.cacheRead / inputSide) * 100) : null;
    const figure = `<div class="kpis">
      <div class="kpi lead"><div class="kpi-v num"><span data-count="${today.tokens}" data-count-key="core:tokens" data-format="tokens" data-count-intro>${fmt.tokens(today.tokens)}</span></div><div class="kpi-l">tokens today at API prices</div></div>
      <div class="kpi"><div class="kpi-v">${fmt.usd(today.cost)}</div><div class="kpi-l">API value</div></div>
      <div class="kpi"><div class="kpi-v">${fmt.count(today.requests)}</div><div class="kpi-l">requests</div></div>
      ${cached == null ? "" : `<div class="kpi"><div class="kpi-v">${cached}%</div><div class="kpi-l">cache hit</div></div>`}
    </div>`;
    const tools = (usage?.tools || []).filter((tool) => tool.figures.tokens > 0).sort((a, b) => b.figures.tokens - a.figures.tokens);
    const sum = tools.reduce((n, tool) => n + tool.figures.tokens, 0);
    let shares = "";
    if (sum && tools.length) {
      const top = tools.slice(0, 6);
      const pct = (n) => { const p = Math.round((n / sum) * 100); return p < 1 ? "<1%" : `${p}%`; };
      const bar = top.map((tool) => `<i style="width:${((tool.figures.tokens / sum) * 100).toFixed(1)}%"></i>`).join("");
      const key = top.map((tool) => `<span class="ki"><i aria-hidden="true"></i><b>${esc(tool.name)}</b>&nbsp;${pct(tool.figures.tokens)}</span>`).join("");
      shares = `<div class="shares">
        <div class="sharebar" role="img" aria-label="Share of today's tokens: ${esc(top.map((tool) => `${tool.name} ${pct(tool.figures.tokens)}`).join(", "))}">${bar}</div>
        <div class="sharekey">${key}</div>
      </div>`;
    }
    return `<section class="today">${figure}${shares}</section>`;
  }

  // Where a new login comes in: a quiet fold under the rows with the same add flow Limits has.
  function addFold(tools) {
    const addable = tools.filter((tool) => tool.switchable);
    if (isStatic || !addable.length) return "";
    const rows = addable.map((tool) => `<div class="row setup-row"><div class="account-id"><span class="setup-mark">${mark(tool.id)}</span><div class="account-copy"><div class="account-name"><b>${esc(tool.name)}</b></div><div class="account-line">${esc(tool.signInHint)}</div></div></div><button class="btn sm ghost" type="button" data-action="add" data-tool="${esc(tool.id)}">${icon("plus")}Add login</button></div>`).join("");
    return `<details class="core-add"><summary>${icon("plus")}<span>Add a login</span></summary><div class="list">${rows}</div></details>`;
  }

  function homePage(tools) {
    const adding = (id) => (data.state.adding || []).includes(id);
    const kept = tools.filter((tool) => tool.accounts.length || adding(tool.id));
    if (!kept.length) {
      const rows = tools.filter((tool) => tool.switchable).map((tool) => `<div class="row setup-row"><div class="account-id"><span class="setup-mark">${mark(tool.id)}</span><div class="account-copy"><div class="account-name"><b>${esc(tool.name)}</b></div><div class="account-line">${esc(tool.signInHint)}</div></div></div>${isStatic ? "" : `<button class="btn sm" type="button" data-action="add" data-tool="${esc(tool.id)}">Add login</button>`}</div>`).join("");
      return { body: `<div class="core">
        <h1 class="sr-only">Keyhop</h1>
        <section class="verdict"><p>No saved logins yet. <span class="detail">Sign in once and Keyhop keeps the login, reads its limits and hops when one runs low.</span></p></section>
        <div class="list setup-list">${rows}</div>
        ${todayStrip()}
      </div>` };
    }
    const rows = kept.map(coreRow).filter(Boolean).sort((a, b) => a.order - b.order).map((row) => row.html).join("");
    const waiting = kept.filter((tool) => adding(tool.id) && !tool.accounts.length);
    const waitRows = waiting.map((tool) => `<li class="row idle"><span class="dot" aria-hidden="true"></span><span class="tool">${esc(tool.name)}</span><span class="login">waiting for a new login ${waited(tool.id)}</span><span class="tdy"></span><span class="runway" aria-hidden="true"></span><span class="left"></span></li>`).join("");
    const verdict = verdictFor(kept);
    return { body: `<div class="core">
      <h1 class="sr-only">Keyhop</h1>
      <section class="verdict" aria-live="polite"><p id="verdict-text">${verdict.text}</p>${verdict.button}</section>
      ${runwayPanel()}
      <div class="colhead" aria-hidden="true"><span></span><span>Tool</span><span>Login</span><span class="r tdy">Today</span><span>Runway</span><span class="r">Window</span></div>
      <ul class="logins" id="logins">${rows}${waitRows}</ul>
      ${addFold(tools)}
      ${todayStrip()}
    </div>` };
  }

  // MARK: Shared pieces kept by the demoted views

  function petSvg(pet) {
    const caption = pet.lineageName ? `${pet.stageName} · ${pet.lineageName}` : pet.stageName;
    const shapes = pet.shapes.map((shape) => `<rect x="${shape.x}" y="${shape.y}" width="${shape.w}" height="${shape.h}" fill="${esc(shape.fill)}" fill-opacity="${shape.opacity}"${shape.kind === "flame" || shape.kind === "shine" || shape.kind === "eye" ? ` class="${shape.kind}"` : ""}/>`).join("");
    return { caption, svg: `<svg class="pet" viewBox="0 0 ${pet.width} ${pet.height}" shape-rendering="crispEdges" role="img" aria-label="${esc(caption)}">${shapes}</svg>` };
  }

  function currentClaim() {
    if (ui.section === "profile" && data.board && data.board.quests) return data.board.quests.claim || null;
    return (data.quests && data.quests.claim) || (data.board && data.board.quests && data.board.quests.claim) || null;
  }

  function claimKick(claim) {
    if (!claim || claim.claimed || !claim.active || !claim.today) return "";
    return `<button class="btn claim-kick" type="button" data-action="streak-claim">Claim ${esc(claim.today.name)}</button>`;
  }

  function petCard() {
    if (data.pet) {
      const pet = data.pet;
      const drawn = petSvg(pet);
      const next = pet.next ? `${fmt.tokens(pet.next.tokens)} to ${esc(pet.next.label)}` : "Monument";
      return `<section class="card pet-card">${drawn.svg}<div><h2>${esc(drawn.caption)}</h2><p>${next}</p></div></section>`;
    }
    if (isStatic || !data.state?.cloud?.available) return "";
    if (!data.state.cloud.linked) {
      return `<section class="card pet-slot"><div><b>Link with GitHub</b><p>Join leaderboards and get a profile you can share. Linking hatches your pet from the usage you already sync.</p></div><button class="btn sm" data-action="cloud-link">Link with GitHub</button></section>`;
    }
    if (data.petError) return `<section class="card"><p class="empty">${esc(data.petError)}</p></section>`;
    return "";
  }

  function budgetRow(budget) {
    const share = budget.amount > 0 ? budget.spent / budget.amount : 0;
    const elapsed = periodProgress(budget.period).elapsed;
    return `<div class="row budget-row">
      <div class="budget-top"><b>${esc(budget.name)}</b><span class="mono">${fmt.usd(budget.spent)} <span class="subtle">/ ${fmt.usd(budget.amount)}</span></span></div>
      ${progress(share * 100, elapsed, share >= 1 ? "bad" : share >= .8 ? "warn" : "", `budget:${budget.scope}`)}
      <div class="subtle" style="font-size:12px">Per ${esc(budget.period)} · ${Math.round(share * 100)}% used · on pace for ${fmt.usd(budget.spent / elapsed)}</div>
    </div>`;
  }

"""##
}
