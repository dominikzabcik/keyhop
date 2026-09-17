import { env, exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { addDays, today } from "../src/env";
import { streaks } from "../src/stats";
import { currentSeason, daysLeft, nextStep, seasonRange, tierFor } from "../src/seasons";
import { parseUsage } from "../src/usage";
import { LIMIT_TTL_SECONDS, clean, parseLimits, sweepLimits } from "../src/limits";
import { badgesFrom, questsFrom } from "../src/quests";
import { webLink } from "../src/account";

const BASE = "http://localhost";

function call(path: string, init: RequestInit = {}): Promise<Response> {
  return exports.default.fetch(new Request(`${BASE}${path}`, { redirect: "manual", ...init }));
}

/** Signs in through the development login and returns the session cookie. */
async function signIn(login: string): Promise<string> {
  const response = await call(`/auth/dev?login=${login}&next=/leaderboard`);
  expect(response.status).toBe(302);
  const cookie = response.headers.getSetCookie().find((value) => value.startsWith("keyhop_session="));
  expect(cookie).toBeDefined();
  return cookie!.split(";")[0];
}

/** Posts a form the way Keyhop's pages do: same origin, with the session cookie. */
function form(path: string, cookie: string, fields: Record<string, string> = {}, origin = BASE): Promise<Response> {
  return call(path, { method: "POST", headers: { cookie, origin }, body: new URLSearchParams(fields) });
}

/** Links an app the way Keyhop does and returns its bearer token. */
/** Each linked app comes from its own address, so one test's linking never uses up another's allowance. */
let linkedApps = 0;

async function linkApp(cookie: string): Promise<string> {
  const from = { "cf-connecting-ip": `10.0.0.${++linkedApps}` };
  const start = await call("/api/device/start", { method: "POST", headers: from, body: JSON.stringify({ label: "Test Mac" }) });
  const { deviceCode, userCode } = (await start.json()) as { deviceCode: string; userCode: string };
  const approved = await form("/link", cookie, { code: userCode });
  expect(approved.headers.get("location")).toBe("/link?done=1");
  const token = await call("/api/device/token", { method: "POST", headers: from, body: JSON.stringify({ deviceCode }) });
  expect(token.status).toBe(200);
  return ((await token.json()) as { token: string }).token;
}

function upload(token: string, days: unknown[]): Promise<Response> {
  return call("/api/usage", { method: "POST", headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ days }) });
}

/** Links a read-only companion the way the phone does, and returns its bearer token. */
async function linkPhone(cookie: string): Promise<string> {
  const from = { "cf-connecting-ip": `10.0.2.${++linkedApps}` };
  const start = await call("/api/device/start", {
    method: "POST",
    headers: from,
    body: JSON.stringify({ label: "Test phone", access: "read" }),
  });
  const { deviceCode, userCode } = (await start.json()) as { deviceCode: string; userCode: string };
  await form("/link", cookie, { code: userCode });
  const grant = await call("/api/device/token", { method: "POST", headers: from, body: JSON.stringify({ deviceCode }) });
  expect(grant.status).toBe(200);
  return ((await grant.json()) as { token: string }).token;
}

function sendLimits(token: string, list: unknown[]): Promise<Response> {
  return call("/api/limits", { method: "POST", headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ limits: list }) });
}

function readLimits(token: string): Promise<Response> {
  return call("/api/limits", { headers: { authorization: `Bearer ${token}` } });
}

describe("usage uploads", () => {
  const day = today();

  it("accepts daily totals per tool", () => {
    const result = parseUsage({ days: [{ day, tool: "claude", tokens: 1200, cost: 1.5, requests: 3 }] }, day);
    expect(result).toEqual({ days: [{ day, tool: "claude", tokens: 1200, costMicros: 1_500_000, requests: 3 }] });
    expect(parseUsage({ days: [{ day, tool: "gemini", tokens: 800, cost: 0.5, requests: 2 }] }, day)).toEqual({
      days: [{ day, tool: "gemini", tokens: 800, costMicros: 500_000, requests: 2 }],
    });
  });

  it("refuses impossible dates, unknown tools, duplicates and negative numbers", () => {
    const entry = { day, tool: "claude", tokens: 1, cost: 0, requests: 1 };
    expect(parseUsage({ days: [{ ...entry, day: "2026-02-30" }] }, day)).toHaveProperty("error");
    expect(parseUsage({ days: [{ ...entry, day: addDays(day, -500) }] }, day)).toHaveProperty("error");
    expect(parseUsage({ days: [{ ...entry, tool: "notepad" }] }, day)).toHaveProperty("error");
    expect(parseUsage({ days: [entry, entry] }, day)).toHaveProperty("error");
    expect(parseUsage({ days: [{ ...entry, tokens: -5 }] }, day)).toHaveProperty("error");
    expect(parseUsage({ days: [{ ...entry, tokens: 1.5 }] }, day)).toHaveProperty("error");
    expect(parseUsage({ nope: true }, day)).toHaveProperty("error");
  });

  it("counts streaks that end today or yesterday", () => {
    const reference = "2026-09-11";
    const active = new Set(["2026-09-10", "2026-09-09", "2026-09-08", "2026-09-01", "2026-09-02"]);
    expect(streaks(active, reference)).toEqual({ current: 3, longest: 3 });
    expect(streaks(new Set(["2026-09-05"]), reference)).toEqual({ current: 0, longest: 1 });
  });
});

