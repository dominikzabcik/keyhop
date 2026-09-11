import { exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { addDays, today } from "../src/env";
import { streaks } from "../src/stats";
import { parseUsage } from "../src/usage";

const BASE = "http://localhost";

function call(path: string, init: RequestInit = {}): Promise<Response> {
  return exports.default.fetch(new Request(`${BASE}${path}`, { redirect: "manual", ...init }));
}

/** Signs in through the development login and returns the session cookie. */
async function signIn(login: string): Promise<string> {
  const response = await call(`/auth/dev?login=${login}&next=/leaderboard`);
  expect(response.status).toBe(302);
  const cookie = response.headers.getSetCookie().find((value) => value.startsWith("switchr_session="));
  expect(cookie).toBeDefined();
  return cookie!.split(";")[0];
}

/** Posts a form the way Switchr's pages do: same origin, with the session cookie. */
function form(path: string, cookie: string, fields: Record<string, string> = {}, origin = BASE): Promise<Response> {
  return call(path, { method: "POST", headers: { cookie, origin }, body: new URLSearchParams(fields) });
}

/** Links an app the way Switchr does and returns its bearer token. */
async function linkApp(cookie: string): Promise<string> {
  const start = await call("/api/device/start", { method: "POST", body: JSON.stringify({ label: "Test Mac" }) });
  const { deviceCode, userCode } = (await start.json()) as { deviceCode: string; userCode: string };
  const approved = await form("/link", cookie, { code: userCode });
  expect(approved.headers.get("location")).toBe("/link?done=1");
  const token = await call("/api/device/token", { method: "POST", body: JSON.stringify({ deviceCode }) });
  expect(token.status).toBe(200);
  return ((await token.json()) as { token: string }).token;
}

function upload(token: string, days: unknown[]): Promise<Response> {
  return call("/api/usage", { method: "POST", headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ days }) });
}

describe("usage uploads", () => {
  const day = today();

  it("accepts daily totals per tool", () => {
    const result = parseUsage({ days: [{ day, tool: "claude", tokens: 1200, cost: 1.5, requests: 3 }] }, day);
    expect(result).toEqual({ days: [{ day, tool: "claude", tokens: 1200, costMicros: 1_500_000, requests: 3 }] });
  });

  it("refuses impossible dates, unknown tools, duplicates and negative numbers", () => {
    const entry = { day, tool: "claude", tokens: 1, cost: 0, requests: 1 };
    expect(parseUsage({ days: [{ ...entry, day: "2026-02-30" }] }, day)).toHaveProperty("error");
    expect(parseUsage({ days: [{ ...entry, day: addDays(day, -500) }] }, day)).toHaveProperty("error");
    expect(parseUsage({ days: [{ ...entry, tool: "copilot" }] }, day)).toHaveProperty("error");
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
    const asCookie = await call("/api/me", { headers: { cookie: `switchr_session=${token}` } });
    expect(asCookie.status).toBe(401);
    const asBearer = await call("/api/me", { headers: { authorization: `Bearer ${cookie.split("=")[1]}` } });
    expect(asBearer.status).toBe(401);
  });
});

describe("leaderboards", () => {
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
    expect(body).not.toContain("<script");
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
    const response = await exports.default.fetch(new Request("https://switchr.example/auth/dev?login=mallory", { redirect: "manual" }));
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
