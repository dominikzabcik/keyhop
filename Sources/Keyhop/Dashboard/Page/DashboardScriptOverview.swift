import Foundation

/// The home: the headline, the hop composer, the logins list and the Limits board.
extension DashboardPage {
    static let scriptOverview = ##"""
  // MARK: Overview

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

  function runsOutSoon(limit) {
    if (!limit?.runsOutAt) return false;
    const eta = new Date(limit.runsOutAt);
    if (!(eta > Date.now())) return false;
    if (limit.resetsAt && eta >= new Date(limit.resetsAt)) return false;
    return true;
  }

  // needs: an error, a window at 85%, or one that runs out before it resets.
  // quiet: nothing to read. active: the login in use, still under that line.
  function laneOf(account) {
    if (account.error) return "needs";
    const limits = account.limits || [];
    if (!limits.length) return "quiet";
    const used = maxUsed(account);
    if (used >= 85 || limits.some(runsOutSoon)) return "needs";
    if (account.active) return "active";
    if (used >= 60) return "hot";
    return "room";
  }

  function worstLane(tool) {
    const order = ["needs", "hot", "active", "room", "quiet"];
    const lanes = tool.accounts.map(laneOf);
    if (!lanes.length) return "quiet";
    return lanes.sort((a, b) => order.indexOf(a) - order.indexOf(b))[0];
  }

  function accountRows(tools) {
    const rows = [];
    for (const tool of tools) for (const account of tool.accounts) rows.push({ tool, account });
    return rows;
  }

  function byPressure(a, b) {
    const score = (row) => (row.account.error ? -1 : maxUsed(row.account));
    return score(b) - score(a);
  }

  function bestHop(tools) {
    let best = null;
    for (const tool of tools) {
      const active = tool.accounts.find((a) => a.active);
      const alt = alternative(tool, active);
      if (!active || !alt) continue;
      const gap = maxUsed(active) - maxUsed(alt);
      if (!best || gap > best.gap) best = { tool, from: active, to: alt, gap };
    }
    return best;
  }

  function stuckAccounts(tools) {
    return accountRows(tools).filter((row) => laneOf(row.account) === "needs" && !alternative(row.tool, row.account));
  }

  function serviceFor(toolId) {
    return (data.services || []).find((s) => s.tool === toolId && servicePhrase[s.level]) || null;
  }

  function outageSentence(service) {
    const phrase = servicePhrase[service.level];
    if (!phrase) return "";
    const advice = service.level === "maintenance" ? "" : " Every account is affected, so hopping won't help.";
    return `${toolName(service.tool)} ${phrase}.${advice}`;
  }

