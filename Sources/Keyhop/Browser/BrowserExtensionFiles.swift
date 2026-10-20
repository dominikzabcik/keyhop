import Foundation

/// The Chrome extension's files, written out by `keyhop browser install`. They live here rather
/// than in a resource bundle so the one binary carries them on every platform.
enum BrowserExtensionFiles {
    /// Chrome derives the extension's ID from the public key in the manifest, so an unpacked copy
    /// always has this ID and the native host can name it.
    static let id = "jghheogemlfdoplloeaiffadakpfjhna"

    static let text: [String: String] = [
        "manifest.json": manifest,
        "background.js": background,
        "popup.html": popup,
        "popup.js": popupScript,
    ]

    static let images: [String: String] = [
        "icon-32.png": "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAIKADAAQAAAABAAAAIAAAAACshmLzAAADjElEQVRYCc1XsU4bQRBdO8GEIggJpY0osKEB+SMoIqVBEaKIlEhp0kTKB4AMCPgCRBOafAAI5QNoU6VJkDC2oUBBpCCWDKIACkPeW/yOZbO3PqJIyUjrmd2ZeW9ub+d8Z8w/lpzPPzQ0NHB1dfU2n89PXF9fl+B/gtGL8cCP7TJvw3+Zy+V+QjcwtjDWDg4OTqATuVMAyCdB+hHegSTi7xonuLg3h4eHnwSbFNAh30QBKDpnoBUT1YqlpjBPa5zLlp8hsF9gJ2wRNgvkA6Ojo9/n5uYeDw8P2yQmE2x/f98sLCyYWq3GpcwCPJsXwltcXDwD3lPeDntf+/v736+srDwvlUoJOZlY9eDgoBkfHzcbGxuWPMMV2rjV1VVTLBaDeGNjY73r6+ut09PTz3lGA3SCwWnCqyCxS87iONw12hRq5qRJxzdB/0P+IKFEsDRxfS6J4rXGuWw3R3HS9OEwssNuCoBmq0VFwH4QwegToWv7sd7cctpbAMcjz5l5qsKoQ3YIqBPHZ4vRGVAhoXi75hOkBaqIvb29tBBDH+JsA3Ql9lFEoIJ8rVsyPz9vGo1GsivEYSzX0O7JLbOH0CeJzdnf6OM7LUZgXhWB9bzY3d0109PTMSjry7wDulKSh54XXKOvmxCHIq027JaXbFnseUGfgGOAbkzmAtC3FlPtFiKI+ULxXLv3GUgD0rp7dVqL6cxnQCAxgphP+b6+dwGx/lbbsRANErqFyZa2BWjiV+fOGcMxOztr6vX6b6Bcq1Qqboq1ha18LmqN9r3PAPt8amqKuUEhOA8jnxfLy8t3WpY+7hILrVarNj/zDohN1VOHhp6EJB8ZGUnal/n0cW1paUlwN/8FmPEFMioiY5CKCCXIxwdTmnR8llOH8DItWOsqwNf0i1Sx1LFnQmeXLKduAV+d/0hEHiqsC6Dl1A40BBRKyuJTAcx37TQ8xNTpUwFbPJ1pEupvkejQUbt2NzzE8kPl5munp6dnB3+f7/D228u3YAJRSEKgmZkZ02w27VrWn+3tbVMul+1btY+HNjw7Ojp6dQFJ3kRBPInATYwcid0k2lyjyE7z+wX68fDbD5Pj42P7YZJ8752fn9f6+vq+IeAZRuo7ooilSejanEfkBBfyEruZfJolBTCJRRQKhQ8AbOHjlEt8UhYwONF5gXkr2hlpFkMbmn1+AfsHsL5Ar7Xb7detVuvrbfZ/YP0CD/R9kUF6WGwAAAAASUVORK5CYII=",
        "icon-48.png": "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",
        "icon-128.png": "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",
    ]

