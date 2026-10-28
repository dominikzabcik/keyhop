import Foundation

/// The Budgets section.
extension DashboardPage {
    static let scriptBudgets = ##"""
  // MARK: Budgets

  function periodProgress(period) {
    const now = new Date();
    let start, end;
    if (period === "day") { start = new Date(now.getFullYear(), now.getMonth(), now.getDate()); end = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1); }
    else if (period === "week") { start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - ((now.getDay() + 6) % 7)); end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 7); }
    else { start = new Date(now.getFullYear(), now.getMonth(), 1); end = new Date(now.getFullYear(), now.getMonth() + 1, 1); }
    return { start, end, elapsed: Math.min(1, Math.max(0.02, (now - start) / (end - start))) };
  }

  function budgetsPage(tools) {
    const status = data.state.status;
    const accounts = tools.flatMap((t) => t.accounts.map((a) => ({ ...a, toolName: t.name })));
    const editing = ui.budgetEdit ? status.budgets.find((b) => b.scope === ui.budgetEdit) : null;
    const scopeValue = editing ? (editing.scope === "all" ? "all" : editing.scope.replace("account:", "")) : "all";
    const list = status.budgets.length ? `<div class="list">${status.budgets.map((b) => `
      <div class="row budget-row">
        ${budgetRow(b).replace(/^<div class="row budget-row">|<\/div>\s*$/g, "")}
        ${isStatic ? "" : `<div class="row-actions" style="justify-content:flex-start;margin-left:-10px"><button class="btn sm ghost" data-action="edit-budget" data-scope="${esc(b.scope)}">Change</button><button class="btn sm ghost danger" data-action="delete-budget" data-scope="${esc(b.scope)}">Remove</button></div>`}
      </div>`).join("")}</div>` : `<p class="empty">No budgets yet. A budget counts what you are charged where a provider reports it, the tokens at API prices elsewhere, and warns you at 80% and 100%.</p>`;
    const form = isStatic ? "" : `<section class="card">
      <div class="card-head"><h2>${editing ? "Change budget" : "New budget"}</h2></div>
      <form class="form" data-form="budget">
        <label>Applies to<select class="field" name="scope"><option value="all" ${scopeValue === "all" ? "selected" : ""}>All accounts</option>${accounts.map((a) => `<option value="${esc(a.id)}" ${scopeValue === a.id ? "selected" : ""}>${esc(a.toolName)} · ${esc(a.name)}</option>`).join("")}</select></label>
        <div class="pair">
          <label>Amount (USD)<input class="field mono" name="amount" inputmode="decimal" placeholder="200" value="${editing ? esc(editing.amount) : ""}" required></label>
          <label>Period<select class="field" name="period">${[["day", "Daily"], ["week", "Weekly"], ["month", "Monthly"]].map(([v, l]) => `<option value="${v}" ${(editing ? editing.period : "month") === v ? "selected" : ""}>${l}</option>`).join("")}</select></label>
        </div>
        <div class="row-actions" style="justify-content:flex-start">${editing ? `<button type="button" class="btn sm ghost" data-action="cancel-budget">Cancel</button>` : ""}<button class="btn sm">Save budget</button></div>
      </form>
    </section>`;
    const month = data.usage["month:all"];
    const overall = status.budgets.find((b) => b.scope === "all" && b.period === "month");
    const byAccount = !month ? `<div class="skel-card" role="status" aria-label="Reading this month's usage">${skelList(4, 30)}</div>` : month.total.requests ? accountTable(month.accounts, "cost") : `<p class="empty">No usage this month yet.</p>`;
    return { body: `
      <div class="split wide-left">
        <section class="card"><div class="card-head"><h2>Budgets</h2><span class="hint mono">${status.budgets.length}</span></div>${list}</section>
        ${form || "<div></div>"}
      </div>
      <div class="split wide-left">
        ${spendCard(month, overall)}
        <section class="card"><div class="card-head"><h2>Spend by account</h2><span class="hint">This month</span></div>${byAccount}</section>
      </div>` };
  }

  function spendCard(usage, budget) {
    if (!usage) return `<section class="card"><div class="card-head"><h2>This month</h2></div><div class="skel-card">${loading("Reading this month's usage")}${skel("100%", 160)}</div></section>`;
    const now = Date.now();
    let running = 0;
    const points = [];
    usage.buckets.forEach((bucket, i) => {
      if (new Date(bucket.start).getTime() > now) return;
      running += Object.values(bucket.values).reduce((sum, v) => sum + v.cost, 0);
      points.push({ i, total: running });
    });
    const days = usage.buckets.length;
    // As tall as the spend list beside it (a row per account), so the two cards end together.
    const rows = (usage.accounts || []).length;
    const W = chartWidth("wide"), H = Math.max(220, Math.min(440, 59 * rows - 72)), L = 52, R = 8, T = 16, B = 26;
    const pw = W - L - R, ph = H - T - B;
    const ceiling = niceCeiling(Math.max(running, budget ? budget.amount : 0) * 1.08);
    const x = (i) => L + (days > 1 ? (i / (days - 1)) * pw : pw / 2);
    const y = (v) => T + ph - (v / ceiling) * ph;
    let grid = "";
    for (let step = 0; step <= 4; step++) {
      const value = (ceiling / 4) * step, yy = y(value).toFixed(1);
      grid += `<line class="${step ? "grid" : "base"}" x1="${L}" x2="${W - R}" y1="${yy}" y2="${yy}"/><text class="axis" x="${L - 8}" y="${yy}" text-anchor="end" dominant-baseline="central">${value === 0 ? "$0" : fmt.usd(value)}</text>`;
    }
    [0, Math.floor((days - 1) / 2), days - 1].forEach((i) => {
      grid += `<text class="axis" x="${x(i).toFixed(1)}" y="${H - 7}" text-anchor="${i === 0 ? "start" : i === days - 1 ? "end" : "middle"}">${esc(fmt.day(usage.buckets[i].start, { month: "short", day: "numeric" }))}</text>`;
    });
    let marks = "";
    if (budget) {
      const by = y(budget.amount).toFixed(1);
      marks += `<line x1="${L}" x2="${W - R}" y1="${by}" y2="${by}" style="stroke:hsl(var(--on) / .4)" stroke-dasharray="4 5"/><text class="axis" x="${W - R}" y="${(y(budget.amount) - 7).toFixed(1)}" text-anchor="end">budget ${fmt.usd(budget.amount)}</text>`;
      marks += `<line x1="${x(0).toFixed(1)}" y1="${y(0).toFixed(1)}" x2="${x(days - 1).toFixed(1)}" y2="${by}" style="stroke:hsl(var(--on) / .12)"/>`;
    }
    let line = "";
    if (points.length) {
      const path = points.map((p, k) => `${k ? "L" : "M"}${x(p.i).toFixed(1)},${y(p.total).toFixed(1)}`).join("");
      const last = points[points.length - 1];
      line = `<path d="${path}L${x(last.i).toFixed(1)},${y(0).toFixed(1)}L${x(points[0].i).toFixed(1)},${y(0).toFixed(1)}Z" style="fill:color-mix(in srgb, var(--primary) 12%, transparent)"/><path d="${path}" fill="none" style="stroke:var(--primary)" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"/><circle cx="${x(last.i).toFixed(1)}" cy="${y(last.total).toFixed(1)}" r="3.5" style="fill:var(--primary)"/>`;
    }
    const elapsed = periodProgress("month").elapsed;
    return `<section class="card">
      <div class="card-head"><h2>This month</h2><span class="hint mono">${running > 0 ? `${fmt.usd(running)} · pace ${fmt.usd(running / elapsed)}` : "$0"}</span></div>
      <div class="card-body chart"><svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="Spend this month, added up by day">${grid}${marks}${line}</svg>
      ${budget ? "" : `<p class="empty-inline subtle" style="margin-top:8px">Add a monthly budget for all accounts to compare against it.</p>`}</div>
      <div class="facts">
        <div><b data-count="${running}" data-count-key="budget-spent" data-format="usd">${fmt.usd(running)}</b><span>spent so far</span></div>
        <div><b data-count="${running / elapsed}" data-count-key="budget-pace" data-format="usd">${fmt.usd(running / elapsed)}</b><span>on pace for the month</span></div>
        <div><b>${Math.max(0, Math.ceil((periodProgress("month").end - Date.now()) / 86400000))}</b><span>${budget ? `days left of ${fmt.usd(budget.amount)}` : "days left"}</span></div>
      </div>
    </section>`;
  }

"""##
}