  const chev = () => `<svg class="chev" viewBox="0 0 16 16" aria-hidden="true"><path d="M6 4.5 10 8 6 11.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  const dot = (kind) => `<i class="ldot ${kind}" aria-hidden="true"></i>`;

  // The sidebar's glance: each tool's login in use and how full its tightest window is.
  function treeHTML(tools) {
    return tools.filter((tool) => tool.accounts.length || (data.state.adding || []).includes(tool.id)).map((tool) => {
      const account = tool.accounts.find((item) => item.active);
      const waiting = (data.state.adding || []).includes(tool.id);
      const lane = account ? laneOf(account) : "quiet";
      const top = account ? tightest(account) : null;
      const pct = top ? Math.round(top.usedPercent) : null;
      const ring = pct == null ? "" : `<svg class="side-ring ${lane}" viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="7.5"/><circle class="fill" cx="10" cy="10" r="7.5" pathLength="100" stroke-dasharray="${Math.min(100, pct)} 100"/></svg>`;
      const detail = waiting ? `Waiting for a login ${waited(tool.id)}` : account ? esc(account.name) : "None in use";
      return `<button class="side-login ${lane}" type="button" data-action="side-tool" data-value="${esc(tool.id)}" aria-pressed="${ui.section === "limits" && ui.quotaTool === tool.id}" title="${esc(tool.name)}${account ? ` · ${esc(account.name)}` : ""}${pct != null ? ` · ${pct}%` : ""}">${mark(tool.id)}<span class="nm"><b>${esc(tool.name)}</b><small>${detail}</small></span>${pct != null ? `<span class="side-pct">${pct}%</span>${ring}` : ""}</button>`;
    }).join("");
  }

  function petFootHTML() {
    const claim = currentClaim();
    const kick = claim && !claim.claimed && claim.active && claim.today
      ? `<button class="btn sm" type="button" data-action="streak-claim">Claim</button>` : "";
    if (!data.pet && !kick) return "";
    const title = data.pet
      ? (data.pet.lineageName ? `${data.pet.stageName} · ${data.pet.lineageName}` : data.pet.stageName)
      : "Streak";
    const note = data.pet && data.pet.next ? `${fmt.tokens(data.pet.next.tokens)} to ${data.pet.next.label}`
      : data.pet ? "Monument" : (claim && claim.today ? claim.today.name : "");
    return `<span><b>${esc(title)}</b>${note ? `<small>${esc(note)}</small>` : ""}</span>${kick}`;
  }

  let treeStamp = "";
  function renderChrome() {
    const home = ui.section === "overview";
    $("#content")?.classList.toggle("is-home", home);
    const title = $("#title");
    if (title) title.hidden = false;
    const tools = data.state?.status?.tools || [];
    const needs = tools.reduce((sum, tool) => sum + tool.accounts.filter((account) => laneOf(account) === "needs").length, 0);
    const badge = $("#limits-count");
    if (badge) {
      badge.hidden = needs === 0;
      badge.textContent = needs ? String(needs) : "";
    }
    const tree = $("#tree");
    if (tree && data.state) {
      const html = treeHTML(tools);
      if (treeStamp !== html) {
        const top = tree.scrollTop;
        tree.innerHTML = html;
        tree.scrollTop = top;
        treeStamp = html;
      }
    }
    const petHost = $("#pet-foot");
    if (petHost) {
      const html = data.state ? petFootHTML() : "";
      petHost.hidden = !html;
      if (petHost.innerHTML !== html) petHost.innerHTML = html;
    }
    renderStatus(needs);
    syncField();
  }

  function renderStatus(needs) {
    const status = data.state?.status;
    const todayBtn = $("#status-today");
    if (todayBtn) todayBtn.textContent = status ? `${fmt.tokens(status.today.tokens)} today` : "";
    const themeBtn = $("#status-theme");
    if (themeBtn) themeBtn.textContent = ui.theme === "day" ? "Day" : "Night";
    const streakEl = $("#status-streak");
    const streak = (data.usage["week:all"] || data.usage["today:all"])?.streak;
    if (streakEl) {
      streakEl.hidden = !streak;
      if (streak) streakEl.textContent = `${streak.current} day streak`;
    }
    const needsBtn = $("#status-needs");
    const clear = $("#status-clear");
    if (needsBtn && clear) {
      if (!data.state) {
        needsBtn.hidden = true;
        clear.hidden = true;
      } else if (needs > 0) {
        needsBtn.hidden = false;
        needsBtn.innerHTML = `<i class="ldot needs" aria-hidden="true"></i>${needs} need${needs === 1 ? "s" : ""} a hop`;
        clear.hidden = true;
      } else {
        needsBtn.hidden = true;
        clear.hidden = false;
      }
    }
    const out = $("#status-outage");
    const troubled = (data.services || []).find((service) => serviceShort[service.level]);
    if (out) {
      out.hidden = !troubled;
      if (troubled) {
        const incident = troubled.incidents && troubled.incidents[0];
        out.href = incident?.link || troubled.page || "#";
        out.textContent = `${toolName(troubled.tool)} ${serviceShort[troubled.level]}`;
      }
    }
  }

  function homeHeadline(tools) {
    const hop = bestHop(tools);
    const wall = stuckAccounts(tools).find((row) => !row.account.error) || null;
    const outage = (wall && serviceFor(wall.tool.id)) || (data.services || []).find((service) => servicePhrase[service.level]) || null;
    const note = outage ? outageSentence(outage) : "";
    if (hop) {
      const wallNote = wall ? `${wall.tool.name} is at ${Math.round(maxUsed(wall.account))}% and has no other login.` : "";
      return {
        title: `${hop.to.name} still has room.`,
        sub: `${hop.tool.name} ${hop.from.name} is in use at ${Math.round(maxUsed(hop.from))}%. ${hop.to.name} is at ${Math.round(maxUsed(hop.to))}%.`,
        note: note || wallNote,
        target: hop.to.id,
      };
    }
    if (wall) {
      const top = tightest(wall.account);
      const when = top && runsOutSoon(top)
        ? `The ${windowName(top.label).toLowerCase()} window runs out around ${fmt.clock(top.runsOutAt)}. `
        : "";
      return {
        title: `${wall.tool.name} is at ${Math.round(maxUsed(wall.account))}%.`,
        sub: `${when}There is no other login to hop to.`,
        note,
        target: null,
      };
    }
    return { title: "Every login in use has room.", sub: "Nothing is close to a limit.", note, target: null };
  }

  function ensureHomePick(tools) {
    const tool = tools.find((item) => item.id === ui.homeTool);
    if (tool && tool.accounts.some((account) => account.id === ui.homeAccount)) return;
    const hop = bestHop(tools);
    if (hop) { ui.homeTool = hop.tool.id; ui.homeAccount = hop.to.id; return; }
    const withAccounts = tools.find((item) => item.accounts.length) || tools[0];
    ui.homeTool = withAccounts?.id || "";
    const list = withAccounts?.accounts || [];
    const room = list.filter((account) => !account.error).sort((a, b) => maxUsed(a) - maxUsed(b))[0];
    ui.homeAccount = (room || list[0])?.id || "";
  }

  function nameList(names) {
    if (names.length < 2) return names.join("");
    return `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
  }

  // Home's list of what wants a decision now: a login at its wall, one signed out, an outage, a budget.
  function attentionItems(tools) {
    const items = [];
    for (const row of accountRows(tools).sort(byPressure)) {
      const { tool, account } = row;
      if (account.error) {
        items.push({ tone: "bad", title: `${account.name} is signed out`, text: `${tool.name}. ${account.error}`,
          action: isStatic || account.active ? `<button class="btn sm secondary" type="button" data-action="goto" data-section="limits">Open</button>`
            : `<button class="btn sm secondary" type="button" data-action="switch" data-id="${esc(account.id)}">Switch and sign in</button>` });
        continue;
      }
      if (!account.active || laneOf(account) !== "needs") continue;
      const top = tightest(account);
      const alt = alternative(tool, account);
      const timing = top && runsOutSoon(top) ? `${windowName(top.label)} runs out around ${fmt.clock(top.runsOutAt)}.`
        : top?.resetsAt ? `${windowName(top.label)} resets in ${fmt.until(top.resetsAt)}.` : "";
      items.push({ tone: "warn", title: `${tool.name} is at ${Math.round(maxUsed(account))}% on ${account.name}`,
        text: `${timing}${alt ? ` ${alt.name} is at ${Math.round(maxUsed(alt))}%.` : " There is no other login to hop to."}`.trim(),
        action: isStatic ? "" : alt ? `<button class="btn sm" type="button" data-action="switch" data-id="${esc(alt.id)}">Hop to ${esc(alt.name)}</button>`
          : `<button class="btn sm ghost" type="button" data-action="add" data-tool="${esc(tool.id)}">${icon("plus")}Add a login</button>` });
    }
    for (const service of data.services || []) {
      if (!servicePhrase[service.level]) continue;
      const incident = service.incidents && service.incidents[0];
      items.push({ tone: service.level === "maintenance" ? "" : "warn", title: `${toolName(service.tool)} ${serviceShort[service.level]}`,
        text: incident?.title || outageSentence(service),
        action: incident?.link || service.page ? `<a class="btn sm ghost" href="${esc(incident?.link || service.page)}" target="_blank" rel="noopener">Status page</a>` : "" });
    }
    for (const alert of (data.state.status.alerts || []).filter((item) => /budget/i.test(item.title))) {
      items.push({ tone: "warn", title: alert.title, text: alert.body, action: `<button class="btn sm ghost" type="button" data-action="goto" data-section="budgets">Budgets</button>` });
    }
    return items;
  }

  function attentionCard(tools) {
    const items = attentionItems(tools);
    const rows = items.map((item) => `<div class="arow ${item.tone}" role="listitem"><i class="ldot ${item.tone === "bad" ? "needs bad" : item.tone === "warn" ? "needs" : "quiet"}" aria-hidden="true"></i><div class="arow-copy"><b>${esc(item.title)}</b>${item.text ? `<p>${esc(item.text)}</p>` : ""}</div>${item.action || ""}</div>`).join("");
    return `<section class="card attention" aria-label="Needs your attention">
      <div class="card-head"><h2>Needs your attention</h2>${items.length ? `<span class="count${items.some((item) => item.tone) ? " hot" : ""}">${items.length}</span>` : ""}</div>
      ${rows ? `<div class="alist" role="list">${rows}</div>` : `<p class="aclear">${icon("hop")}Nothing needs you. Every login in use has room.</p>`}
    </section>`;
  }

  // The logins in use right now, one per tool, with the window closest to its limit.
  function inUseCard(tools, hopId) {
    const rows = tools.filter((tool) => tool.accounts.length).map((tool) => {
      const account = tool.accounts.find((item) => item.active) || null;
      if (!account) return "";
      const lane = laneOf(account);
      const top = tightest(account);
      const right = !isStatic && hopId && tool.accounts.some((item) => item.id === hopId)
        ? `<button class="btn sm" type="button" data-action="switch" data-id="${esc(hopId)}">Hop</button>`
        : top ? `<span class="iu-pct ${lane}">${Math.round(top.usedPercent)}%</span>` : `<span class="iu-pct subtle">No limit</span>`;
      return `<div class="iu-row" role="listitem">${mark(tool.id)}<button class="iu-main" type="button" data-action="goto" data-section="limits"><b>${esc(tool.name)}</b><span>${esc(account.name)}${top ? ` · ${esc(windowName(top.label))}` : ""}</span></button>
        <div class="iu-bar">${top ? progress(top.usedPercent, top.pace, undefined, `home:${account.id}`) : ""}</div>${right}</div>`;
    }).join("");
    const pool = quotaPool("all");
    const pooled = pool && pool.accounts ? `<span class="hint">${Math.round(pool.remaining)}% of ${Math.round(pool.capacity)}% left in all</span>` : "";
    return `<section class="card inuse" aria-label="Your logins">
      <div class="card-head"><h2>In use</h2>${pooled}<button class="htext" type="button" data-action="goto" data-section="limits">All limits</button></div>
      <div class="iu-list" role="list">${rows || `<p class="empty">No login is in use.</p>`}</div>
    </section>`;
  }

  // The week at a glance: four figures, each against the same span before it.
  function homeOverview() {
    const range = ui.homeRange;
    const usage = data.usage[`${range}:all`];
    const picker = tabs("home-range", [["today", "Today"], ["week", "7 days"], ["30d", "30 days"]].filter(([value]) => !isStatic || data.usage[`${value}:all`]), range);
    const head = `<div class="section-head"><h2>Overview</h2>${picker}</div>`;
    if (!usage) {
      const error = data.usageErrors[`${range}:all`];
      return `${head}<section class="card">${error ? `<p class="empty">${esc(error)}</p>` : loading("Reading usage", "empty")}</section>`;
    }
    const t = usage.total, p = usage.previous, compared = usage.compared !== false;
    const span = { today: "yesterday", week: "the 7 days before", "30d": "the 30 days before" }[range] || "the period before";
    const hitOf = (x) => { const side = x.input + x.cacheRead + x.cacheWrite + (x.cacheWrite1h || 0); return side ? x.cacheRead / side : null; };
    const hit = hitOf(t), hitBefore = hitOf(p);
    const points = hit != null && hitBefore != null && compared ? Math.round((hit - hitBefore) * 100) : null;
    const tile = (label, value, count, format, change, note) => `<div class="hstat">
        <span class="hstat-label">${label}</span>
        <b class="hstat-value"${count != null ? ` data-count="${count}" data-count-key="home:${label}:${range}" data-format="${format}" data-count-intro` : ""}>${value}</b>
        <span class="hstat-foot">${change || ""}${note ? `<span>${note}</span>` : ""}</span>
      </div>`;
    const vs = compared ? `vs ${span}` : "";
    const tiles = `<div class="hstats">
      ${tile("Tokens", fmt.tokens(t.tokens), t.tokens, "tokens", compared ? fmt.change(t.tokens, p.tokens, fmt.tokens(p.tokens)) : "", vs)}
      ${tile("API value", fmt.usd(t.cost), t.cost, "usd", compared ? fmt.change(t.cost, p.cost, fmt.usd(p.cost)) : "", vs)}
      ${tile("Requests", fmt.count(t.requests), t.requests, "count", compared ? fmt.change(t.requests, p.requests, fmt.count(p.requests)) : "", vs)}
      ${tile("Cache hit", hit != null ? `${Math.round(hit * 100)}%` : "None", hit != null ? hit * 100 : null, "pct", points != null ? `<span class="mono ${points > 0 ? "up" : points < 0 ? "down" : "subtle"}">${points > 0 ? "+" : ""}${points} pts</span>` : "", usage.cacheSavings > 0 ? `${fmt.usd(usage.cacheSavings)} saved` : vs)}
    </div>`;
    return `${head}${tiles}${activityCard(usage)}`;
  }

  // The last 26 weeks, day by day, and the streaks and habits in them.
  function activityCard(usage) {
    const days = usage.heatmap || [];
    if (!days.length) return "";
    const s = usage.streak;
    const months = new Map(), weekdays = Array.from({ length: 7 }, () => ({ sum: 0, n: 0 }));
    for (const day of days) {
      const date = new Date(day.day + "T00:00:00");
      const key = day.day.slice(0, 7);
      months.set(key, (months.get(key) || 0) + day.tokens);
      if (day.tokens > 0) { weekdays[date.getDay()].sum += day.tokens; weekdays[date.getDay()].n += 1; }
    }
    const topMonth = [...months.entries()].sort((a, b) => b[1] - a[1])[0];
    const topDay = weekdays.map((w, i) => ({ i, avg: w.n ? w.sum / w.n : 0 })).sort((a, b) => b.avg - a.avg)[0];
    const dayName = topDay && topDay.avg ? new Intl.DateTimeFormat(undefined, { weekday: "long" }).format(new Date(2024, 0, 7 + topDay.i)) : "";
    const monthName = topMonth && topMonth[1] ? fmt.day(topMonth[0] + "-01T00:00:00", { month: "long", year: "numeric" }) : "";
    const fact = (label, value, note) => `<div class="hstreak"><span class="hstat-label">${label}</span><b>${value}</b>${note ? `<span class="hstat-foot">${note}</span>` : ""}</div>`;
    const plural = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;
    return `<section class="card activity">
      <div class="card-head"><h2>${s.activeDays} active days <span class="subtle">in the last 26 weeks</span></h2><span class="scale">Less <i style="background:hsl(var(--on) / .05)"></i><i style="background:hsl(var(--on) / .18)"></i><i style="background:hsl(var(--on) / .36)"></i><i style="background:hsl(var(--on) / .6)"></i><i style="background:hsl(var(--on) / .9)"></i> More</span></div>
      <div class="card-body chart activity-heat">${heatmap(days, "full")}</div>
      <div class="hstreaks">
        ${fact("Current streak", plural(s.current, "day"), s.current ? "Any usage keeps it going" : "Use any tool today to start one")}
        ${fact("Longest streak", plural(s.longest, "day"), "")}
        ${fact("Most active month", esc(monthName || "Not yet"), topMonth && topMonth[1] ? `${fmt.tokens(topMonth[1])} tokens` : "")}
        ${fact("Most active day", dayName ? `${esc(dayName)}s` : "Not yet", topDay && topDay.avg ? `${fmt.tokens(topDay.avg)} on average` : "")}
      </div>
    </section>`;
  }

  function homeHop(query) {
    if (isStatic) { toast("This is a saved page, so it can't switch logins."); return; }
    const tools = data.state?.status.tools || [];
    const words = String(query || "").trim().toLowerCase();
    let target = null;
    if (words) {
      const hits = [];
      for (const tool of tools) for (const account of tool.accounts) {
        if (`${account.name} ${account.email || ""} ${tool.name}`.toLowerCase().includes(words)) hits.push({ tool, account });
      }
      target = hits.find((hit) => !hit.account.active && !hit.account.error) || hits[0] || null;
    } else {
      for (const tool of tools) {
        const account = tool.accounts.find((item) => item.id === ui.homeAccount);
        if (account) target = { tool, account };
      }
    }
    if (!target) { toast(words ? "No login matches that." : "Name a saved login.", true); return; }
    if (target.account.error) { toast(target.account.error, true); go("limits"); return; }
    if (target.account.active) { toast(`${target.tool.name} is already on ${target.account.name}.`); return; }
    ui.homeQuery = "";
    ui.homeTool = target.tool.id;
    ui.homeAccount = target.account.id;
    fieldDash = still.matches ? 0 : 6;
    act(null, () => api("/api/switch", { id: target.account.id }), "Switching", true);
  }

  function overviewPage(tools) {
    const adding = (id) => (data.state.adding || []).includes(id);
    const today = fmt.day(new Date(), { weekday: "long", month: "long", day: "numeric" });
    const hero = (title, sub, note) => `<section class="hero" aria-label="Today">
      <div data-hero></div>
      <div class="hero-copy"><p class="hero-date">${esc(today)}</p><h2 class="hero-title">${esc(title)}</h2>${sub ? `<p class="hsub">${esc(sub)}</p>` : ""}${note ? `<p class="hnote">${esc(note)}</p>` : ""}</div>
      ${isStatic ? "" : `<button class="hero-btn" type="button" data-action="wallpaper">Wallpaper</button>`}
    </section>`;
    if (!tools.some((tool) => tool.accounts.length || adding(tool.id))) {
      const rows = tools.map((tool) => `<div class="row setup-row"><div class="account-id">${mark(tool.id)}<div class="account-copy"><div class="account-name"><b>${esc(tool.name)}</b></div><div class="account-line">${esc(tool.signInHint)}</div></div></div>${isStatic ? "" : `<button class="btn sm" type="button" data-action="add" data-tool="${esc(tool.id)}">Add</button>`}</div>`).join("");
      return { body: `${hero("Add a login.", "No saved accounts yet. Sign in once and Keyhop keeps the login.", "")}<section class="card" aria-label="Your logins"><div class="card-head"><h2>Your logins</h2></div><div class="list">${rows}</div></section>` };
    }
    ensureHomePick(tools);
    const head = homeHeadline(tools);
    const tool = tools.find((item) => item.id === ui.homeTool) || tools[0];
    const picked = tool?.accounts.find((account) => account.id === ui.homeAccount);
    const toolPop = ui.homeMenu === "tool" ? `<div class="hpop">${tools.map((item) => `<button type="button" data-action="home-tool" data-id="${esc(item.id)}" class="${item.id === tool?.id ? "on" : ""}">${esc(item.name)}</button>`).join("")}</div>` : "";
    const accountPop = ui.homeMenu === "account" && tool ? `<div class="hpop">${tool.accounts.map((account) => `<button type="button" data-action="home-account" data-id="${esc(account.id)}" class="${account.id === ui.homeAccount ? "on" : ""}">${esc(account.name)}<small>${account.error ? "expired" : account.limits?.length ? Math.round(maxUsed(account)) + "%" : "no limit"}</small></button>`).join("")}</div>` : "";
    const pct = picked && !picked.error && picked.limits?.length ? ` · ${Math.round(maxUsed(picked))}%` : picked?.error ? " · expired" : "";
    const composer = `<form class="hcomposer card" data-form="home-hop"><input name="query" value="${esc(ui.homeQuery || "")}" placeholder="Name a login, or hop to the one with room" autocomplete="off" aria-label="Where to hop"><div class="hcomposer-bar"><div class="hchip-wrap"><button class="hchip" type="button" data-action="home-menu" data-menu="tool">${esc(tool?.name || "Tool")}</button>${toolPop}</div><div class="hchip-wrap"><button class="hchip" type="button" data-action="home-menu" data-menu="account">${esc(picked ? picked.name : "Account")}${esc(pct)}</button>${accountPop}</div><button class="hgo" type="submit" aria-label="Go"><svg class="icon" viewBox="0 0 16 16" aria-hidden="true"><path d="M8 12.5V3.5"/><path d="M4.5 7 8 3.5 11.5 7"/></svg></button></div></form>`;
    // An outage is listed under Needs your attention, so the wallpaper keeps to the headline.
    return { body: `${hero(head.title, head.sub, "")}${composer}<div class="home-grid">${attentionCard(tools)}${inUseCard(tools, head.target)}</div>${homeOverview()}` };
  }

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
      return `<section class="card pet-card">${drawn.svg}<div><h2>${esc(drawn.caption)}</h2><p>${next}</p></div>${claimKick(currentClaim())}</section>`;
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
