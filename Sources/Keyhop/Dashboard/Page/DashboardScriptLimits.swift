import Foundation

/// Limits: every saved login, grouped by tool, with what each window has used and when it
/// resets. Only what the tools report; no guesses about when a limit will run out.
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
    return { toolbar, body: `<div class="lim-page">${empty}${groups}${note}${unset}</div>` };
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
    const read = account.error || !account.limitsReadAt ? "" : `${account.readError ? "last read" : "read"} ${fmt.relative(account.limitsReadAt)}`;
    const meta = [account.plan, account.label ? account.email : "", read].filter(Boolean).join(" · ");
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
