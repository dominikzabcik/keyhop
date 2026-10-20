// Loads Keyhop's Chrome extension in Chromium against the real native host (the built binary)
// and walks a hop both ways. claude.ai isn't reached: who is signed in is read from the cookie.
// Run after swift build: node e2e/browser/extension.mjs
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const repo = path.resolve(new URL("../..", import.meta.url).pathname);
const binary = path.join(repo, ".build/debug/Keyhop");
const root = fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), "keyhop-ext-"));
const data = path.join(root, "data"), home = path.join(root, "home"), profile = path.join(root, "profile");
for (const dir of [data, home, profile]) fs.mkdirSync(dir, { recursive: true });
const A = "11111111-1111-1111-1111-111111111111", B = "22222222-2222-2222-2222-222222222222";
fs.writeFileSync(path.join(data, "accounts.json"), JSON.stringify([
  { id: A, provider: "claude", identity: "uuid-a|org", email: "a@x.dev", addedAt: "2026-10-01T00:00:00Z" },
  { id: B, provider: "claude", identity: "uuid-b|org", email: "b@x.dev", addedAt: "2026-10-01T00:00:00Z" },
]));
const use = (id) => { fs.writeFileSync(path.join(data, ".s"), JSON.stringify({ usage: {}, active: { claude: id }, cursorExports: {}, sentAlerts: {} })); fs.renameSync(path.join(data, ".s"), path.join(data, "cli-state.json")); };
use(A);
const env = { ...process.env, KEYHOP_DATA_DIR: data, KEYHOP_SECRET_STORE: "file", HOME: home };
execFileSync(binary, ["browser", "install"], { env });
const ext = path.join(data, "Chrome Extension");
const registered = fs.readdirSync(path.join(home, ".config"), { recursive: true }).filter((f) => f.endsWith("app.keyhop.browser.json"));
fs.mkdirSync(path.join(profile, "NativeMessagingHosts"), { recursive: true });
fs.copyFileSync(path.join(home, ".config", registered[0]), path.join(profile, "NativeMessagingHosts/app.keyhop.browser.json"));

const context = await chromium.launchPersistentContext(profile, {
  headless: true, channel: "chromium", env,
  args: [`--disable-extensions-except=${ext}`, `--load-extension=${ext}`],
});
let [worker] = context.serviceWorkers();
worker ||= await context.waitForEvent("serviceworker");
const id = new URL(worker.url()).host;
if (id !== "jghheogemlfdoplloeaiffadakpfjhna") { console.log("FAILED: the manifest key gives the extension", id); process.exitCode = 1; }
// claude.ai can't be reached here, so who-is-signed-in answers from the sessionKey cookie.
await worker.evaluate(() => {
  globalThis.fetch = async (url) => {
    const [cookie] = await chrome.cookies.getAll({ domain: "claude.ai", name: "sessionKey" });
    const who = { "sk-a": ["a@x.dev", "uuid-a"], "sk-b": ["b@x.dev", "uuid-b"] }[cookie?.value];
    if (!who || !String(url).includes("/api/account")) return new Response("{}", { status: 401 });
    return new Response(JSON.stringify({ email_address: who[0], uuid: who[1] }), { status: 200 });
  };
});
const popup = await context.newPage();
await popup.goto(`chrome-extension://${id}/popup.html`);
const status = () => popup.evaluate(() => new Promise((r) => chrome.runtime.sendMessage({ type: "status" }, r))).catch(() => null);
const session = async () => (await context.cookies("https://claude.ai")).find((c) => c.name === "sessionKey")?.value || "(none)";
const vault = () => fs.existsSync(path.join(data, "vault")) ? fs.readdirSync(path.join(data, "vault")).sort() : [];
const wait = async (what, test, ms = 15000) => {
  const end = Date.now() + ms;
  while (Date.now() < end) { if (await test()) return console.log("ok:", what); await new Promise((r) => setTimeout(r, 300)); }
  console.log("FAILED:", what, JSON.stringify(await status()), await session(), vault()); process.exitCode = 1;
};

// Reconnect so the hello runs after fetch is stubbed.
await popup.evaluate(() => new Promise((r) => chrome.runtime.sendMessage({ type: "sync" }, r)));
await context.addCookies([{ name: "sessionKey", value: "sk-a", domain: ".claude.ai", path: "/", secure: true, httpOnly: true, sameSite: "Lax", expires: 1900000000 }]);
await wait("connected to the host", async () => (await status())?.connected);
await wait("the browser's login is kept for a@x.dev", async () => vault().includes(`web-${A}`));
use(B);
await wait("a hop to b@x.dev with no site login asks to sign in", async () => (await status())?.sites?.["claude.ai"]?.needs === "b@x.dev" && (await session()) === "(none)");
await context.addCookies([{ name: "sessionKey", value: "sk-b", domain: ".claude.ai", path: "/", secure: true, httpOnly: true, sameSite: "Lax", expires: 1900000000 }]);
await wait("signing in as b@x.dev by hand is kept", async () => vault().includes(`web-${B}`));
use(A);
await wait("hopping back puts a@x.dev's login back", async () => (await session()) === "sk-a");
use(B);
await wait("and b@x.dev's again, with no sign-in", async () => (await session()) === "sk-b" && !(await status())?.sites?.["claude.ai"]?.needs);
await popup.reload();
const shown = await popup.locator("body").innerText();
if (!shown.includes("b@x.dev")) { console.log("FAILED: the popup names the account", shown); process.exitCode = 1; }
await context.close();
fs.rmSync(root, { recursive: true, force: true });