describe("linking the app", () => {
  it("waits for approval in the browser, then hands the app a token once", async () => {
    const start = await call("/api/device/start", { method: "POST", body: JSON.stringify({ label: "Studio Mac" }) });
    const { deviceCode, userCode, verifyUrl } = (await start.json()) as { deviceCode: string; userCode: string; verifyUrl: string };
    expect(userCode).toMatch(/^[A-Z2-9]{4}-[A-Z2-9]{4}$/);
    expect(verifyUrl).toBe(`${BASE}/link?code=${userCode}`);

    const pending = await call("/api/device/token", { method: "POST", body: JSON.stringify({ deviceCode }) });
    expect(pending.status).toBe(428);

    const cookie = await signIn("linker");
    expect((await form("/link", cookie, { code: userCode })).headers.get("location")).toBe("/link?done=1");

    const granted = await call("/api/device/token", { method: "POST", body: JSON.stringify({ deviceCode }) });
    const { token, user } = (await granted.json()) as { token: string; user: { login: string } };
    expect(user.login).toBe("linker");

    const me = await call("/api/me", { headers: { authorization: `Bearer ${token}` } });
    expect(((await me.json()) as { user: { login: string } }).user.login).toBe("linker");

    const again = await call("/api/device/token", { method: "POST", body: JSON.stringify({ deviceCode }) });
    expect(again.status).toBe(410);
  });

  it("doesn't accept an app token as a browser session, or the reverse", async () => {
    const cookie = await signIn("mixer");
    const token = await linkApp(cookie);
    const asCookie = await call("/api/me", { headers: { cookie: `keyhop_session=${token}` } });
    expect(asCookie.status).toBe(401);
    const asBearer = await call("/api/me", { headers: { authorization: `Bearer ${cookie.split("=")[1]}` } });
    expect(asBearer.status).toBe(401);
    const browserAtApi = await call("/api/me", { headers: { cookie } });
    expect(browserAtApi.status).toBe(401);
    const appAtSettings = await call("/settings/delete", {
      method: "POST",
      headers: { authorization: `Bearer ${token}` },
      body: new URLSearchParams({ confirm: "mixer" }),
    });
    expect(appAtSettings.status).toBe(403);
    expect((await call("/api/me", { headers: { authorization: `Bearer ${token}` } })).status).toBe(200);
  });

  it("allows only one browser session to claim a device code", async () => {
    const start = await call("/api/device/start", { method: "POST", body: JSON.stringify({ label: "Shared Mac" }) });
    const { userCode } = (await start.json()) as { userCode: string };
    const first = await signIn("first-claim");
    const second = await signIn("second-claim");
    const [one, two] = await Promise.all([form("/link", first, { code: userCode }), form("/link", second, { code: userCode })]);
    expect([one.headers.get("location"), two.headers.get("location")].sort()).toEqual([
      `/link?code=${encodeURIComponent(userCode)}&error=expired`,
      "/link?done=1",
    ]);
  });

  it("redeems an approved device code only once under concurrent polling", async () => {
    const from = { "cf-connecting-ip": "10.0.1.1" };
    const start = await call("/api/device/start", {
      method: "POST",
      headers: from,
      body: JSON.stringify({ label: "Fast phone" }),
    });
    const { deviceCode, userCode } = (await start.json()) as { deviceCode: string; userCode: string };
    const cookie = await signIn("parallel-linker");
    expect((await form("/link", cookie, { code: userCode })).headers.get("location")).toBe("/link?done=1");

    const polls = await Promise.all([
      call("/api/device/token", { method: "POST", headers: from, body: JSON.stringify({ deviceCode }) }),
      call("/api/device/token", { method: "POST", headers: from, body: JSON.stringify({ deviceCode }) }),
    ]);
    expect(polls.map((response) => response.status).sort()).toEqual([200, 410]);

    const granted = polls.find((response) => response.status === 200)!;
    const { token } = (await granted.json()) as { token: string };
    expect((await call("/api/me", { headers: { authorization: `Bearer ${token}` } })).status).toBe(200);
  });

  it("keeps a phone link read-only and lets it revoke itself", async () => {
    const from = { "cf-connecting-ip": "10.0.1.2" };
    const start = await call("/api/device/start", {
      method: "POST",
      headers: from,
      body: JSON.stringify({ label: "Test phone", access: "read" }),
    });
    const { deviceCode, userCode } = (await start.json()) as { deviceCode: string; userCode: string };
    const cookie = await signIn("phone-reader");
    const approval = await call(`/link?code=${userCode}`, { headers: { cookie } });
    const approvalBody = await approval.text();
    expect(approvalBody).toContain("Test phone");
    expect(approvalBody).toContain("It cannot upload usage or change your profile.");
    await form("/link", cookie, { code: userCode });
    const grant = await call("/api/device/token", { method: "POST", headers: from, body: JSON.stringify({ deviceCode }) });
    const { token } = (await grant.json()) as { token: string };
    const authorization = { authorization: `Bearer ${token}` };

    expect((await call("/api/me", { headers: authorization })).status).toBe(200);
    expect((await upload(token, [])).status).toBe(403);
    expect((await call("/api/me", { method: "PATCH", headers: authorization, body: JSON.stringify({ public: true }) })).status).toBe(403);
    expect((await call("/api/session", { method: "DELETE", headers: authorization })).status).toBe(204);
    expect((await call("/api/me", { headers: authorization })).status).toBe(401);
  });
});

