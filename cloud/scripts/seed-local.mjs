// Fills a local `npm run dev` database with made-up people, usage and a team, to look at the pages.
//   node scripts/seed-local.mjs [http://localhost:8787]
const base = process.argv[2] ?? "http://localhost:8787";
const people = [
  { login: "mira", scale: 9_000_000, tools: [0.7, 0.2, 0.1] },
  { login: "jonas", scale: 6_500_000, tools: [0.3, 0.6, 0.1] },
  { login: "priya", scale: 5_200_000, tools: [0.5, 0.1, 0.4] },
  { login: "tomas", scale: 2_800_000, tools: [0.1, 0.8, 0.1] },
  { login: "alex", scale: 1_400_000, tools: [0.45, 0.1, 0.45] },
];
const tools = ["claude", "cursor", "codex"];
const pricePerMillion = { claude: 4.2, cursor: 2.1, codex: 3.1 };

async function request(path, init = {}) {
  return fetch(`${base}${path}`, { redirect: "manual", ...init });
}

async function signIn(login) {
  const response = await request(`/auth/dev?login=${login}`);
  const cookie = response.headers.getSetCookie().find((value) => value.startsWith("switchr_session="));
  if (!cookie) throw new Error(`Dev login failed for ${login}: ${response.status}. Is DEV_LOGIN=true in .dev.vars?`);
  return cookie.split(";")[0];
}

function post(path, cookie, fields = {}) {
  return request(path, { method: "POST", headers: { cookie, origin: base }, body: new URLSearchParams(fields) });
}

async function linkApp(cookie) {
  const { deviceCode, userCode } = await (await request("/api/device/start", { method: "POST", body: JSON.stringify({ label: "Seed Mac" }) })).json();
  await post("/link", cookie, { code: userCode });
  return (await (await request("/api/device/token", { method: "POST", body: JSON.stringify({ deviceCode }) })).json()).token;
}

const today = new Date();
const cookies = {};
for (const [index, person] of people.entries()) {
  const cookie = await signIn(person.login);
  cookies[person.login] = cookie;
  // Everyone but the last is public, so the leaderboard and a private team member both show.
  await post("/welcome", cookie, index < people.length - 1 ? { public: "on", next: "/" } : { next: "/" });
  const token = await linkApp(cookie);
  const days = [];
  for (let back = 0; back < 180; back++) {
    const date = new Date(today);
    date.setUTCDate(date.getUTCDate() - back);
    const weekend = [0, 6].includes(date.getUTCDay());
    if (Math.random() < (weekend ? 0.55 : 0.12)) continue;
    const volume = person.scale * (0.35 + Math.random() * 1.3) * (weekend ? 0.4 : 1);
    tools.forEach((tool, t) => {
      const tokens = Math.round(volume * person.tools[t]);
      if (tokens < 1000) return;
      days.push({
        day: date.toISOString().slice(0, 10),
        tool,
        tokens,
        cost: Math.round(((tokens / 1_000_000) * pricePerMillion[tool]) * 100) / 100,
        requests: Math.max(1, Math.round(tokens / 42_000)),
      });
    });
  }
  const saved = await request("/api/usage", { method: "POST", headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ days }) });
  console.log(`${person.login}: ${days.length} entries, ${saved.status}`);
}

const created = await post("/teams", cookies.mira, { name: "Night Shift" });
const slug = created.headers.get("location").split("/").pop();
const invited = await post(`/t/${slug}/invites`, cookies.mira);
const code = new URL(invited.headers.get("location"), base).searchParams.get("invite");
for (const login of ["jonas", "tomas", "alex"]) await post(`/invite/${code}`, cookies[login]);
console.log(`Team /t/${slug} with an invite at /invite/${code}`);
console.log(`Signed-in cookie for mira: ${cookies.mira}`);
