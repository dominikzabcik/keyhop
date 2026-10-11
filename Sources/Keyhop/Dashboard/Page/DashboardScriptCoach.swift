import Foundation

/// The Coach section: optimize, compare and yield, from this computer's own store.
extension DashboardPage {
    static let scriptCoach = ##"""
  // MARK: Coach

  function deltaCell(delta, format) {
    const change = delta.change == null ? `<span class="subtle">new</span>` : `<span class="${delta.change > 0 ? "up" : delta.change < 0 ? "down" : "subtle"}">${delta.change > 0 ? "+" : ""}${Math.round(delta.change)}%</span>`;
    return `<div class="coach-delta"><span class="subtle">${esc(delta.label)}</span><b class="num">${format(delta.now)}</b><span class="subtle num">from ${format(delta.before)}</span>${change}</div>`;
  }

  function coachPage() {
    if (isStatic) return { body: `<section class="card"><p class="empty">Coaching is read live in the window, not in a saved page.</p></section>` };
    if (data.coachError) return { body: `<div class="notice">${icon("alert")}<div><p>${esc(data.coachError)}</p></div></div>` };
    const report = data.coach;
    if (!report) return { body: `<section class="card"><p class="empty" data-loading="Reading the last thirty days">${loadingInner("Reading the last thirty days")}</p></section>` };
    const o = report.optimize, c = report.compare, y = report.yield;
    const findings = o.findings.map((f) => `<p class="coach-finding ${esc(f.kind)}">${esc(f.text)}</p>`).join("");
    const tools = o.tools.length ? `<table class="table"><thead><tr><th>Tool</th><th class="right">API value</th><th class="right">Cache hit</th><th class="right">Premium models</th></tr></thead>
      <tbody>${o.tools.map((t) => `<tr><td><span class="cell-name">${mark(t.tool)}<span>${esc(t.toolName)}</span></span></td><td class="right mono">${fmt.usd(t.apiValue)}</td><td class="right mono">${t.cacheHit == null ? "n/a" : `${Math.round(t.cacheHit)}%`}</td><td class="right mono">${Math.round(t.premiumShare)}%</td></tr>`).join("")}</tbody></table>` : "";
    const sessions = o.sessions.length ? `<table class="table"><thead><tr><th>Heaviest sessions</th><th class="right">Minutes</th><th class="right">API value</th><th class="right">Of the period</th></tr></thead>
      <tbody>${o.sessions.map((s) => `<tr><td><span class="cell-name">${mark(s.tool)}<span>${esc(s.model)} · ${esc(fmt.day(s.from))}</span></span></td><td class="right mono">${s.minutes}</td><td class="right mono">${fmt.usd(s.apiValue)}</td><td class="right mono">${Math.round(s.share)}%</td></tr>`).join("")}</tbody></table>` : "";
    const optimize = `<section class="card"><div class="card-head"><h2>Optimize</h2><span class="hint">Last ${report.days} days</span></div>
      <div class="card-body">${findings}</div>${tools}${sessions}</section>`;
    const compare = `<section class="card"><div class="card-head"><h2>Compare</h2><span class="hint">Against the ${report.days} days before</span></div>
      <div class="card-body coach-deltas">${deltaCell(c.tokens, fmt.tokens)}${deltaCell(c.apiValue, fmt.usd)}${deltaCell(c.requests, fmt.count)}${deltaCell(c.cacheHit, (v) => `${Math.round(v)}%`)}</div>
      ${c.tools.length ? `<table class="table"><thead><tr><th>Tool</th><th class="right">Now</th><th class="right">Before</th><th class="right">Change</th></tr></thead><tbody>${c.tools.map((d) => `<tr><td>${esc(d.label)}</td><td class="right mono">${fmt.usd(d.now)}</td><td class="right mono">${fmt.usd(d.before)}</td><td class="right mono">${d.change == null ? "new" : `${d.change > 0 ? "+" : ""}${Math.round(d.change)}%`}</td></tr>`).join("")}</tbody></table>` : ""}
      ${c.models.length ? `<table class="table"><thead><tr><th>Model</th><th class="right">Now</th><th class="right">Before</th><th class="right">Change</th></tr></thead><tbody>${c.models.map((d) => `<tr><td class="mono">${esc(d.label)}</td><td class="right mono">${fmt.usd(d.now)}</td><td class="right mono">${fmt.usd(d.before)}</td><td class="right mono">${d.change == null ? "new" : `${d.change > 0 ? "+" : ""}${Math.round(d.change)}%`}</td></tr>`).join("")}</tbody></table>` : ""}</section>`;
    const yieldBody = y.enabled
      ? `<div class="card-body coach-deltas">
          <div class="coach-delta"><span class="subtle">Commits</span><b class="num">${fmt.count(y.commits)}</b><span class="subtle">${y.merges} merges</span></div>
          <div class="coach-delta"><span class="subtle">Per commit</span><b class="num">${y.tokensPerCommit == null ? "n/a" : fmt.tokens(y.tokensPerCommit)}</b><span class="subtle">${y.valuePerCommit == null ? "" : fmt.usd(y.valuePerCommit)}</span></div>
          <div class="coach-delta"><span class="subtle">Per merge</span><b class="num">${y.tokensPerMerge == null ? "n/a" : fmt.tokens(y.tokensPerMerge)}</b><span class="subtle">${y.valuePerMerge == null ? "" : fmt.usd(y.valuePerMerge)}</span></div>
          <div class="coach-delta"><span class="subtle">Spent</span><b class="num">${fmt.tokens(y.tokens)}</b><span class="subtle">${fmt.usd(y.apiValue)}</span></div></div>
        ${y.note ? `<div class="card-body"><p class="empty-inline">${esc(y.note)}</p></div>` : ""}
        ${y.repos.length ? `<table class="table"><thead><tr><th>Repository</th><th class="right">Commits</th><th class="right">Merges</th><th class="right">Tokens</th><th class="right">Per commit</th><th class="right">Per merge</th></tr></thead><tbody>${y.repos.map((r) => `<tr><td>${esc(r.repo)}</td><td class="right mono">${r.commits}</td><td class="right mono">${r.merges}</td><td class="right mono">${fmt.tokens(r.tokens)}</td><td class="right mono">${r.tokensPerCommit == null ? "n/a" : fmt.tokens(r.tokensPerCommit)}</td><td class="right mono">${r.valuePerMerge == null ? "n/a" : fmt.usd(r.valuePerMerge)}</td></tr>`).join("")}</tbody></table>` : ""}`
      : `<div class="card-body"><p class="empty-inline">${esc(y.note || "")}</p></div>`;
    const yieldCard = `<section class="card"><div class="card-head"><h2>Yield</h2><span class="hint">What the spend produced</span></div>${yieldBody}</section>`;
    return { body: optimize + compare + yieldCard };
  }
"""##
}