    static let manifest = ##"""
{
  "manifest_version": 3,
  "name": "Keyhop",
  "version": "1.0.0",
  "description": "When Keyhop hops Claude Code or Codex to another account, claude.ai and chatgpt.com in this browser follow.",
  "key": "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAs9DI8tqiBfNNRUxdhRzm/5tHIwpCDX5pzPDQ0lFUfEzmOG4VHgWcednKX4S6P4M2Jvi72ePNgDl2Z/fb7O2jYkazfNHCvy2kOqDLH1q+PaqEt2Etc+s8lcXdnxv7rYURokZpZBjBhfJkOJBKBhwhCcb8FxVAuARAavVe51OEzLlYW8qxH7OSjmZ8kJFj3qHhECx4wSl026EIDXGA9QnxQINiO9KO7LPR0yLlMHdetMNv8M2QG/1bF2elBFUmjGN/QKcRSAAYFm3SC2Y9etI3tlJNzKsWgnUcqopn011vupTAUmBfPSPPDkvPPLHgP6sLlJpYIK8EBXtplQej3VJfqwIDAQAB",
  "background": { "service_worker": "background.js" },
  "action": { "default_popup": "popup.html", "default_title": "Keyhop", "default_icon": { "32": "icon-32.png", "48": "icon-48.png", "128": "icon-128.png" } },
  "icons": { "32": "icon-32.png", "48": "icon-48.png", "128": "icon-128.png" },
  "permissions": ["nativeMessaging", "cookies", "storage", "alarms", "notifications"],
  "host_permissions": ["https://claude.ai/*", "https://*.claude.ai/*", "https://chatgpt.com/*", "https://*.chatgpt.com/*"],
  "minimum_chrome_version": "116"
}
"""##

    static let background = ##"""
// Keyhop for Chrome: when Keyhop hops Claude Code or Codex to another account, the claude.ai or
// chatgpt.com login in this browser follows. Each site's cookies are kept per account by Keyhop
// itself (in the Keychain on a Mac), never in the browser's storage.

const HOST = "app.keyhop.browser";
const SITES = {
  "claude.ai": {
    tool: "claude",
    home: "https://claude.ai/",
    login: "https://claude.ai/login",
    domains: ["claude.ai"],
    session: ["sessionKey"],
    async who() {
      const response = await fetch("https://claude.ai/api/account", { credentials: "include", headers: { Accept: "application/json" } });
      if (!response.ok) return null;
      const body = await response.json();
      const email = body.email_address || body.email || body.account?.email_address;
      return email ? { email, id: body.uuid || body.account?.uuid || "" } : null;
    },
  },
  "chatgpt.com": {
    tool: "codex",
    home: "https://chatgpt.com/",
    login: "https://chatgpt.com/auth/login",
    domains: ["chatgpt.com"],
    session: ["__Secure-next-auth.session-token"],
    async who() {
      const response = await fetch("https://chatgpt.com/api/auth/session", { credentials: "include", headers: { Accept: "application/json" } });
      if (!response.ok) return null;
      const body = await response.json();
      return body.user?.email ? { email: body.user.email, id: body.user.id || "" } : null;
    },
  },
};

let port = null;
let retry = 1000;
const waiting = new Map();
const busy = new Set();
const status = { connected: false, error: "", sites: {} };

// MARK: Keyhop

function connect() {
  if (port) return;
  try {
    port = chrome.runtime.connectNative(HOST);
  } catch (error) {
    status.connected = false;
    status.error = String(error.message || error);
    return later();
  }
  port.onMessage.addListener(receive);
  port.onDisconnect.addListener(() => {
    status.connected = false;
    status.error = chrome.runtime.lastError?.message || "Keyhop closed the connection.";
    port = null;
    for (const [, done] of waiting) done(null);
    waiting.clear();
    badge();
    later();
  });
  send({ type: "hello", version: chrome.runtime.getManifest().version });
}

function later() {
  setTimeout(connect, retry);
  retry = Math.min(retry * 2, 60_000);
}

function send(message) {
  try { port?.postMessage(message); } catch {}
}

// Asks Keyhop something and waits for the answer with the same id.
function ask(message) {
  const id = crypto.randomUUID();
  return new Promise((resolve) => {
    const timer = setTimeout(() => { waiting.delete(id); resolve(null); }, 10_000);
    waiting.set(id, (reply) => { clearTimeout(timer); resolve(reply); });
    send({ ...message, id });
  });
}

async function receive(message) {
  if (message.id && waiting.has(message.id)) {
    const done = waiting.get(message.id);
    waiting.delete(message.id);
    return done(message);
  }
  if (message.type === "state") {
    status.connected = true;
    status.error = "";
    retry = 1000;
    status.keyhop = message.version;
    for (const site of message.sites || []) await follow(site);
    badge();
  }
}

// MARK: Following a hop

// Keyhop says which account each tool uses. When that changes, the site follows once; signing in
// to another account on the site by hand afterwards is left alone.
async function follow(site) {
  const spec = SITES[site.site];
  if (!spec) return;
  const entry = (status.sites[site.site] ||= {});
  entry.keyhop = site.active || null;
  entry.saved = (site.accounts || []).filter((account) => account.web).length;
  if (!site.active) return;
  const { applied = {} } = await chrome.storage.local.get("applied");
  if (applied[site.site] === site.active.id) return;
  if (busy.has(site.site)) return;
  busy.add(site.site);
  try {
    // The first time, the browser's login is only kept: the site follows Keyhop's next hop.
    if (applied[site.site] === undefined) {
      const now = await who(site.site);
      if (now) await keep(site.site, now);
    } else {
      await hop(site.site, site.active);
    }
    applied[site.site] = site.active.id;
    await chrome.storage.local.set({ applied });
  } finally {
    busy.delete(site.site);
  }
}

async function hop(name, target) {
  const spec = SITES[name];
  const now = await who(name);
  if (now && same(now.email, target.email)) {
    status.sites[name].browser = now.email;
    await keep(name, now);
    return;
  }
  // The login on the site now is kept first, so a hop never loses one.
  if (now) await keep(name, now);
  const reply = await ask({ type: "cookies", site: name, account: target.id });
  await clear(spec);
  if (reply?.cookies?.length) {
    for (const cookie of reply.cookies) await put(cookie);
    const after = await who(name);
    status.sites[name].browser = after?.email || "";
    if (after && same(after.email, target.email)) {
      await reload(spec);
      return;
    }
    // The saved login has expired: sign in again, and the new one is kept.
    await clear(spec);
  }
  status.sites[name].browser = "";
  status.sites[name].needs = target.email;
  await signIn(spec, target.email);
}

async function who(name) {
  try { return await SITES[name].who(); } catch { return null; }
}

async function keep(name, identity) {
  const spec = SITES[name];
  const cookies = [];
  for (const domain of spec.domains) cookies.push(...await chrome.cookies.getAll({ domain }));
  if (!cookies.some((cookie) => spec.session.some((key) => cookie.name.startsWith(key)))) return;
  const reply = await ask({ type: "session", site: name, email: identity.email, webId: identity.id, cookies: cookies.map(plain) });
  if (reply?.type === "saved") {
    status.sites[name].browser = identity.email;
    if (same(status.sites[name].needs, identity.email)) status.sites[name].needs = "";
  }
  return reply;
}

const same = (a, b) => !!a && !!b && a.toLowerCase() === b.toLowerCase();

function plain(cookie) {
  return {
    name: cookie.name, value: cookie.value, domain: cookie.domain, path: cookie.path,
    secure: cookie.secure, httpOnly: cookie.httpOnly, sameSite: cookie.sameSite,
    hostOnly: cookie.hostOnly, expirationDate: cookie.session ? null : cookie.expirationDate,
  };
}

const urlOf = (cookie) => `https://${cookie.domain.replace(/^\./, "")}${cookie.path || "/"}`;

async function clear(spec) {
  for (const domain of spec.domains) {
    for (const cookie of await chrome.cookies.getAll({ domain })) {
      await chrome.cookies.remove({ url: urlOf(cookie), name: cookie.name, storeId: cookie.storeId });
    }
  }
}

async function put(cookie) {
  const details = { url: urlOf(cookie), name: cookie.name, value: cookie.value, path: cookie.path, secure: cookie.secure, httpOnly: cookie.httpOnly };
  if (!cookie.hostOnly) details.domain = cookie.domain;
  if (cookie.sameSite && cookie.sameSite !== "unspecified") details.sameSite = cookie.sameSite;
  if (cookie.expirationDate) details.expirationDate = cookie.expirationDate;
  try { await chrome.cookies.set(details); } catch {}
}

async function tabsOf(spec) {
  return chrome.tabs.query({ url: spec.domains.map((domain) => `https://${domain}/*`) });
}

async function reload(spec) {
  for (const tab of await tabsOf(spec)) chrome.tabs.reload(tab.id);
}

async function signIn(spec, email) {
  const tabs = await tabsOf(spec);
  if (tabs.length) {
    await chrome.tabs.update(tabs[0].id, { url: spec.login });
    for (const tab of tabs.slice(1)) chrome.tabs.reload(tab.id);
  } else {
    await chrome.tabs.create({ url: spec.login, active: false });
  }
  chrome.notifications?.create(`sign-in:${spec.tool}`, {
    type: "basic", iconUrl: "icon-128.png", title: `Sign in as ${email}`,
    message: `Keyhop moved ${spec.tool === "claude" ? "Claude" : "Codex"} to ${email}. Sign in on ${spec.domains[0]} once and Keyhop keeps it for the next hop.`,
  });
  badge();
}

// MARK: Noticing a sign-in

// A sign-in on the site by hand is kept for that account, so the next hop to it needs no password.
const pending = new Map();
chrome.cookies.onChanged.addListener(({ cookie, removed }) => {
  if (removed) return;
  for (const [name, spec] of Object.entries(SITES)) {
    if (!spec.domains.some((domain) => cookie.domain.replace(/^\./, "").endsWith(domain))) continue;
    if (!spec.session.some((key) => cookie.name.startsWith(key)) || busy.has(name)) continue;
    clearTimeout(pending.get(name));
    pending.set(name, setTimeout(async () => {
      if (busy.has(name)) return;
      const now = await who(name);
      if (now) await keep(name, now);
      badge();
    }, 2500));
  }
});

// MARK: Badge and popup

function badge() {
  const needs = Object.values(status.sites).some((site) => site.needs);
  chrome.action.setBadgeBackgroundColor({ color: needs || !status.connected ? "#e5484d" : "#2563eb" });
  chrome.action.setBadgeText({ text: !status.connected ? "!" : needs ? "1" : "" });
}

chrome.runtime.onMessage.addListener((message, _sender, reply) => {
  if (message.type === "status") {
    reply(status);
    return false;
  }
  if (message.type === "sync") {
    (async () => {
      for (const name of Object.keys(SITES)) {
        const now = await who(name);
        if (now) await keep(name, now);
      }
      if (!port) connect(); else send({ type: "hello", version: chrome.runtime.getManifest().version });
      reply(status);
    })();
    return true;
  }
  return false;
});

chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
// A worker that was put to sleep wakes here and reconnects; an open port keeps it awake.
chrome.alarms.create("keyhop", { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener(connect);
connect();
"""##

    static let popup = ##"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Keyhop</title>
<style>
  :root { color-scheme: light dark; --bg: #fff; --text: #0b0d12; --muted: #5d6472; --line: #e7e9ee; --good: #16a34a; --bad: #e5484d; --blue: #2563eb; }
  @media (prefers-color-scheme: dark) { :root { --bg: #111317; --text: #f2f4f7; --muted: #9aa1ad; --line: #252830; } }
  body { margin: 0; width: 300px; background: var(--bg); color: var(--text); font: 13px/1.4 -apple-system, BlinkMacSystemFont, "Inter", "Segoe UI", sans-serif; }
  header { display: flex; align-items: center; gap: 8px; padding: 12px 14px; border-bottom: 1px solid var(--line); }
  header img { width: 20px; height: 20px; border-radius: 5px; }
  header b { flex: 1; }
  .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--bad); }
  .dot.on { background: var(--good); }
  .site { padding: 10px 14px; border-bottom: 1px solid var(--line); }
  .site b { display: block; margin-bottom: 2px; }
  .row { display: flex; justify-content: space-between; gap: 8px; color: var(--muted); }
  .row span:last-child { color: var(--text); text-align: right; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .needs { margin-top: 6px; color: var(--bad); }
  .note { padding: 10px 14px; color: var(--muted); }
  footer { padding: 10px 14px; }
  button { width: 100%; height: 30px; border: 0; border-radius: 7px; background: var(--blue); color: #fff; font: inherit; font-weight: 600; cursor: pointer; }
</style>
</head>
<body>
<header><img src="icon-32.png" alt=""><b>Keyhop</b><span class="dot" id="dot"></span></header>
<main id="sites"></main>
<footer><button id="sync" type="button">Sync now</button></footer>
<script src="popup.js"></script>
</body>
</html>
"""##

    static let popupScript = ##"""
const NAMES = { "claude.ai": "claude.ai · Claude Code", "chatgpt.com": "chatgpt.com · Codex" };

function text(value) {
  const span = document.createElement("span");
  span.textContent = value;
  return span;
}

function draw(status) {
  document.getElementById("dot").className = status?.connected ? "dot on" : "dot";
  const root = document.getElementById("sites");
  root.replaceChildren();
  if (!status?.connected) {
    const note = document.createElement("p");
    note.className = "note";
    note.textContent = `Keyhop isn't connected. Run keyhop browser install, then reload this extension.${status?.error ? ` (${status.error})` : ""}`;
    root.append(note);
    return;
  }
  for (const name of Object.keys(NAMES)) {
    const site = status.sites[name] || {};
    const block = document.createElement("section");
    block.className = "site";
    const title = document.createElement("b");
    title.textContent = NAMES[name];
    block.append(title);
    for (const [label, value] of [["Keyhop uses", site.keyhop?.email || "No saved account"], ["Signed in here", site.browser || "Not yet"], ["Saved for hops", String(site.saved ?? 0)]]) {
      const row = document.createElement("div");
      row.className = "row";
      row.append(text(label), text(value));
      block.append(row);
    }
    if (site.needs) {
      const needs = document.createElement("div");
      needs.className = "needs";
      needs.textContent = `Sign in as ${site.needs} once.`;
      block.append(needs);
    }
    root.append(block);
  }
}

chrome.runtime.sendMessage({ type: "status" }, draw);
document.getElementById("sync").addEventListener("click", () => chrome.runtime.sendMessage({ type: "sync" }, draw));
"""##
}
