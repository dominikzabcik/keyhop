/**
 * Drives every Keyhop screen and reports what is wrong with it.
 *
 *   node run.mjs --site            the website, from a local wrangler
 *   node run.mjs --app             the Mac window, from `keyhop dashboard --sample`
 *   node run.mjs --cli             the commands, including the tools `keyhop mcp` serves
 *   node run.mjs                   all three
 *   node run.mjs --review          all three, then ask Jev about what it read
 *
 * Findings that are decidable fail the run. Jev's answers are written into the report and never
 * fail it on their own: a judgement is a second opinion, not a gate.
 */

import { execFile, spawn } from "node:child_process";
import { mkdir, readdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { chromium, request as playwrightRequest } from "playwright";

import { checkCommands } from "./cli.mjs";
import { checkLinks, faults, pokeControls, readScreen } from "./checks.mjs";
import { ACCOUNT_SCREENS, APP_SCREENS, APP_WIDTHS, SITE_SCREENS, WIDTHS } from "./screens.mjs";
import { signIn } from "./signin.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const out = join(here, "report");

const flags = new Set(process.argv.slice(2));
const wanted = {
  site: flags.has("--site"),
  app: flags.has("--app"),
  cli: flags.has("--cli"),
  review: flags.has("--review"),
};
if (!wanted.site && !wanted.app && !wanted.cli) {
  wanted.site = true;
  wanted.app = true;
  wanted.cli = true;
}

/** Starts a process and waits until `ready` recognises its output. Kills it when the run ends. */
function start(command, args, { cwd, ready, timeout = 120_000 }) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd, env: process.env });
    let output = "";
    const done = setTimeout(() => {
      child.kill();
      reject(new Error(`${command} never became ready. Output so far:\n${output.slice(-800)}`));
    }, timeout);
    const look = (chunk) => {
      output += chunk;
      const found = ready(output);
      if (!found) return;
      clearTimeout(done);
      resolve({ child, found });
    };
    child.stdout.on("data", (d) => look(String(d)));
    child.stderr.on("data", (d) => look(String(d)));
    child.on("exit", (code) => {
      clearTimeout(done);
      reject(new Error(`${command} exited with ${code} before it was ready:\n${output.slice(-800)}`));
    });
  });
}

async function withPage(browser, size, visit, cookie) {
  const context = await browser.newContext({ viewport: { width: size.width, height: size.height }, deviceScaleFactor: 1 });
  if (cookie) {
    const { path, ...rest } = cookie; // Playwright takes a url or a path, not both.
    await context.addCookies([rest]);
  }
  const page = await context.newPage();
  const consoleErrors = [];
  const failedRequests = [];
  page.on("console", (message) => {
    if (message.type() === "error") consoleErrors.push(message.text());
  });
  page.on("pageerror", (error) => consoleErrors.push(String(error)));
  page.on("response", (response) => {
    if (response.status() < 400) return;
    failedRequests.push({
      path: new URL(response.url()).pathname,
      status: response.status(),
      isDocument: response.request().resourceType() === "document",
    });
  });
  try {
    return await visit(page, consoleErrors, failedRequests);
  } finally {
    await context.close();
  }
}

/** Walks one target's screens at every width, saving a picture and a reading of each. */
async function walk({ browser, origin, screens, open, label, widths = WIDTHS, cookie }) {
  const found = [];
  const readings = [];
  for (const screen of screens) {
    for (const size of widths) {
      const shot = join(out, "screens", `${label}-${screen.name}-${size.name}.png`);
      const { reading, status, pressed } = await withPage(browser, size, async (page, consoleErrors, failedRequests) => {
        const status = await open(page, screen);
        await page.waitForTimeout(700); // Let anything that animates settle before it is judged.
        const reading = await readScreen(page);
        await page.screenshot({ path: shot, fullPage: false });
        found.push(...faults({ screen, width: size.name, reading, status, consoleErrors, failedRequests }));
        // One width is enough to learn whether the controls answer at all.
        let pressed = [];
        if (size.name === "laptop" && screen.expect?.status?.includes(404) !== true) {
          const poked = await pokeControls(page, screen);
          found.push(...poked.dead);
          pressed = poked.pressed;
        }
        return { reading, status, pressed };
      }, cookie);
      if (size.name === "laptop") readings.push({ target: label, screen: screen.name, status, pressed, ...reading, shot });
    }
  }
  return { found, readings };
}

