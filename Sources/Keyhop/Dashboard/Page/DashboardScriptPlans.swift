import Foundation

/// The Plans section: what each paid plan costs against the month's API value and the week's peaks.
extension DashboardPage {
    static let scriptPlans = ##"""
  // MARK: Plans

  function planWindow(window) {
    const tone = window.peak >= 90 ? "bad" : window.peak >= 75 ? "warn" : "";
    return `<div class="plan-window"><span class="subtle">${esc(window.label)}</span>${progress(window.peak, null, tone, `plan-window:${esc(window.label)}`)}<span class="mono subtle num">${Math.round(window.peak)}% peak</span></div>`;
  }

  function planCard(row) {
    const price = row.price == null ? "Unpriced" : row.price === 0 ? "Free" : `${fmt.usd(row.price)} / month`;
    const share = row.price && row.price > 0 ? Math.min(100, (row.apiValue / row.price) * 100) : 0;
    const standing = { earning: "Earning its keep", room: "Room to spare", wall: "Near the wall", free: "Free", quiet: "Quiet", unknown: "Unpriced" }[row.standing] || "";
    const tone = row.standing === "wall" ? "bad" : row.standing === "room" || row.standing === "quiet" ? "warn" : "";
    return `<section class="card plan-card ${esc(row.standing)}">
      <header class="card-head"><h2>${mark(row.tool)}<span>${esc(row.toolName)} · ${esc(row.name)}</span></h2><span class="pill ${tone}">${esc(standing)}</span></header>
      <div class="card-body">
        <div class="plan-top"><div><b>${esc(row.plan || "No plan reported")}</b><span class="subtle">${esc(price)}</span></div>
          <div class="plan-value"><b class="num">${fmt.usd(row.apiValue)}</b><span class="subtle">API value this month${row.billed > 0 ? `, ${fmt.usd(row.billed)} billed` : ""}</span></div></div>
        ${row.price && row.price > 0 ? progress(share, null, row.standing === "wall" ? "bad" : "", `plan:${esc(row.id)}`) : ""}
        <p class="plan-verdict">${esc(row.verdict)}</p>
        ${row.advice ? `<p class="plan-advice">${esc(row.advice)}</p>` : ""}
        ${row.windows.length ? `<div class="plan-windows">${row.windows.map(planWindow).join("")}</div>` : ""}
      </div></section>`;
  }

  function plansPage() {
    if (isStatic) return { body: `<section class="card"><p class="empty">Plans are priced live in the window, not in a saved page.</p></section>` };
    if (data.plansError) return { body: `<div class="notice">${icon("alert")}<div><p>${esc(data.plansError)}</p></div></div>` };
    const report = data.plans;
    if (!report) return { body: `<section class="card"><p class="empty" data-loading="Pricing this month's plans">${loadingInner("Pricing this month's plans")}</p></section>` };
    const head = `<section class="card plans-head"><div class="card-body"><p class="plans-headline">${esc(report.headline)}</p>
      <p class="subtle">${esc(report.month)}. List prices as Keyhop knows them; API value is what the month's tokens would cost at standard API prices, never the bill. Peaks are the highest each window reached in the last seven days.</p></div></section>`;
    const cards = report.rows.length
      ? `<div class="plan-grid">${report.rows.map(planCard).join("")}</div>`
      : `<section class="card"><p class="empty">No logins to price yet. Add one under Accounts.</p></section>`;
    return { body: head + cards };
  }
"""##
}