describe("leaderboards", () => {
  it("renders the product landing page at the root", async () => {
    const page = await call("/");
    expect(page.status).toBe(200);
    const body = await page.text();
    expect(body).toContain("Every account.");
    expect(body).toContain("Download Keyhop");
    expect(body).toContain("Your work never leaves your computer.");
    expect(body).toContain('id="product"');
    // The tools table names every tool Keyhop ships.
    for (const name of ["Claude Code", "Cursor", "Codex", "Gemini CLI", "OpenCode", "Pi", "GitHub Copilot", "Windsurf", "Codebuff"]) {
      expect(body).toContain(`${name}</th>`);
    }
    expect(body).toContain("keyhop_recommendation");
    expect(body).toContain('<link rel="canonical" href="https://keyhop.app/">');
    expect(body).toContain('<meta name="robots" content="index, follow, max-image-preview:large">');
    expect(body).toContain('<script type="application/ld+json"');
    expect(body).toContain('"@type":"SoftwareApplication"');
  });

  it("ranks public profiles only, by the chosen measure", async () => {
    const day = today();
    const alice = await linkApp(await signIn("alice"));
    const bob = await linkApp(await signIn("bob"));
    await call("/api/me", { method: "PATCH", headers: { authorization: `Bearer ${alice}` }, body: JSON.stringify({ public: true }) });

    expect((await upload(alice, [{ day, tool: "claude", tokens: 5000, cost: 2, requests: 10 }])).status).toBe(200);
    expect((await upload(bob, [{ day, tool: "codex", tokens: 9000, cost: 1, requests: 4 }])).status).toBe(200);

    const before = (await (await call("/api/leaderboard?period=today")).json()) as { entries: { login: string }[] };
    expect(before.entries.map((entry) => entry.login)).toEqual(["alice"]);

    await call("/api/me", { method: "PATCH", headers: { authorization: `Bearer ${bob}` }, body: JSON.stringify({ public: true }) });
    const byTokens = (await (await call("/api/leaderboard?period=today&metric=tokens")).json()) as { entries: { login: string }[] };
    expect(byTokens.entries.map((entry) => entry.login)).toEqual(["bob", "alice"]);
    const byCost = (await (await call("/api/leaderboard?period=today&metric=cost")).json()) as { entries: { login: string; cost: number }[] };
    expect(byCost.entries.map((entry) => [entry.login, entry.cost])).toEqual([["alice", 2], ["bob", 1]]);

    // Uploading the same day again replaces it rather than adding to it.
    await upload(alice, [{ day, tool: "claude", tokens: 20000, cost: 2, requests: 10 }]);
    const replaced = (await (await call("/api/leaderboard?period=today")).json()) as { entries: { login: string; tokens: number }[] };
    expect(replaced.entries[0]).toMatchObject({ login: "alice", tokens: 20000 });
  });

  it("renders the leaderboard page with the podium", async () => {
    const page = await call("/leaderboard?period=all&metric=tokens");
    expect(page.status).toBe(200);
    expect(page.headers.get("content-security-policy")).toContain("default-src 'none'");
    const body = await page.text();
    expect(body).toContain("<h1>Leaderboard</h1>");
    // The only script is the backdrop, allowed by this response's nonce.
    const nonce = page.headers.get("content-security-policy")!.match(/script-src 'nonce-([^']+)'/)?.[1];
    expect(nonce).toBeTruthy();
    expect(body.match(/<script\b[^>]*>/g)).toEqual([`<script nonce="${nonce}">`]);
  });
});

describe("public site", () => {
  it.each([
    ["/download", "Ready on every desktop."],
    ["/privacy", "Your work is not the product."],
    ["/terms", "Use Keyhop with accounts that are yours."],
    ["/security", "Report problems privately."],
  ])("renders %s with canonical metadata", async (path, heading) => {
    const page = await call(path);
    expect(page.status).toBe(200);
    const body = await page.text();
    expect(body).toContain(`<h1>${heading}</h1>`);
    expect(body).toContain(`<link rel="canonical" href="https://keyhop.app${path}">`);
    expect(body).toContain('<meta property="og:image"');
  });

  it("publishes crawler and security discovery files", async () => {
    const robots = await call("/robots.txt");
    expect(robots.headers.get("content-type")).toContain("text/plain");
    const robotsBody = await robots.text();
    expect(robotsBody).toContain("Sitemap: https://keyhop.app/sitemap.xml");
    expect(robotsBody).not.toContain("Disallow: /login");

    const sitemap = await call("/sitemap.xml");
    expect(sitemap.headers.get("content-type")).toContain("application/xml");
    const sitemapBody = await sitemap.text();
    expect(sitemapBody).toContain("<loc>https://keyhop.app/download</loc>");
    expect(sitemapBody).toContain("<loc>https://keyhop.app/privacy</loc>");

    const security = await call("/.well-known/security.txt");
    expect(security.headers.get("content-type")).toContain("text/plain");
    expect(await security.text()).toContain("Contact: https://github.com/dominikzabcik/keyhop/security/advisories/new");
  });

  it("keeps sign-in and error pages out of search results", async () => {
    for (const path of ["/login?next=/settings", "/does-not-exist"]) {
      const page = await call(path);
      expect(page.headers.get("x-robots-tag")).toBe("noindex, nofollow");
      expect(await page.text()).toContain('<meta name="robots" content="noindex, nofollow">');
    }
  });

  it("indexes only public profile pages", async () => {
    const cookie = await signIn("searchable");
    const privateProfile = await call("/u/searchable", { headers: { cookie } });
    expect(privateProfile.headers.get("x-robots-tag")).toBe("noindex, nofollow");

    await form("/settings/profile", cookie, { public: "on" });
    const publicProfile = await call("/u/searchable");
    expect(publicProfile.headers.get("x-robots-tag")).toBeNull();
    expect(await publicProfile.text()).toContain('<meta name="robots" content="index, follow, max-image-preview:large">');

    const sitemap = await call("/sitemap.xml");
    expect(await sitemap.text()).toContain("<loc>https://keyhop.app/u/searchable</loc>");
  });
});

