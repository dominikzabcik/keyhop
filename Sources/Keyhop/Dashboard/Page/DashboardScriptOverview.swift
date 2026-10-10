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

  function treeIsOpen(tool) {
    if (!tool) return false;
    if (ui.treeOpen[tool.id] === undefined) ui.treeOpen[tool.id] = tool.accounts.length > 0;
    return !!ui.treeOpen[tool.id];
  }

  function treeHTML(tools) {
    return tools.map((tool) => {
      const open = treeIsOpen(tool);
      const rows = open ? tool.accounts.map((account) => {
        const lane = laneOf(account);
        return `<button class="tree-acct ${lane}" type="button" data-action="goto" data-section="accounts">${dot(lane)}<span class="nm">${esc(account.name)}</span><span class="plan">${esc(account.plan || "")}</span></button>`;
      }).join("") : "";
      const waiting = open && (data.state.adding || []).includes(tool.id)
        ? `<p class="tree-wait">Waiting for a login ${waited(tool.id)}</p>` : "";
      return `<button class="tree-tool${open ? " open" : ""}" type="button" data-action="fold" data-tool="${esc(tool.id)}" aria-expanded="${open ? "true" : "false"}">${chev()}<span class="nm">${esc(tool.name)}</span>${dot(worstLane(tool))}</button>${rows}${waiting}`;
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
    $("#content")?.classList.toggle("is-board", ui.section === "limits");
    const title = $("#title");
    if (title && data.state) title.hidden = home;
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

  function homeLogin(row, hopId) {
    const account = row.account;
    const lane = laneOf(account);
    const top = tightest(account);
    let meta = row.tool.name + (account.plan ? ` · ${account.plan}` : "");
    if (account.error) meta += " · login expired";
    else if (top) meta += ` · ${windowName(top.label)} ${Math.round(top.usedPercent)}%`;
    if (top && runsOutSoon(top)) meta += ` · runs out ${fmt.until(top.runsOutAt)}`;
    const right = account.error
      ? `<span class="hpill bad">Expired</span>`
      : lane === "needs"
        ? `<span class="hpill">Needs a hop</span>`
        : !isStatic && hopId === account.id
          ? `<button class="btn sm" type="button" data-action="switch" data-id="${esc(account.id)}">Hop</button>`
          : `<span class="pct">${top ? Math.round(top.usedPercent) + "%" : "No limit"}</span>`;
    return `<div class="hlogin" role="listitem"><button class="hlogin-main" type="button" data-action="goto" data-section="accounts">${dot(lane)}<b class="${lane === "needs" ? "warn" : ""}">${esc(account.name)}</b><span class="meta">${esc(meta)}</span></button>${right}</div>`;
  }

  function budgetStrip() {
    const alerts = (data.state.status.alerts || []).filter((alert) => /budget/i.test(alert.title));
    if (!alerts.length) return "";
    return `<section class="notices hnotices" aria-label="Budgets">${alerts.map((alert) => `<div class="notice-row">${icon("alert")}<div><b>${esc(alert.title)}</b><p>${esc(alert.body)}</p></div></div>`).join("")}</section>`;
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
    if (target.account.error) { toast(target.account.error, true); go("accounts"); return; }
    if (target.account.active) { toast(`${target.tool.name} is already on ${target.account.name}.`); return; }
    ui.homeQuery = "";
    ui.homeTool = target.tool.id;
    ui.homeAccount = target.account.id;
    fieldDash = still.matches ? 0 : 6;
    act(null, () => api("/api/switch", { id: target.account.id }), "Switching", true);
  }

  function overviewPage(tools) {
    const adding = (id) => (data.state.adding || []).includes(id);
    if (!tools.some((tool) => tool.accounts.length || adding(tool.id))) {
      const rows = tools.map((tool) => `<div class="hlogin"><div class="hlogin-main">${mark(tool.id)}<b>${esc(tool.name)}</b><span class="meta">${esc(tool.signInHint)}</span></div>${isStatic ? "" : `<button class="btn sm" type="button" data-action="add" data-tool="${esc(tool.id)}">Add</button>`}</div>`).join("");
      return { body: `<div class="hstack"><h1>Add a login.</h1><p class="hsub">No saved accounts yet. Sign in once and Keyhop keeps the login.</p></div><section class="hlogins card" aria-label="Your logins"><div class="hlogins-head"><b>Your logins</b></div>${rows}</section>` };
    }
    ensureHomePick(tools);
    const head = homeHeadline(tools);
    const rows = accountRows(tools);
    const needs = rows.filter((row) => laneOf(row.account) === "needs").sort(byPressure);
    const active = rows.filter((row) => laneOf(row.account) === "active").sort(byPressure);
    const room = rows.filter((row) => { const lane = laneOf(row.account); return lane === "room" || lane === "hot"; }).sort(byPressure);
    const quiet = rows.filter((row) => laneOf(row.account) === "quiet");
    const shown = active.slice(0, 4);
    const more = active.length - shown.length;
    const group = (label, list) => list.length ? `<div class="hgroup">${label}</div>${list.map((row) => homeLogin(row, head.target)).join("")}` : "";
    const waiting = tools.filter((tool) => adding(tool.id)).map((tool) => `<div class="hlogin"><div class="hlogin-main"><span class="pulse" aria-hidden="true"><i></i><i></i><i></i></span><b>${esc(tool.name)}</b><span class="meta">Waiting for the new login ${waited(tool.id)}</span></div>${isStatic ? "" : `<button class="btn sm ghost" type="button" data-action="add-stop" data-tool="${esc(tool.id)}">Stop</button>`}</div>`).join("");
    const quietNames = [...new Set(quiet.map((row) => row.tool.name))];
    const unset = tools.filter((tool) => !tool.accounts.length && !adding(tool.id)).map((tool) => tool.name);
    const quietVerb = quietNames.length === 1 ? "has" : "have";
    const quietLine = quietNames.length ? `<div class="hgroup">Quiet</div><p class="hquiet">${esc(nameList(quietNames))} ${quietVerb} no limit to read.</p>` : "";
    const unsetLine = unset.length ? `<p class="hquiet">Not set up: ${esc(unset.join(", "))}.</p>` : "";
    const moreLine = more ? `<p class="hquiet"><button class="htext" type="button" data-action="goto" data-section="limits">${more} more in use</button></p>` : "";
    const tool = tools.find((item) => item.id === ui.homeTool) || tools[0];
    const picked = tool?.accounts.find((account) => account.id === ui.homeAccount);
    const toolPop = ui.homeMenu === "tool" ? `<div class="hpop">${tools.map((item) => `<button type="button" data-action="home-tool" data-id="${esc(item.id)}" class="${item.id === tool?.id ? "on" : ""}">${esc(item.name)}</button>`).join("")}</div>` : "";
    const accountPop = ui.homeMenu === "account" && tool ? `<div class="hpop">${tool.accounts.map((account) => `<button type="button" data-action="home-account" data-id="${esc(account.id)}" class="${account.id === ui.homeAccount ? "on" : ""}">${esc(account.name)}<small>${account.error ? "expired" : account.limits?.length ? Math.round(maxUsed(account)) + "%" : "no limit"}</small></button>`).join("")}</div>` : "";
    const pct = picked && !picked.error && picked.limits?.length ? ` · ${Math.round(maxUsed(picked))}%` : picked?.error ? " · expired" : "";
    const composer = `<form class="hcomposer card" data-form="home-hop"><input name="query" value="${esc(ui.homeQuery || "")}" placeholder="Name a login, or hop to the one with room" autocomplete="off" aria-label="Where to hop"><div class="hcomposer-bar"><div class="hchip-wrap"><button class="hchip" type="button" data-action="home-menu" data-menu="tool">${esc(tool?.name || "Tool")}</button>${toolPop}</div><div class="hchip-wrap"><button class="hchip" type="button" data-action="home-menu" data-menu="account">${esc(picked ? picked.name : "Account")}${esc(pct)}</button>${accountPop}</div><button class="hgo" type="submit" aria-label="Go"><svg class="icon" viewBox="0 0 16 16" aria-hidden="true"><path d="M8 12.5V3.5"/><path d="M4.5 7 8 3.5 11.5 7"/></svg></button></div></form>`;
    return { body: `<div class="hstack"><h1>${esc(head.title)}</h1><p class="hsub">${esc(head.sub)}</p>${head.note ? `<p class="hnote">${esc(head.note)}</p>` : ""}</div>${composer}<section class="hlogins card" aria-label="Your logins"><div class="hlogins-head"><b>Your logins</b><button class="htext" type="button" data-action="goto" data-section="limits">Limits</button></div><div role="list">${waiting}${group("Needs a hop", needs)}${group("In use", shown)}${moreLine}${group("Room", room)}${quietLine}${unsetLine}</div></section>${budgetStrip()}` };
  }

  function limitCard(tool, account) {
    const lane = laneOf(account);
    const top = tightest(account);
    const alt = alternative(tool, account);
    const line = account.error ? account.error : top ? `${windowName(top.label)} at ${Math.round(top.usedPercent)}%. ${limitFoot(top)}`.trim() : (tool.limitsNote || "No limit to read.");
    const hopBtn = !isStatic && alt && !account.error ? `<button class="btn sm" type="button" data-action="switch" data-id="${esc(alt.id)}">Hop to ${esc(alt.name)}</button>` : "";
    const bar = top ? progress(top.usedPercent, top.pace, undefined, `board:${account.id}:${top.label}`) : "";
    return `<article class="kcard ${lane}"><header>${dot(lane)}<b>${esc(account.name)}</b><span class="pct">${top ? Math.round(top.usedPercent) + "%" : ""}</span></header><p class="kmeta">${esc(tool.name)}${account.plan ? ` · ${esc(account.plan)}` : ""}</p><p class="kline">${esc(line)}</p>${bar}<div class="kacts"><button class="btn sm ghost" type="button" data-action="goto" data-section="accounts">Open</button>${hopBtn}</div></article>`;
  }

  function limitsPage(tools) {
    const rows = accountRows(tools);
    const cols = [
      ["needs", "Needs a hop", (lane) => lane === "needs"],
      ["active", "In use", (lane) => lane === "active"],
      ["room", "Room", (lane) => lane === "room" || lane === "hot"],
      ["quiet", "Quiet", (lane) => lane === "quiet"],
    ];
    const board = cols.map(([id, label, match]) => {
      const list = rows.filter((row) => match(laneOf(row.account))).sort(byPressure);
      const cards = list.map((row) => limitCard(row.tool, row.account)).join("");
      return `<section class="kcol"><h2>${dot(id)}<span>${label}</span><span class="n" aria-hidden="true">${list.length}</span></h2><div class="kcol-body">${cards || `<p class="kempty">Nothing here</p>`}</div></section>`;
    }).join("");
    return { body: `<p class="knote">Every saved login, by how close it is to a wall.</p><div class="kscroll"><div class="kboard">${board}</div></div>` };
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
