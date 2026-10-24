import Foundation

/// The Plans section: what each paid plan costs against the month's API value and the week's peaks.
extension DashboardPage {
    static let scriptPlans = ##"""
  // MARK: Plans

  // What a row says, from what was measured only: a window at its limit this week, a plan the
  // month's API value has already passed, or one nothing used.
  function planStanding(row) {
    if (row.standing === "wall") return ["Hits its limit", "bad"];
    if (row.price > 0 && row.apiValue >= row.price) return ["Pays off", "good"];
    // Copilot and Windsurf report limits but no tokens, so only an empty window says unused.
    if (row.price > 0 && row.apiValue === 0 && !row.windows.some((w) => w.peak > 0)) return ["Unused", "warn"];
    return ["", ""];
  }
  const times = (value, price) => price > 0 ? `${(value / price) >= 10 ? Math.round(value / price) : (value / price).toFixed(1)}×` : "";

  // One row a login: its plan and price, the month's API value against it, and the week's peak.
  function planRow(row) {
    const price = row.price == null ? "" : row.price === 0 ? "Free" : fmt.usd(row.price);
    const peak = row.windows.reduce((best, w) => (!best || w.peak > best.peak ? w : best), null);
    const [label, tone] = planStanding(row);
    const pill = label ? `<span class="pill ${tone}"${row.advice ? ` title="${esc(row.advice)}"` : ""}>${esc(label)}</span>` : "";
    return `<tr>
      <td><span class="cell-name">${mark(row.tool)}<span>${esc(row.name)}</span></span></td>
      <td>${esc(row.plan || "")}</td>
      <td class="right mono">${esc(price)}</td>
      <td class="right mono">${fmt.usd(row.apiValue)}</td>
      <td class="right mono subtle">${row.apiValue > 0 ? times(row.apiValue, row.price) : ""}</td>
      <td>${peak ? `<div class="plan-peak">${progress(peak.peak, null, peak.peak >= 90 ? "bad" : peak.peak >= 75 ? "warn" : "", `plan-peak:${esc(row.id)}`)}<span class="mono subtle num">${Math.round(peak.peak)}% ${esc(peak.label)}</span></div>` : ""}</td>
      <td class="right">${pill}</td>
    </tr>`;
  }

  function plansPage() {
    if (isStatic) return { body: `<section class="card"><p class="empty">Plans are priced live in the window, not in a saved page.</p></section>` };
    if (data.plansError) return { body: failed(data.plansError) };
    const report = data.plans;
    if (!report) return { body: `<section class="card"><p class="empty" data-loading="Pricing this month's plans">${loadingInner("Pricing this month's plans")}</p></section>` };
    if (!report.rows.length) return { body: `<section class="card"><p class="empty">No logins to price yet. Add one under Limits.</p></section>` };
    const figure = (value, label) => `<div class="plans-fig"><b class="num">${value}</b><span class="subtle">${label}</span></div>`;
    const head = `<section class="card plans-head" title="API value is what the tokens would cost at standard API prices, never the bill. The peak is the highest a window reached in the last seven days.">
      ${figure(fmt.usd(report.paid), "a month in plans")}${figure(fmt.usd(report.apiValue), `API value in ${esc(report.month)}`)}${report.paid > 0 ? figure(times(report.apiValue, report.paid), "what the plans return") : ""}
    </section>`;
    const rows = report.rows.slice().sort((a, b) => a.toolName.localeCompare(b.toolName) || b.apiValue - a.apiValue).map(planRow).join("");
    const table = `<section class="card"><div class="table-wrap"><table class="table plans-table"><thead><tr><th>Login</th><th>Plan</th><th class="right">Price</th><th class="right nowrap">API value</th><th class="right">Return</th><th>Peak this week</th><th></th></tr></thead><tbody>${rows}</tbody></table></div></section>`;
    return { body: head + table };
  }
"""##
}