describe("ranked seasons", () => {
  it("puts tokens on the ladder, with three divisions inside each tier", () => {
    expect(tierFor(0)).toMatchObject({ key: "bronze", division: 3 });
    expect(tierFor(249_000_000)).toMatchObject({ key: "bronze", division: 1 });
    expect(tierFor(250_000_000)).toMatchObject({ key: "silver", division: 3 });
    expect(tierFor(2_000_000_000)).toMatchObject({ key: "gold" });
    expect(tierFor(50_000_000_000)).toMatchObject({ key: "master", division: null });
    expect(nextStep(50_000_000_000)).toBeNull();
    expect(nextStep(0)?.tokens).toBeGreaterThan(0);
  });

  it("counts a season as its own calendar month, stopping at today", () => {
    expect(seasonRange("2026-09", "2026-09-13")).toEqual({ from: "2026-09-01", to: "2026-09-13", over: false });
    expect(seasonRange("2026-09", "2026-10-04")).toEqual({ from: "2026-09-01", to: "2026-09-30", over: true });
    expect(daysLeft("2026-09", "2026-09-30")).toBe(1);
    expect(daysLeft("2026-09", "2026-10-01")).toBe(0);
    expect(currentSeason("2026-09-13")).toBe("2026-09");
  });

  it("ranks the season and tells you your own place", async () => {
    const day = today();
    const ivan = await linkApp(await signIn("ivan"));
    await call("/api/me", { method: "PATCH", headers: { authorization: `Bearer ${ivan}` }, body: JSON.stringify({ public: true }) });
    await upload(ivan, [{ day, tool: "claude", tokens: 300_000_000, cost: 12, requests: 900 }]);

    const response = await call("/api/season", { headers: { authorization: `Bearer ${ivan}` } });
    const body = (await response.json()) as {
      season: string;
      you: { rank: number; tier: { key: string }; next: { tokens: number } };
      entries: { login: string; tier: { key: string } }[];
    };
    expect(body.season).toBe(currentSeason());
    expect(body.you.rank).toBe(1);
    expect(body.you.tier.key).toBe("silver");
    expect(body.you.next.tokens).toBeGreaterThan(0);
    expect(body.entries.find((entry) => entry.login === "ivan")?.tier.key).toBe("silver");

    // A month Keyhop never ran isn't a season.
    expect((await call("/api/season?season=2020-01")).status).toBe(400);
  });

  it("renders the season page with the ladder", async () => {
    const page = await call("/season");
    expect(page.status).toBe(200);
    const body = await page.text();
    expect(body).toContain("<h1>Season</h1>");
    expect(body).toContain("The ladder");
  });
});

describe("teams", () => {
  it("creates a team, invites someone and ranks every member, private or not", async () => {
    const day = today();
    const carol = await signIn("carol");
    const created = await form("/teams", carol, { name: "Night Shift" });
    expect(created.headers.get("location")).toBe("/t/night-shift");

    const invited = await form("/t/night-shift/invites", carol);
    const code = new URL(invited.headers.get("location")!, BASE).searchParams.get("invite")!;
    expect(code.length).toBeGreaterThan(10);

    const dave = await signIn("dave");
    const invitePage = await call(`/invite/${code}`, { headers: { cookie: dave } });
    expect(await invitePage.text()).toContain("Join Night Shift");
    expect((await form(`/invite/${code}`, dave)).headers.get("location")).toBe("/t/night-shift");

    const daveToken = await linkApp(dave);
    await upload(daveToken, [{ day, tool: "cursor", tokens: 777, cost: 0.5, requests: 2 }]);

    const board = await call("/api/leaderboard?period=today&team=night-shift", { headers: { authorization: `Bearer ${daveToken}` } });
    const entries = ((await board.json()) as { entries: { login: string; isYou: boolean }[] }).entries;
    expect(entries).toEqual([expect.objectContaining({ login: "dave", isYou: true })]);

    const outsider = await signIn("eve");
    expect((await call("/t/night-shift", { headers: { cookie: outsider } })).status).toBe(404);

    // Turning invites off stops the old link.
    await form("/t/night-shift/invites/revoke", carol);
    expect((await call(`/invite/${code}`, { headers: { cookie: outsider } })).status).toBe(404);
  });
});