async function checkSite(browser) {
  // A machine that has never run the website locally has an empty database, and half its pages
  // answer 500. The migrations are the website's own, applied to the local copy only.
  console.log("Preparing the local database…");
  await promisify(execFile)("npx", ["wrangler", "d1", "migrations", "apply", "switchr", "--local"], {
    cwd: join(root, "cloud"),
    env: process.env,
  });

  console.log("Starting the website…");
  const { child } = await start("npx", ["wrangler", "dev", "--port", "8811", "--ip", "127.0.0.1"], {
    cwd: join(root, "cloud"),
    ready: (text) => /Ready on http/.test(text) || /127\.0\.0\.1:8811/.test(text),
  });
  const origin = "http://127.0.0.1:8811";
  try {
    // Wrangler prints its address a moment before it answers.
    for (let attempt = 0; attempt < 30; attempt++) {
      try {
        const probe = await fetch(origin);
        if (probe.ok) break;
      } catch {}
      await new Promise((r) => setTimeout(r, 500));
    }
    const result = await walk({
      browser,
      origin,
      screens: SITE_SCREENS,
      label: "site",
      open: async (page, screen) => {
        const response = await page.goto(origin + screen.path, { waitUntil: "networkidle" });
        return response?.status() ?? null;
      },
    });

    // The same walk again, this time as someone who is signed in, for the pages that need it.
    console.log("Signing in to the local website…");
    let cookie = null;
    try {
      cookie = { ...(await signIn(join(root, "cloud"))), url: origin };
    } catch (error) {
      result.found.push({ screen: "sign-in", width: "-", kind: "setup", detail: `couldn't sign in locally: ${error.message}` });
    }
    if (cookie) {
      const signedIn = await walk({
        browser,
        origin,
        screens: ACCOUNT_SCREENS,
        label: "account",
        cookie,
        open: async (page, screen) => {
          const response = await page.goto(origin + screen.path, { waitUntil: "networkidle" });
          return response?.status() ?? null;
        },
      });
      result.found.push(...signedIn.found);
      result.readings.push(...signedIn.readings);
      // Pressing things is the point, and some of them are settings. The visitor is put back the
      // way it started before anything else reads the site.
      await signIn(join(root, "cloud"));
    }

    const api = await playwrightRequest.newContext();
    const hrefs = result.readings.flatMap((r) => r.controls.map((c) => c.href));
    for (const { href, status } of await checkLinks(api, origin, hrefs)) {
      result.found.push({ screen: "links", width: "-", kind: "dead-link", detail: `${href} answers ${status}` });
    }
    await api.dispose();
    return result;
  } finally {
    child.kill();
  }
}

