// Fills a local `npm run dev` database with made-up people, usage and a team, to look at the pages.
//   node scripts/seed-local.mjs [http://localhost:8787]
const base = process.argv[2] ?? "http://localhost:8787";
const people = [
  { login: "mira", scale: 9_000_000, tools: [0.6, 0.2, 0.1, 0.1] },
  { login: "jonas", scale: 6_500_000, tools: [0.2, 0.55, 0.1, 0.15] },
  { login: "priya", scale: 5_200_000, tools: [0.4, 0.1, 0.3, 0.2] },
  { login: "tomas", scale: 2_800_000, tools: [0.1, 0.65, 0.1, 0.15] },
  { login: "alex", scale: 1_400_000, tools: [0.35, 0.1, 0.35, 0.2] },
];
const tools = ["claude", "cursor", "codex", "gemini"];
const pricePerMillion = { claude: 4.2, cursor: 2.1, codex: 3.1, gemini: 2 };
const repos = ["nightshift/atlas", "nightshift/atlas-web", "nightshift/ledger", "nightshift/runbook", "nightshift/mobile"];
// Real days are two or three pieces of work, each landed over several commits, so the seed makes
// days that shape instead of a bag of unrelated subjects.
const tasks = [
  { scope: "importer", lines: ["stop a dead job retrying forever", "retry with a ceiling", "log why the job gave up", "cover the retry ceiling"] },
  { scope: "ledger", lines: ["read the ledger in one pass", "drop the second lookup", "round the totals the way the invoice does", "name the columns after what they hold"] },
  { scope: "auth", lines: ["keep the session alive when the tab sleeps", "refuse a token that outlived its session", "say which sign-in expired"] },
  { scope: "sync", lines: ["let a failed upload report itself", "send the last eight days, not the year", "back off when the server is busy"] },
  { scope: "dates", lines: ["pull the date maths into one place", "count a day in the viewer's zone", "cover the day either side of midnight"] },
  { scope: "", lines: ["write down what the sync actually does", "say plainly what the empty state means", "spell out what never leaves the computer"] },
];
const types = ["feat", "fix", "refactor", "perf", "test", "docs"];
const pick = (list) => list[Math.floor(Math.random() * list.length)];

async function request(path, init = {}) {
  return fetch(`${base}${path}`, { redirect: "manual", ...init });
}

async function signIn(login) {
  const response = await request(`/auth/dev?login=${login}`);
  const cookie = response.headers.getSetCookie().find((value) => value.startsWith("keyhop_session="));
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

  // Commits for the same stretch. The last person shares no subjects, so the page can be seen both
  // with the words and with only the counts.
  const work = [];
  const shares = index < people.length - 1;
  for (let back = 0; back < 180; back++) {
    const date = new Date(today);
    date.setUTCDate(date.getUTCDate() - back);
    const day = date.toISOString().slice(0, 10);
    const weekend = [0, 6].includes(date.getUTCDay());
    if (Math.random() < (weekend ? 0.7 : 0.2)) continue;
    const mine = repos.slice(0, 1 + Math.floor(Math.random() * 3));
    for (const repo of mine) {
      // One or two tasks in this repository today, each landed over a few commits.
      const todays = [...tasks].sort(() => Math.random() - 0.5).slice(0, 1 + Math.floor(Math.random() * (weekend ? 1 : 2)));
      let minute = 0;
      const subjects = todays.flatMap((task) => {
        const lines = task.lines.slice(0, 1 + Math.floor(Math.random() * task.lines.length));
        return lines.map((line) => {
          minute += 20 + Math.floor(Math.random() * 70);
          return {
            sha: Math.random().toString(16).slice(2, 9).padEnd(7, "0"),
            subject: `${pick(types)}${task.scope ? `(${task.scope})` : ""}: ${line}`,
            insertions: 3 + Math.floor(Math.random() * 180),
            deletions: Math.floor(Math.random() * 90),
            at: Math.floor(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()) / 1000) + 9 * 3600 + minute * 60,
            offset: 0,
          };
        });
      });
      const commits = subjects.length;
      work.push({
        day,
        repo,
        commits,
        insertions: subjects.reduce((sum, entry) => sum + entry.insertions, 0),
        deletions: subjects.reduce((sum, entry) => sum + entry.deletions, 0),
        ...(shares ? { subjects } : {}),
      });
    }
  }
  // Everyone is finished except one, who is left mid-index so that state can be seen on the page.
  const indexing = person.login === "tomas";
  const indexState = indexing ? { done: 11, total: 40, complete: false } : { done: 40, total: 40, complete: true };
  const committed = await request("/api/work", {
    method: "POST",
    headers: { authorization: `Bearer ${token}` },
    body: JSON.stringify({ days: work, index: indexState }),
  });
  console.log(`${person.login}: ${days.length} usage entries (${saved.status}), ${work.length} commit days (${committed.status})`);
}

const created = await post("/teams", cookies.mira, { name: "Night Shift" });
const slug = created.headers.get("location").split("/").pop();
const invited = await post(`/t/${slug}/invites`, cookies.mira);
const code = new URL(invited.headers.get("location"), base).searchParams.get("invite");
for (const login of ["jonas", "tomas", "alex"]) await post(`/invite/${code}`, cookies[login]);
console.log(`Team /t/${slug} with an invite at /invite/${code}`);
console.log(`Signed-in cookie for mira: ${cookies.mira}`);