describe("privacy and safety", () => {
  it("keeps private profiles to their owner", async () => {
    const frank = await signIn("frank");
    expect((await call("/u/frank")).status).toBe(404);
    expect((await call("/u/frank", { headers: { cookie: frank } })).status).toBe(200);
  });

  it("refuses cookie changes from another site", async () => {
    const grace = await signIn("grace");
    const response = await form("/settings/profile", grace, { public: "on" }, "https://evil.example");
    expect(response.status).toBe(403);
  });

  it("offers the development login on localhost only", async () => {
    const response = await exports.default.fetch(new Request("https://keyhop.example/auth/dev?login=mallory", { redirect: "manual" }));
    expect(response.status).toBe(404);
  });

  it("deletes an account with everything it synced", async () => {
    const heidi = await signIn("heidi");
    const token = await linkApp(heidi);
    await upload(token, [{ day: today(), tool: "claude", tokens: 10, cost: 0, requests: 1 }]);
    expect((await form("/settings/delete", heidi, { confirm: "heidi" })).headers.get("location")).toBe("/leaderboard");
    expect((await call("/api/me", { headers: { authorization: `Bearer ${token}` } })).status).toBe(401);
  });
});

describe("quests and badges", () => {
  const rows = (entries: [string, string, number][]) => entries.map(([day, tool, tokens]) => ({ day, tool: tool as never, tokens }));

  it("measures today's and this week's goals", () => {
    const reference = "2026-09-13";
    const list = questsFrom(
      rows([
        [reference, "claude", 5000],
        [reference, "cursor", 2000],
        ["2026-09-12", "claude", 1000],
        ["2026-09-11", "claude", 1000],
        ["2026-09-10", "codex", 1000],
        ["2026-09-09", "claude", 1000],
        ["2026-09-08", "gemini", 1000],
        [reference, "opencode", 1000],
        [reference, "pi", 1000],
      ]),
      reference,
    );
    const by = Object.fromEntries(list.map((entry) => [entry.key, entry]));
    expect(by["today"].complete).toBe(true);
    expect(by["two-tools"]).toMatchObject({ done: 2, target: 2, complete: true });
    expect(by["beat-yesterday"].complete).toBe(true);
    expect(by["five-days"]).toMatchObject({ done: 5, complete: true });
    expect(by["every-tool"]).toMatchObject({ done: 6, target: 6, complete: true });
  });

  it("leaves a goal short when the days do not add up", () => {
    const reference = "2026-09-13";
    const by = Object.fromEntries(questsFrom(rows([[reference, "claude", 10]]), reference).map((entry) => [entry.key, entry]));
    expect(by["two-tools"]).toMatchObject({ done: 1, complete: false });
    expect(by["five-days"]).toMatchObject({ done: 1, complete: false });
  });

  it("does not let quota-only tools distort tracked-tool goals", () => {
    const reference = "2026-09-13";
    const tracked: [string, string, number][] = ["claude", "cursor", "codex", "gemini", "opencode", "pi"].map((tool) => [
      reference,
      tool,
      1,
    ]);
    tracked.push([reference, "copilot", 1], [reference, "windsurf", 1], [reference, "codebuff", 1]);
    const data = rows(tracked);
    const quests = Object.fromEntries(questsFrom(data, reference).map((entry) => [entry.key, entry]));
    const badges = Object.fromEntries(badgesFrom(data, { top3: false, bestTier: null }, reference).map((entry) => [entry.key, entry]));
    expect(quests["every-tool"]).toMatchObject({ done: 6, target: 6, complete: true });
    expect(badges["all-tools"].earned).toBe(true);
  });

  it("earns badges from the days themselves", () => {
    const reference = "2026-09-13";
    const entries: [string, string, number][] = Array.from({ length: 7 }, (_, back) => [addDays(reference, -back), "claude", 1000]);
    entries.push(
      [reference, "cursor", 1],
      [reference, "codex", 1],
      [reference, "gemini", 1],
      [reference, "opencode", 1],
      [reference, "pi", 1],
    );
    const by = Object.fromEntries(badgesFrom(rows(entries), { top3: false, bestTier: null }, reference).map((entry) => [entry.key, entry]));
    expect(by["first-sync"].earned).toBe(true);
    expect(by["streak-7"]).toMatchObject({ earned: true, day: reference });
    expect(by["streak-30"].earned).toBe(false);
    expect(by["all-tools"]).toMatchObject({ earned: true, day: reference });
    expect(by["billion"].earned).toBe(false);
  });

  it("earns the token badges once the running total passes them", () => {
    const by = Object.fromEntries(
      badgesFrom(
        rows([["2026-09-01", "claude", 600_000_000], ["2026-09-02", "claude", 600_000_000]]),
        { top3: true, bestTier: "gold" },
        "2026-09-13",
      ).map((entry) => [entry.key, entry]),
    );
    expect(by["billion"]).toMatchObject({ earned: true, day: "2026-09-02" });
    expect(by["ten-billion"].earned).toBe(false);
    expect(by["climber"].earned).toBe(true);
    expect(by["podium"].earned).toBe(true);
  });
});

