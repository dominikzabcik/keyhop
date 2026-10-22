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

  // Keyhop shows what is, not guesses about when a limit will run out.
  const runsOutSoon = () => false;

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

  // The hop most worth making now: a tool whose login in use needs one and has somewhere to go.
  function bestHop(tools) {
    let best = null;
    for (const tool of tools) {
      const active = tool.accounts.find((a) => a.active);
      if (!active || laneOf(active) !== "needs" || active.error) continue;
      const alt = alternative(tool, active);
      if (!alt) continue;
      const gap = leftOf(alt) - (leftOf(active) ?? 0);
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
    const advice = service.level === "maintenance" ? "" : " Every account is affected, so hopping won't help.";
    return `${toolName(service.tool)} ${phrase}.${advice}`;
  }

  const chev = () => `<svg class="chev" viewBox="0 0 16 16" aria-hidden="true"><path d="M6 4.5 10 8 6 11.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  const dot = (kind) => `<i class="ldot ${kind}" aria-hidden="true"></i>`;

  // The sidebar's glance: each tool's login in use and what is left on its tightest window.
  // Tools without a limit to read are counted in Usage, so they are not listed here.
  function treeHTML(tools) {
    return tools.filter((tool) => tool.accounts.length || (data.state.adding || []).includes(tool.id)).map((tool) => {
      const account = tool.accounts.find((item) => item.active);
      const waiting = (data.state.adding || []).includes(tool.id);
      const top = account ? tightest(account) : null;
      if (!top && !waiting && !account?.error) return "";
      const left = account ? leftOf(account) : null;
      const label = top ? `${tool.name} · ${windowName(top.label).replace("-hour", "h").replace("Weekly", "week")}` : tool.name;
      const side = waiting ? waited(tool.id) : account?.error ? `<span class="side-when bad">Signed out</span>` : "";
      const tone = account?.error || (left != null && left <= 15) ? "bad" : left != null && left <= 40 ? "warn" : "";
      return `<button class="side-login ${tone}" type="button" data-action="side-tool" data-value="${esc(tool.id)}" aria-pressed="${ui.section === "limits" && ui.quotaTool === tool.id}" title="${esc(tool.name)}${account ? ` · ${esc(account.name)}` : ""}${left != null ? ` · ${left}% left` : ""}">
        <span class="side-top">${mark(tool.id)}<span class="nm">${esc(label)}</span>${side}${left != null ? `<span class="side-pct">${left}%</span>` : ""}</span>
        ${left != null ? `<span class="side-bar"><span style="width:${left}%" data-grow="side:${esc(tool.id)}"></span></span>` : ""}
      </button>`;
    }).join("");
  }

  let treeStamp = "";
  function renderChrome() {
    const home = ui.section === "overview";
    $("#content")?.classList.toggle("is-home", home);
    const title = $("#title");
    if (title) title.hidden = false;
    const tools = data.state?.status?.tools || [];
    const needs = data.state ? needsCount(tools) : 0;
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
    const logins = tools.reduce((sum, tool) => sum + tool.accounts.length, 0);
    const line = $("#brand-line");
    if (line && data.state) line.textContent = `${logins} login${logins === 1 ? "" : "s"} · ${tools.filter((tool) => tool.accounts.length).length} tools`;
    const cloud = data.state?.cloud;
    const login = cloud?.linked && cloud.login ? cloud.login : "";
    const avatar = $("#side-avatar");
    if (avatar) avatar.textContent = login ? login.slice(0, 2).toUpperCase() : "K";
    const name = $("#side-name"), sub = $("#side-sub");
    if (name) name.textContent = login ? `@${login}` : "Settings";
    if (sub) sub.textContent = "Settings";
    const live = $("#side-live");
    const read = data.state?.status?.refreshedAt;
    if (live) {
      const fresh = !isStatic && read && Date.now() - new Date(read) < 15 * 60_000;
      live.hidden = !read;
      live.className = `side-live${fresh ? " on" : ""}`;
      live.innerHTML = fresh ? `<i aria-hidden="true"></i>Live` : read ? esc(`read ${fmt.relative(read)}`) : "";
    }
    renderStatus();
    syncField();
  }

  // The top bar's field switch, and a word when a tool's service is in trouble. What needs you is
  // counted on Limits in the sidebar.
  function renderStatus() {
    const themeBtn = $("#theme");
    if (themeBtn) {
      const day = ui.theme === "day";
      themeBtn.setAttribute("aria-label", day ? "Show the field by night" : "Show the field by day");
      themeBtn.title = day ? "Night" : "Day";
      themeBtn.querySelector("use")?.setAttribute("href", day ? "#i-moon" : "#i-sun");
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
  }

  // What the pet says: the hop worth making, if there is one. A login with nowhere to go is counted on Limits.
  function homeHeadline(tools) {
    const hop = bestHop(tools);
    if (hop) return { title: `${hop.tool.name} has ${leftOf(hop.from)}% left.`, sub: `${hop.to.name} has ${leftOf(hop.to)}%.`, target: hop.to.id };
    return null;
  }

  function nameList(names) {
    if (names.length < 2) return names.join("");
    return `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
  }

  // The logins that want a decision now: one in use that is low, or one signed out. Limits in the
  // sidebar counts them.
  function needsCount(tools) {
    let count = 0;
    for (const tool of tools) {
      const active = tool.accounts.find((account) => account.active);
      if (active && !active.error && laneOf(active) === "needs") count += 1;
      count += tool.accounts.filter((account) => account.error).length;
    }
    return count;
  }

  // Tools on Home share one blue, lightest for the largest share.
  const SHARE_BLUES = ["#a8cefc", "#80b7fb", "#60a5fa", "#4d84c8", "#3d6aa0", "#2e4f78"];
  const HOME_RANGES = [["today", "Day"], ["week", "Week"], ["month", "Month"], ["all", "All"]];
  const PET_STAGES = [["speck", "Speck", 0], ["hatch", "Hatch", 1e6], ["frame", "Frame", 50e6], ["bulk", "Bulk", 500e6], ["mass", "Mass", 5e9], ["monument", "Monument", 25e9]];

  function homeTotal(usage) {
    const range = ui.homeRange, t = usage.total, p = usage.previous, compared = usage.compared !== false;
    const now = new Date();
    const label = { today: "Today", week: "7 days", month: "This month", all: "All time" }[range] || usage.title;
    const title = { today: "Today, so far", week: "The last 7 days", month: "This month, so far", all: "Everything so far" }[range] || usage.title;
    const span = { today: "yesterday", week: "the 7 days before", month: "the month before" }[range] || "the period before";
    let change = "";
    // Only whole spans are compared: a day or a month so far against a whole one says nothing.
    if (range === "week" && compared && p?.tokens) {
      const pct = Math.round(((t.tokens - p.tokens) / p.tokens) * 100);
      change = Math.abs(pct) >= 900 ? "" : `<span class="hchange ${pct >= 0 ? "up" : "down"}">${pct >= 0 ? "↑" : "↓"} ${Math.abs(pct)}% on ${esc(span)}</span>`;
    }
    const tools = (usage.tools || []).filter((tool) => tool.figures.tokens > 0).sort((a, b) => b.figures.tokens - a.figures.tokens);
    const sum = tools.reduce((n, tool) => n + tool.figures.tokens, 0) || 1;
    const shares = tools.map((tool, i) => ({ tool, share: tool.figures.tokens / sum, color: SHARE_BLUES[Math.min(i, SHARE_BLUES.length - 1)] }));
    const bar = shares.map((x, i) => `<span style="flex-grow:${(x.share * 1000).toFixed(0)};background:${x.color}" data-grow="home-mix:${esc(x.tool.id)}" data-grow-prop="flexGrow" title="${esc(x.tool.name)} · ${Math.round(x.share * 100)}%"></span>`).join("");
    const pct = (share) => share > 0 && share < .01 ? "<1%" : `${Math.round(share * 100)}%`;
    const tiles = shares.slice(0, 6).map((x) => `<div class="htile"><span class="htile-name">${esc(x.tool.name)}</span><span class="htile-pct"><span style="color:${x.color}">${mark(x.tool.id)}</span>${pct(x.share)}</span><span class="htile-foot">${fmt.tokens(x.tool.figures.tokens)} tokens</span></div>`).join("");
    return `<section class="card htotal" aria-labelledby="total-h">
      <div class="htotal-head"><span class="htotal-title"><span class="lab">${esc(range === "today" ? fmt.day(now, { weekday: "long", month: "long", day: "numeric" }) : label)}</span><h2 id="total-h">${esc(title)}</h2></span>${change}</div>
      <div class="htotal-figure"><b class="hbig" data-count="${t.tokens}" data-count-key="home:tokens:${range}" data-format="count" data-count-intro>${fmt.count(t.tokens)}</b><span class="hvalue"><b class="money" data-count="${t.cost}" data-count-key="home:cost:${range}" data-format="usdExact">${FORMATS.usdExact(t.cost)}</b><span>tokens · value at API prices</span></span></div>
      ${bar ? `<div class="hmix" role="img" aria-label="Share of tokens by tool">${bar}</div>` : ""}
      ${tiles ? `<div class="htiles">${tiles}</div>` : ""}
    </section>`;
  }

  // Tokens per step of the range: the 7 days before sit dimmed behind the last 7, and today is blue.
  function homeTrend(usage) {
    const range = ui.homeRange;
    const sumOf = (bucket) => Object.values(bucket.values || {}).reduce((n, v) => n + (v.tokens || 0), 0);
    let bars = (usage.buckets || []).map((bucket) => ({ start: bucket.start, tokens: sumOf(bucket), now: false, before: false }));
    let unit = { hour: "hour", day: "day", week: "week", month: "month" }[usage.bucket] || "day";
    if (range === "week") {
      const days = usage.heatmap || [];
      const firstDay = localDay(new Date(usage.start));
      const at = days.findIndex((d) => d.day === firstDay);
      const before = at >= 7 ? days.slice(at - 7, at) : [];
      bars = [...before.map((d) => ({ start: d.day + "T00:00:00", tokens: d.tokens, before: true })), ...bars];
    }
    if (!bars.length) return "";
    // The bucket holding this moment is now; later ones are still to come.
    const at = Date.now();
    let current = bars.findIndex((b, i) => !b.before && new Date(b.start).getTime() <= at && (i === bars.length - 1 || new Date(bars[i + 1].start).getTime() > at));
    if (current < 0) current = bars.length - 1;
    bars[current].now = true;
    bars.forEach((b, i) => { b.later = i > current; });
    const peak = Math.max(...bars.map((b) => b.tokens), 1);
    const step = Math.pow(10, Math.floor(Math.log10(peak)));
    const top = Math.ceil(peak / step) * step;
    const label = (bucket) => unit === "hour" ? fmt.day(bucket.start, { hour: "numeric" }) : unit === "month" ? fmt.day(bucket.start, { month: "short", year: "2-digit" }) : fmt.day(bucket.start, { month: "short", day: "numeric" });
    const cols = bars.map((b, i) => `<span class="hcol"${tipAttr(label(b), [["Tokens", fmt.tokens(b.tokens)]])}><span class="hbar${b.before ? " before" : ""}${b.now ? " now" : ""}${b.later ? " later" : ""}" style="height:${Math.max(b.tokens ? 2 : 0, (b.tokens / top) * 100).toFixed(1)}%"></span></span>`).join("");
    const nowLabel = { hour: "Now", day: "Today", week: "This week", month: "This month" }[unit];
    // Ticks sit under the bar they name: the first, the middle and the current one.
    const place = (i) => `left:${(((i + .5) / bars.length) * 100).toFixed(2)}%`;
    const mid = Math.floor(current / 2);
    const ticks = [[0, label(bars[0])], ...(mid > 0 && current - mid > 1 ? [[mid, label(bars[mid])]] : []), ...(current > 0 ? [[current, nowLabel]] : [])]
      .map(([i, text]) => `<span${i === current ? ' class="on"' : ""} style="${place(i)}">${esc(i === current && current === 0 ? nowLabel : text)}</span>`).join("");
    const legend = range === "week" ? `<span class="hlegend"><span><i class="before"></i>7 days before</span><span><i></i>Last 7 days</span></span>` : "";
    return `<section class="card htrend" aria-labelledby="trend-h">
      <div class="card-head"><h2 id="trend-h">Tokens per ${unit}</h2><span class="hint">${legend}</span></div>
      <div class="hchart"><div class="haxis"><span>${fmt.tokens(top)}</span><span>${fmt.tokens(top / 2)}</span><span>0</span></div>
        <div class="hplot"><div class="hbars">${cols}</div><div class="hticks">${ticks}</div></div></div>
    </section>`;
  }

  function homeModels(usage) {
    const models = (usage.models || []).filter((m) => m.figures.tokens > 0).sort((a, b) => b.figures.tokens - a.figures.tokens);
    if (!models.length) return "";
    const sum = (usage.total?.tokens) || models.reduce((n, m) => n + m.figures.tokens, 0) || 1;
    const span = { today: "today", week: "the last 7 days", month: "this month", all: "all time" }[ui.homeRange] || "";
    const rows = models.slice(0, 4).map((m, i) => {
      const share = m.figures.tokens / sum;
      return `<div class="hmodel" role="listitem"><span class="tile-mark">${mark(m.tool)}</span><span class="hmodel-name"><b>${esc(m.model)}</b><small>via ${esc(toolName(m.tool))}</small></span><span class="hmodel-bar"><span class="${i === 0 ? "lead" : ""}" style="width:${(share / ((models[0].figures.tokens / sum) || 1) * 100).toFixed(1)}%" data-grow="home-model:${esc(m.tool + m.model)}"></span></span><b class="hmodel-pct">${share > 0 && share < .01 ? "<1%" : Math.round(share * 100) + "%"}</b></div>`;
    }).join("");
    return `<section class="card hmodels" aria-labelledby="models-h">
      <div class="card-head"><h2 id="models-h">Top models</h2><span class="hint">share of tokens ${esc(span)}</span></div>
      <div class="hmodel-list" role="list">${rows}</div>
    </section>`;
  }

  // The pet's night: its stage, how far to the next, and the hop it would make, in its own words.
  function homePet(tools) {
    const pet = data.pet;
    const head = homeHeadline(tools);
    const usage = data.usage[`${ui.homeRange}:all`] || data.usage["week:all"];
    const streak = pet?.streak ?? usage?.streak?.current ?? 0;
    let seed = 7;
    const rand = () => ((seed = (seed * 9301 + 49297) % 233280) / 233280);
    const stars = Array.from({ length: 34 }, (_, i) => `<rect class="star" style="--i:${i}" x="${(rand() * 400).toFixed(0)}" y="${(rand() * 190).toFixed(0)}" width="${rand() > .8 ? 2 : 1.4}" height="${rand() > .8 ? 2 : 1.4}"/>`).join("");
    const sky = `<svg class="hpet-sky" viewBox="0 0 400 300" preserveAspectRatio="xMidYMax slice" aria-hidden="true">${stars}<path class="hill1" d="M0 236 C 70 214 140 220 210 228 C 280 236 340 216 400 222 L400 300 L0 300 Z"/><path class="hill2" d="M0 266 C 100 252 210 256 300 262 C 350 265 380 264 400 262 L400 300 L0 300 Z"/></svg>`;
    const stageAt = pet ? Math.max(0, PET_STAGES.findIndex(([id]) => id === pet.stage)) : -1;
    const drawn = pet ? petSvg(pet) : null;
    const claim = claimKick(currentClaim());
    const title = pet ? (pet.lineageName ? `${pet.stageName} · ${pet.lineageName}` : pet.stageName) : "Your pet";
    let progressRow = "";
    if (pet) {
      const [, , from] = PET_STAGES[stageAt];
      const to = pet.next ? pet.tokens + pet.next.tokens : null;
      const share = to ? Math.min(1, Math.max(0, (pet.tokens - from) / (to - from))) : 1;
      progressRow = `<div class="hpet-progress"><div><span>About ${fmt.tokens(pet.tokens)} so far</span><span>${pet.next ? `${fmt.tokens(pet.next.tokens)} tokens until ${esc(pet.next.label)}` : "Fully grown"}</span></div><span class="hpet-track"><span style="width:${(share * 100).toFixed(1)}%" data-grow="home-pet"></span></span></div>`;
    } else if (!isStatic && data.state?.cloud?.available && !data.state.cloud.linked) {
      progressRow = `<div class="hpet-progress"><div><span>Link with GitHub and your pet hatches from the usage you already sync.</span></div></div>`;
    }
    const later = !head || ui.petLater === head.title;
    const bubble = later ? "" : `<div class="hpet-bubble" role="status"><b>${esc(head.title)}</b>${head.sub ? `<span>${esc(head.sub)}</span>` : ""}${!isStatic && head.target ? `<span class="hpet-acts"><button class="btn sm" type="button" data-action="switch" data-id="${esc(head.target)}">Hop</button><button class="btn sm quiet" type="button" data-action="pet-later" data-value="${esc(head.title)}">Later</button></span>` : ""}${!pet && !isStatic && data.state?.cloud?.available && !data.state.cloud.linked ? `<span class="hpet-acts"><button class="btn sm" type="button" data-action="cloud-link">Link with GitHub</button></span>` : ""}</div>`;
    const figure = drawn ? `<div class="hpet-figure">${drawn.svg}<span class="hpet-shadow"></span></div>` : `<div class="hpet-figure egg" aria-hidden="true"><span class="hpet-egg"></span><span class="hpet-shadow"></span></div>`;
    const stages = PET_STAGES.map(([id, name], i) => {
      const state = i === stageAt ? "on" : i < stageAt ? "past" : "ahead";
      const size = 12 + i * 3.4;
      return `<span class="hstage ${state}"><span class="hstage-tile">${drawn ? drawn.svg.replace('class="pet"', `class="pet-mini" style="height:${size.toFixed(0)}px"`) : ""}</span><span>${esc(name)}</span></span>`;
    }).join("");
    return `<section class="card hpet" aria-labelledby="pet-h">${sky}
      <div class="hpet-head"><h2 id="pet-h">${esc(title)}</h2>${claim || (streak ? `<span class="hpet-streak"><i aria-hidden="true"></i>On a ${streak}-day streak</span>` : "")}</div>
      ${progressRow}
      <div class="hpet-stage">${bubble}${figure}</div>
      <div class="hstages" aria-label="Stages">${stages}</div>
    </section>`;
  }

  function homeActivity(usage) {
    const days = (usage.heatmap || []).slice(-17 * 7);
    if (!days.length) return "";
    const s = usage.streak || { current: 0, longest: 0, activeDays: 0 };
    const offset = (new Date(days[0].day + "T00:00:00").getDay() + 6) % 7;
    const active = days.map((d) => d.tokens).filter((v) => v > 0).sort((a, b) => a - b);
    const q = (x) => (active.length ? active[Math.min(active.length - 1, Math.floor(x * active.length))] : 0);
    const cuts = [q(.25), q(.5), q(.75)];
    const cells = [...Array(offset).fill(null), ...days].map((day) => {
      if (!day) return `<span class="hcell pad"></span>`;
      const level = !day.tokens ? 0 : day.tokens <= cuts[0] ? 1 : day.tokens <= cuts[1] ? 2 : day.tokens <= cuts[2] ? 3 : 4;
      return `<span class="hcell l${level}"${day.tokens && !isStatic ? ` data-action="day" data-value="${day.day}"` : ""}${tipAttr(fmt.day(day.day + "T00:00:00", { weekday: "short", month: "short", day: "numeric" }), day.tokens ? [["Tokens", fmt.tokens(day.tokens)], ["API value", fmt.usd(day.cost)]] : [["No usage", ""]])}></span>`;
    }).join("");
    const note = s.current ? `${s.current}-day streak${s.current >= s.longest ? ", your best" : ` · best ${s.longest}`}` : `${s.activeDays} active days`;
    return `<section class="card hactivity" aria-labelledby="act-h">
      <div class="card-head"><h2 id="act-h">Activity</h2><span class="hint">${esc(note)}</span></div>
      <div class="hheat" role="img" aria-label="Tokens per day for the last 17 weeks">${cells}</div>
      <div class="hheat-foot"><span>${esc(fmt.day(days[0].day + "T00:00:00", { month: "long" }))}</span><span class="scale">Less <i class="hcell l0"></i><i class="hcell l1"></i><i class="hcell l2"></i><i class="hcell l3"></i><i class="hcell l4"></i> More</span></div>
    </section>`;
  }

  function homeSkeleton() {
    const line = (w, h = 12) => `<span class="skel" style="width:${w};height:${h}px"></span>`;
    const bars = Array.from({ length: 14 }, (_, i) => `<span class="skel" style="height:${18 + ((i * 37) % 60)}%"></span>`).join("");
    const rows = Array.from({ length: 4 }, () => `<div class="skel-row">${line("22px", 22)}${line("38%")}${line("100%", 6)}</div>`).join("");
    return `<section class="card htotal skel-card">${line("110px", 10)}${line("190px", 22)}${line("240px", 44)}<div class="skel-wait">${loading("Reading usage")}</div></section>
      <section class="card htrend skel-card"><div class="card-head">${line("120px", 14)}</div><div class="skel-bars">${bars}</div></section>
      <section class="card hmodels skel-card"><div class="card-head">${line("100px", 14)}</div><div class="skel-rows">${rows}</div></section>`;
  }

  function overviewPage(tools) {
    const adding = (id) => (data.state.adding || []).includes(id);
    const picker = tabs("home-range", HOME_RANGES.filter(([value]) => !isStatic || data.usage[`${value}:all`]), ui.homeRange);
    if (!tools.some((tool) => tool.accounts.length || adding(tool.id))) {
      const rows = tools.map((tool) => `<div class="row setup-row"><div class="account-id"><span class="tile-mark">${mark(tool.id)}</span><div class="account-copy"><div class="account-name"><b>${esc(tool.name)}</b></div><div class="account-line">${esc(tool.signInHint)}</div></div></div>${isStatic ? "" : `<button class="btn sm" type="button" data-action="add" data-tool="${esc(tool.id)}">Add</button>`}</div>`).join("");
      return { body: `<section class="card hwelcome" aria-labelledby="welcome-h"><span class="lab">Get started</span><h2 id="welcome-h">Add a login</h2><p class="muted">No saved accounts yet. Sign in once and Keyhop keeps the login, reads its limits and hops when one runs low.</p></section><section class="card" aria-label="Your logins"><div class="card-head"><h2>Your logins</h2></div><div class="list">${rows}</div></section>` };
    }
    const usage = data.usage[`${ui.homeRange}:all`];
    const error = data.usageErrors[`${ui.homeRange}:all`];
    // Until the first figures arrive, Home keeps its shape: the cards are there, only empty.
    const waiting = error ? `<section class="card"><p class="empty">${esc(error)}</p></section>` : homeSkeleton();
    const left = usage ? `${homeTotal(usage)}${homeTrend(usage)}${homeModels(usage)}` : waiting;
    const activity = usage ? homeActivity(usage) : "";
    return { toolbar: picker, body: `<div class="home-cols"><div class="home-col">${left}</div><div class="home-col">${homePet(tools)}${activity}</div></div>` };
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