async function checkApp(browser) {
  console.log("Starting Keyhop's window with sample data…");
  const binary = join(root, ".build/debug/Keyhop");
  const { child, found } = await start(binary, ["dashboard", "--sample", "--no-open", "--json"], {
    cwd: root,
    ready: (text) => text.match(/"url":"(http:[^"]+)"/)?.[1],
    // Sample data never touches real accounts, and a private folder keeps it out of the real one.
    env: { ...process.env, KEYHOP_DATA_DIR: join(out, "data") },
  });
  const url = new URL(found);
  try {
    const result = await walk({
      browser,
      origin: url.origin,
      screens: APP_SCREENS,
      label: "app",
      widths: APP_WIDTHS,
      open: async (page, screen) => {
        await page.goto(`${url.origin}/${url.hash.replace("s=overview", `s=${screen.section}`)}`, { waitUntil: "networkidle" });
        await page.waitForFunction(() => !document.querySelector(".lede.busy"), null, { timeout: 20_000 }).catch(() => {});
        return null;
      },
    });
    // Hop is the app's fastest repeated path. Check its keyboard entry, live filtering,
    // empty state and Enter-to-open behavior instead of relying only on static screenshots.
    try {
      await withPage(browser, APP_WIDTHS[1], async (page) => {
        await page.goto(`${url.origin}/${url.hash}`, { waitUntil: "networkidle" });
        await page.keyboard.press("Tab");
        if ((await page.locator(":focus").innerText()) !== "Skip to content") throw new Error("skip control is not first in the focus order");
        await page.keyboard.press("Enter");
        if ((await page.locator(":focus").getAttribute("id")) !== "main") throw new Error("skip control did not focus the main content");
        await page.keyboard.press(process.platform === "darwin" ? "Meta+K" : "Control+K");
        const search = page.locator("#palette input");
        await search.waitFor({ state: "visible" });
        await search.fill("Usage");
        const matches = page.locator("[data-palette]:visible");
        if ((await matches.count()) < 1 || !(await matches.first().innerText()).includes("Usage")) {
          throw new Error("search did not narrow Hop to the Usage section");
        }
        await search.press("Enter");
        await page.waitForURL(/#usage$/);
        await page.getByRole("heading", { name: "Usage", exact: true }).waitFor({ state: "visible" });

        // Returning to Keyhop should refresh at once rather than showing figures up to 20 seconds old.
        const resumed = page.waitForResponse((response) => new URL(response.url()).pathname === "/api/state");
        await page.evaluate(() => document.dispatchEvent(new Event("visibilitychange")));
        await resumed;

        await page.keyboard.press(process.platform === "darwin" ? "Meta+K" : "Control+K");
        await search.fill("no-such-account-or-section");
        await page.getByText(/Nothing matches/).waitFor({ state: "visible" });
        await page.keyboard.press("Escape");
        if ((await page.locator("#palette").getAttribute("hidden")) === null) throw new Error("Escape did not close Hop");

        // Hop stays at one physical anchor while section-specific tools change around it.
        const rightEdges = [];
        for (const section of ["overview", "usage", "settings"]) {
          await page.locator(`#nav a[data-section="${section}"]`).click();
          const box = await page.locator(".hop").boundingBox();
          rightEdges.push(Math.round(box.x + box.width));
        }
        if (new Set(rightEdges).size !== 1) throw new Error(`Hop moved between sections: ${rightEdges.join(", ")}`);

        // An update check gets a local wait and must not light the limits progress bar.
        await page.route("**/api/update", async (route) => {
          await new Promise((resolve) => setTimeout(resolve, 700));
          await route.continue();
        });
        await page.reload({ waitUntil: "domcontentloaded" });
        await page.locator('[data-action="settings-pane"][data-value="app"]').click();
        await page.getByText("Checking for updates…", { exact: true }).waitFor({ state: "visible" });
        if (await page.locator("#top-meter").evaluate((meter) => meter.classList.contains("on"))) {
          throw new Error("update check borrowed the limits progress bar");
        }
      });
    } catch (error) {
      result.found.push({ screen: "quick-hop", width: "laptop", kind: "interaction", detail: error.message });
    }
    return result;
  } finally {
    child.kill();
  }
}

/**
 * What the phone's screens said, last time its tests ran.
 *
 * The UI tests drive the phone in a simulator and write down what each screen showed. Reading
 * those here puts the phone in front of Jev with the pages and the window, without a second run.
 */
async function phoneScreens() {
  const folders = [];
  if (process.env.KEYHOP_SCREEN_TEXT) folders.push(process.env.KEYHOP_SCREEN_TEXT);
  const devices = join(homedir(), "Library/Developer/CoreSimulator/Devices");
  try {
    for (const device of await readdir(devices)) folders.push(join(devices, device, "data/keyhop-screens"));
  } catch {}

  const readings = [];
  const seen = new Set();
  for (const folder of folders) {
    let files;
    try {
      files = await readdir(folder);
    } catch {
      continue;
    }
    for (const file of files.filter((name) => name.endsWith(".json"))) {
      const when = (await stat(join(folder, file))).mtimeMs;
      // A screen from a run days ago says nothing about the app as it stands now.
      if (Date.now() - when > 24 * 60 * 60 * 1000 || seen.has(file)) continue;
      seen.add(file);
      const said = JSON.parse(await readFile(join(folder, file), "utf8"));
      readings.push({
        target: "phone",
        screen: said.screen,
        title: said.title,
        // A native navigation title is the screen's first-level heading even though XCTest records
        // it separately from the visible accessibility text.
        headings: said.title ? [{ level: 1, text: said.title }] : [],
        controls: (said.controls ?? []).map((text) => ({ text })),
        text: said.text ?? "",
        pressed: [],
      });
    }
  }
  return readings;
}