describe("link abuse controls", () => {
  it("slows a device that polls too quickly", async () => {
    const start = await call("/api/device/start", { method: "POST", body: JSON.stringify({ label: "Noisy Mac" }) });
    const { deviceCode } = (await start.json()) as { deviceCode: string };
    let response: Response | undefined;
    for (let attempt = 0; attempt < 31; attempt++) {
      response = await call("/api/device/token", { method: "POST", body: JSON.stringify({ deviceCode }) });
    }
    expect(response?.status).toBe(429);
    expect(response?.headers.get("retry-after")).toBe("10");
  });
});

describe("profiles", () => {
  it("stores a link only when it is a web address", () => {
    expect(webLink("keyhop.app")).toBe("https://keyhop.app/");
    expect(webLink("https://example.dev/me")).toBe("https://example.dev/me");
    expect(webLink("  ")).toBeNull();
    expect(webLink(undefined)).toBeNull();
    expect(webLink("javascript:alert(1)")).toBeNull();
    expect(webLink("mailto:me@example.dev")).toBeNull();
  });

  it("shows the chosen name, keeps the GitHub one, and serves a card", async () => {
    const cookie = await signIn("nadia");
    const token = await linkApp(cookie);
    await call("/api/me", { method: "PATCH", headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ public: true }) });
    await upload(token, [{ day: today(), tool: "claude", tokens: 4200, cost: 1, requests: 5 }]);

    const saved = await form("/settings/profile", cookie, { public: "on", display_name: "Nadia K.", bio: "Ships at night.", link: "example.dev" });
    expect(saved.headers.get("location")).toBe("/settings?saved=1");

    const page = await (await call("/u/nadia")).text();
    expect(page).toContain("Nadia K.");
    expect(page).toContain("Ships at night.");
    expect(page).toContain("https://example.dev/");

    const card = await call("/u/nadia/card.svg");
    expect(card.status).toBe(200);
    expect(card.headers.get("content-type")).toContain("image/svg+xml");
    const svg = await card.text();
    expect(svg).toContain("<svg");
    expect(svg).toContain("Nadia K.");
  });

  it("refuses a link that is not http or https, and keeps the rest", async () => {
    const cookie = await signIn("oscar");
    const rejected = await form("/settings/profile", cookie, { public: "on", display_name: "Oscar", link: "javascript:alert(1)" });
    expect(rejected.headers.get("location")).toBe("/settings?error=link");
  });

  it("keeps a private profile's card private", async () => {
    await signIn("quinn");
    expect((await call("/u/quinn/card.svg")).status).toBe(404);
  });

  it("escapes a name in the card rather than letting it become markup", async () => {
    const cookie = await signIn("rex");
    const token = await linkApp(cookie);
    await call("/api/me", { method: "PATCH", headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ public: true }) });
    await form("/settings/profile", cookie, { public: "on", display_name: '<script>x</script>' });
    const svg = await (await call("/u/rex/card.svg")).text();
    expect(svg).not.toContain("<script>");
    expect(svg).toContain("&lt;script&gt;");
  });
});

