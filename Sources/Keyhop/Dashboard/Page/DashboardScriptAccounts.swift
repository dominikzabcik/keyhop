import Foundation

/// The Accounts section and the pet drawing it shares with the sidebar.
extension DashboardPage {
    static let scriptAccounts = ##"""
  // MARK: Accounts

  function accountsPage(tools) {
    const body = tools.map((tool) => {
      const adding = data.state.adding.includes(tool.id);
      const rows = tool.accounts.map((account) => accountRow(account, tool)).join("");
      const waiting = adding ? `<div class="row waiting-row"><div class="waiting"><span class="pulse"><i></i><i></i><i></i></span><span>Waiting for a new ${esc(tool.name)} login ${waited(tool.id)}<br><small>${esc(tool.signInHint)} Keyhop saves it the moment it appears.</small></span></div>
        ${isStatic ? "" : `<button class="btn sm ghost" data-action="add-stop" data-tool="${esc(tool.id)}">Stop waiting</button>`}</div>` : "";
      const empty = !tool.accounts.length && !adding ? `<p class="empty">${esc(tool.signInHint)}</p>` : "";
      return `<section class="group">
        <div class="group-head">${mark(tool.id)}<h2>${esc(tool.name)}</h2><span class="count">${tool.accounts.length}</span>
          ${isStatic ? "" : `<button class="btn sm ghost" data-action="add" data-tool="${esc(tool.id)}" ${adding ? "disabled" : ""}>${icon("plus")}Add account</button>`}</div>
        <div class="card list">${waiting}${rows}${empty}</div>
      </section>`;
    }).join("");
    return { body: `<div class="acct-sheet"><p class="lede">Every login Keyhop keeps. Switching saves the login in use first, so none is ever lost.</p>${body}</div>` };
  }

  // One saved login: a status dot, the name, and one sentence for the tightest window.
  // The login in use carries a mark that moves to the next one when you switch.
  function accountSentence(account, tool) {
    const top = tightest(account);
    if (account.error) return account.error;
    if (!top) return tool.limitsNote || "No limit to read.";
    const foot = limitFoot(top);
    return `${windowName(top.label)} at ${Math.round(top.usedPercent)}%.${foot ? ` ${foot}` : ""}`;
  }

  function accountRow(account, tool) {
    const editing = ui.editing === account.id;
    const confirming = ui.confirming === account.id;
    const lane = laneOf(account);
    const line = [account.plan, account.label ? account.email : "", accountSentence(account, tool)].filter(Boolean).join(" · ");
    const name = editing
      ? `<form class="rename" data-form="rename" data-id="${esc(account.id)}"><input class="field" name="name" value="${esc(account.label || "")}" placeholder="${esc(account.email)}" maxlength="60" aria-label="Name"><button class="btn sm">Save</button><button type="button" class="btn sm ghost" data-action="cancel-edit">Cancel</button></form>`
      : `<div class="account-name"><b class="${lane === "needs" ? "warn" : ""}">${esc(account.name)}</b>${account.active ? `<span class="in-use" style="view-transition-name:in-use-${esc(tool.id)}">In use</span>` : ""}</div>
         <div class="account-line">${esc(line)}</div>`;
    let actions = "";
    if (!isStatic && !editing) {
      if (confirming) {
        actions = `<span class="subtle" style="font-size:12.5px">Delete this saved login?</span><button class="btn sm secondary danger" data-action="remove" data-id="${esc(account.id)}">Remove</button><button class="btn sm ghost" data-action="cancel-remove">Keep</button>`;
      } else {
        const open = ui.menu === account.id;
        const menu = open ? `<div class="row-menu" role="menu">
            <button type="button" role="menuitem" data-action="edit" data-id="${esc(account.id)}">Rename</button>
            ${account.active ? "" : `<button type="button" role="menuitem" class="danger" data-action="confirm-remove" data-id="${esc(account.id)}">Remove saved login</button>`}
          </div>` : "";
        actions = `${account.active ? "" : `<button class="btn sm secondary" data-action="switch" data-id="${esc(account.id)}">Switch</button>`}
          <span class="menu-anchor"><button type="button" class="btn sm ghost icon-only" data-action="account-menu" data-id="${esc(account.id)}" aria-haspopup="true" aria-expanded="${open}" aria-label="More for ${esc(account.name)}">${icon("more")}</button>${menu}</span>`;
      }
    }
    const today = account.today
      ? `<b data-count="${account.today.tokens}" data-count-key="acct:${esc(account.id)}" data-format="tokens">${fmt.tokens(account.today.tokens)}</b><span>tokens today · ${fmt.usd(account.today.cost)}</span>`
      : `<span>No usage today</span>`;
    return `<div class="row account-row${account.active ? " active" : ""}" style="view-transition-name:acct-${esc(account.id)}">
      <div class="account-id">${dot(lane)}<div class="account-copy">${name}</div></div>
      <div class="today">${today}</div>
      <div class="row-actions">${actions}</div>
    </div>`;
  }

"""##
}