/** The run as a page someone can read, saved beside the pictures. */
function summary(found, judgements, readings) {
  const lines = [`# Every screen, ${new Date().toISOString().slice(0, 16).replace("T", " ")}`, ""];
  lines.push(`${readings.length} screens read, ${readings.reduce((n, r) => n + (r.pressed?.length ?? 0), 0)} controls pressed.`, "");

  lines.push(found.length ? `## ${found.length} problems` : "## No problems", "");
  for (const fault of found) lines.push(`- **${fault.screen}** (${fault.width}) ${fault.kind}: ${fault.detail}`);
  lines.push("");

  const raised = judgements.filter((j) => !j.passed);
  if (judgements.length) {
    lines.push(raised.length ? `## ${raised.length} judgements to look at` : "## Jev raised nothing", "");
    for (const judgement of raised) lines.push(`- **${judgement.screen}** ${judgement.question}: ${judgement.answer}`);
    lines.push("", "<details><summary>Every answer</summary>", "");
    for (const screen of [...new Set(judgements.map((j) => j.screen))]) {
      lines.push(`**${screen}**`, "");
      for (const judgement of judgements.filter((j) => j.screen === screen)) {
        const sure = judgement.confidence == null ? "" : ` (confidence ${judgement.confidence.toFixed(2)})`;
        lines.push(`- ${judgement.question}: ${judgement.answer}${sure}${judgement.note ? ` — ${judgement.note}` : ""}`);
      }
      lines.push("");
    }
    lines.push("</details>", "");
  }

  lines.push("## Screens", "");
  for (const reading of readings) lines.push(`- ${reading.target}/${reading.screen}: ${reading.headings[0]?.text ?? reading.title}`);
  return lines.join("\n") + "\n";
}

async function main() {
  await rm(out, { recursive: true, force: true });
  await mkdir(join(out, "screens"), { recursive: true });
  const browser = await chromium.launch();
  const found = [];
  const readings = [];
  try {
    if (wanted.site) {
      const site = await checkSite(browser);
      found.push(...site.found);
      readings.push(...site.readings);
    }
    if (wanted.app) {
      const app = await checkApp(browser);
      found.push(...app.found);
      readings.push(...app.readings);
    }
    if (wanted.cli) {
      console.log("Running the commands…");
      found.push(...(await checkCommands(join(root, ".build/debug/Keyhop"))));
    }
  } finally {
    await browser.close();
  }

  if (wanted.review) {
    const phone = await phoneScreens();
    if (phone.length) console.log(`Reading ${phone.length} screens the phone's tests wrote down…`);
    readings.push(...phone);
  }

  let judgements = [];
  if (wanted.review) {
    const { review } = await import("./review.mjs");
    judgements = await review(readings);
  }

  await writeFile(join(out, "report.json"), JSON.stringify({ found, judgements, screens: readings.map((r) => r.screen) }, null, 2));
  await writeFile(join(out, "report.md"), summary(found, judgements, readings));

  for (const fault of found) console.log(`✗ ${fault.screen} (${fault.width}) ${fault.kind}: ${fault.detail}`);
  for (const judgement of judgements) {
    const mark = judgement.passed ? "·" : "!";
    console.log(`${mark} ${judgement.screen} ${judgement.question}: ${judgement.answer}${judgement.note ? ` — ${judgement.note}` : ""}`);
  }
  const pressedCount = readings.reduce((sum, r) => sum + (r.pressed?.length ?? 0), 0);
  console.log(`\n${readings.length} screens read, ${pressedCount} controls pressed, ${found.length} problems, ${judgements.filter((j) => !j.passed).length} judgements to look at.`);
  console.log(`Pictures and the full report are in ${out}.`);
  process.exit(found.length ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(2);
});