describe("limit sharing", () => {
  const reference = 1_800_000_000;

  it("accepts one reading per account and window", () => {
    const result = parseLimits(
      { limits: [{ accountKey: "a1", tool: "codex", label: " Personal ", windowLabel: " 5h ", usedPercent: 91.27, resetsAt: reference + 1440 }] },
      reference,
    );
    expect(result).toEqual({
      limits: [{ accountKey: "a1", tool: "codex", label: "Personal", windowLabel: "5h", usedPercent: 91.3, resetsAt: reference + 1440 }],
    });
  });

  it("takes a window with no reset and an account with no label", () => {
    const result = parseLimits({ limits: [{ accountKey: "a1", tool: "cursor", windowLabel: "Auto", usedPercent: 12 }] }, reference);
    expect(result).toEqual({ limits: [{ accountKey: "a1", tool: "cursor", label: null, windowLabel: "Auto", usedPercent: 12, resetsAt: null }] });
  });

  it("refuses unknown tools, impossible percentages, stale or distant resets and duplicates", () => {
    const one = (entry: Record<string, unknown>) => parseLimits({ limits: [{ accountKey: "a1", tool: "claude", windowLabel: "5h", usedPercent: 5, ...entry }] }, reference);
    expect(parseLimits({ days: [] }, reference)).toEqual({ error: "Send { limits: [...] }." });
    expect(one({ tool: "notepad" })).toEqual({ error: "Tool must be claude, cursor, codex, gemini, opencode, pi, copilot, windsurf or codebuff." });
    expect(one({ accountKey: "has space" })).toHaveProperty("error");
    expect(one({ windowLabel: "" })).toHaveProperty("error");
    expect(one({ usedPercent: 101 })).toHaveProperty("error");
    expect(one({ usedPercent: -1 })).toHaveProperty("error");
    expect(one({ usedPercent: "high" })).toHaveProperty("error");
    expect(one({ resetsAt: reference - LIMIT_TTL_SECONDS - 60 })).toHaveProperty("error");
    expect(one({ resetsAt: reference + 400 * 86400 })).toHaveProperty("error");
    expect(one({ resetsAt: reference + 0.5 })).toHaveProperty("error");
    expect(
      parseLimits(
        {
          limits: [
            { accountKey: "a1", tool: "claude", windowLabel: "5h", usedPercent: 5 },
            { accountKey: "a1", tool: "claude", windowLabel: "5h", usedPercent: 6 },
          ],
        },
        reference,
      ),
    ).toEqual({ error: "5h appears twice for one account." });
  });

  it("strips anything that would let a label lie about itself", () => {
    const ch = (code: number) => String.fromCharCode(code);
    // A label and a window name both end up in a notification on someone's phone.
    const labelled = (value: string) => {
      const result = parseLimits({ limits: [{ accountKey: "a1", tool: "claude", label: value, windowLabel: "5h", usedPercent: 5 }] }, reference);
      return "limits" in result ? result.limits[0].label : result.error;
    };
    // A newline would fake a second line in a notification title.
    expect(labelled("Work" + ch(10) + "Injected")).toBe("Work Injected");
    expect(labelled("Work" + ch(0) + "x")).toBe("Work x");
    // An escape sequence would colour a terminal that printed it.
    expect(labelled("Work" + ch(27) + "[31m")).toBe("Work [31m");
    // A bidi override would reverse what the words appear to say.
    expect(labelled("a" + ch(0x202e) + "b")).toBe("a b");
    expect(labelled("  spaced   out  ")).toBe("spaced out");
    // Markup is left alone: it is data, and nothing renders a label as HTML.
    expect(labelled("<b>Work</b>")).toBe("<b>Work</b>");

    const windows = parseLimits({ limits: [{ accountKey: "a1", tool: "claude", windowLabel: "5h" + ch(10) + "evil", usedPercent: 5 }] }, reference);
    expect("limits" in windows && windows.limits[0].windowLabel).toBe("5h evil");
    expect(clean(ch(10) + ch(9) + " ")).toBe("");
  });

  it("keeps a long label to a readable length and drops an empty one", () => {
    const result = parseLimits({ limits: [{ accountKey: "a1", tool: "claude", label: "x".repeat(80), windowLabel: "5h", usedPercent: 5 }] }, reference);
    expect("limits" in result && result.limits[0].label).toBe("x".repeat(40));
    const blank = parseLimits({ limits: [{ accountKey: "a1", tool: "claude", label: "   ", windowLabel: "5h", usedPercent: 5 }] }, reference);
    expect("limits" in blank && blank.limits[0].label).toBeNull();
  });

  it("lets a computer publish limits and a read-only phone read them back", async () => {
    const cookie = await signIn("sasha");
    const mac = await linkApp(cookie);
    const phone = await linkPhone(cookie);
    const soon = Math.floor(Date.now() / 1000) + 1500;

    expect((await sendLimits(mac, [
      { accountKey: "work", tool: "codex", label: "Work", windowLabel: "Week", usedPercent: 62, resetsAt: soon + 90_000 },
      { accountKey: "work", tool: "codex", label: "Work", windowLabel: "5h", usedPercent: 96, resetsAt: soon },
      { accountKey: "spare", tool: "cursor", label: null, windowLabel: "Auto", usedPercent: 12 },
    ])).status).toBe(200);

    const read = await readLimits(phone);
    expect(read.status).toBe(200);
    const body = (await read.json()) as { limits: { windowLabel: string; usedPercent: number }[]; updatedAt: number };
    // Soonest reset first, and the window that never says when it turns over last.
    expect(body.limits.map((entry) => entry.windowLabel)).toEqual(["5h", "Week", "Auto"]);
    expect(body.limits[0].usedPercent).toBe(96);
    expect(body.updatedAt).toBeGreaterThan(0);
  });

  it("replaces the last reading rather than piling readings up", async () => {
    const cookie = await signIn("tariq");
    const mac = await linkApp(cookie);
    await sendLimits(mac, [
      { accountKey: "one", tool: "claude", windowLabel: "5h", usedPercent: 80 },
      { accountKey: "two", tool: "claude", windowLabel: "5h", usedPercent: 40 },
    ]);
    await sendLimits(mac, [{ accountKey: "one", tool: "claude", windowLabel: "5h", usedPercent: 10 }]);
    const body = (await (await readLimits(mac)).json()) as { limits: { accountKey: string; usedPercent: number }[] };
    expect(body.limits).toHaveLength(1);
    expect(body.limits[0]).toMatchObject({ accountKey: "one", usedPercent: 10 });
  });

  it("refuses an upload from a read-only phone, and clears on request", async () => {
    const cookie = await signIn("ursula");
    const mac = await linkApp(cookie);
    const phone = await linkPhone(cookie);
    await sendLimits(mac, [{ accountKey: "one", tool: "gemini", windowLabel: "Day", usedPercent: 30 }]);

    expect((await sendLimits(phone, [{ accountKey: "one", tool: "gemini", windowLabel: "Day", usedPercent: 99 }])).status).toBe(403);
    expect((await call("/api/limits", { method: "DELETE", headers: { authorization: `Bearer ${phone}` } })).status).toBe(403);

    expect((await call("/api/limits", { method: "DELETE", headers: { authorization: `Bearer ${mac}` } })).status).toBe(204);
    const body = (await (await readLimits(phone)).json()) as { limits: unknown[]; updatedAt: number | null };
    expect(body).toEqual({ limits: [], updatedAt: null });
  });

  it("keeps one person's limits away from another's, and away from anyone unlinked", async () => {
    const mac = await linkApp(await signIn("vera"));
    await sendLimits(mac, [{ accountKey: "one", tool: "claude", windowLabel: "5h", usedPercent: 77 }]);
    const stranger = await linkApp(await signIn("wesley"));
    expect((await (await readLimits(stranger)).json()) as unknown).toEqual({ limits: [], updatedAt: null });
    expect((await call("/api/limits")).status).toBe(401);
  });

  it("sweeps readings nobody refreshed, and only those", async () => {
    const mac = await linkApp(await signIn("yara"));
    await sendLimits(mac, [{ accountKey: "old", tool: "claude", windowLabel: "5h", usedPercent: 10 }]);
    const fresh = await linkApp(await signIn("zane"));
    await sendLimits(fresh, [{ accountKey: "new", tool: "claude", windowLabel: "5h", usedPercent: 20 }]);
    // Age only yara's row past the TTL, as if that computer went quiet a day ago.
    await env.DB.prepare("UPDATE account_limits SET updated_at = updated_at - ? WHERE account_key = 'old'").bind(LIMIT_TTL_SECONDS + 60).run();

    expect(await sweepLimits(env.DB)).toBeGreaterThanOrEqual(1);
    const left = await env.DB.prepare("SELECT account_key FROM account_limits WHERE account_key IN ('old', 'new')").all<{ account_key: string }>();
    expect(left.results.map((row) => row.account_key)).toEqual(["new"]);
  });

  it("limits how fast one account can upload, without slowing anyone else", async () => {
    const busy = await linkApp(await signIn("runaway"));
    const calm = await linkApp(await signIn("steady"));
    const statuses: number[] = [];
    for (let attempt = 0; attempt < 65; attempt++) {
      statuses.push((await sendLimits(busy, [{ accountKey: "a", tool: "claude", windowLabel: "5h", usedPercent: 1 }])).status);
    }
    expect(statuses.slice(0, 60).every((status) => status === 200)).toBe(true);
    const refused = await sendLimits(busy, []);
    expect(refused.status).toBe(429);
    expect(refused.headers.get("retry-after")).toBe("60");
    // The same allowance covers daily totals, so switching endpoints doesn't get around it.
    expect((await upload(busy, [])).status).toBe(429);
    expect((await sendLimits(calm, [])).status).toBe(200);
    // Reading is never throttled by writing.
    expect((await readLimits(busy)).status).toBe(200);
  });
});

describe("site header", () => {
  it("offers sign-in everywhere, and the same places on every page", async () => {
    for (const path of ["/", "/download", "/privacy", "/leaderboard", "/season"]) {
      const body = await (await call(path)).text();
      expect(body, path).toContain('href="/login?next=');
      for (const place of ['>Leaderboard</a>', '>Season</a>', '>Download</a>', '>Product</a>']) {
        expect(body, `${path} ${place}`).toContain(place);
      }
      // Teams only means something once signed in.
      expect(body, path).not.toContain('href="/teams"');
      expect(body, path).not.toContain('action="/auth/logout"');
    }
  });

  it("shows who is signed in, with a way out, on marketing pages too", async () => {
    const cookie = await signIn("header-user");
    for (const path of ["/", "/download", "/leaderboard"]) {
      const body = await (await call(path, { headers: { cookie } })).text();
      expect(body, path).toContain("@header-user");
      expect(body, path).toContain('href="/u/header-user"');
      expect(body, path).toContain('href="/settings"');
      expect(body, path).toContain('href="/teams"');
      expect(body, path).toContain('action="/auth/logout"');
      expect(body, path).not.toContain('href="/login?next=');
    }
  });

  it("marks the page you are on", async () => {
    const body = await (await call("/download")).text();
    expect(body).toMatch(/href="\/download" aria-current="page"/);
  });

  it("signs out back to the page you were on, unless it needs you signed in", async () => {
    const back = async (next: string) => {
      const cookie = await signIn(`leaver${Math.random().toString(36).slice(2, 8)}`);
      const response = await form("/auth/logout", cookie, { next });
      expect(response.status).toBe(302);
      expect(response.headers.getSetCookie().some((value) => value.startsWith("keyhop_session=;"))).toBe(true);
      // The session is really gone, not just the cookie.
      expect((await call("/settings", { headers: { cookie } })).status).toBe(302);
      return response.headers.get("location");
    };
    expect(await back("/season")).toBe("/season");
    expect(await back("/download")).toBe("/download");
    expect(await back("/settings")).toBe("/");
    expect(await back("/teams")).toBe("/");
    expect(await back("https://evil.example/")).toBe("/leaderboard");
    expect(await back("//evil.example/")).toBe("/leaderboard");
    expect(await back("")).toBe("/");
  });

  it("refuses a sign-out posted from another site", async () => {
    const cookie = await signIn("stays-in");
    const response = await form("/auth/logout", cookie, { next: "/" }, "https://evil.example");
    expect(response.status).toBe(403);
    expect((await call("/settings", { headers: { cookie } })).status).toBe(200);
  });
});
