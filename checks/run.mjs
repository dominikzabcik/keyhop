/**
 * Drives every Keyhop screen and reports what is wrong with it.
 *
 *   node run.mjs --site            the website, from a local wrangler
 *   node run.mjs --app             the Mac window, from `keyhop dashboard --sample`
 *   node run.mjs --site --app      both
 *   node run.mjs --site --review   both, then ask Jev about what it read
 *
 * Findings that are decidable fail the run. Jev's answers are written into the report and never
 * fail it on their own: a judgement is a second opinion, not a gate.
 */

import { spawn } from "node:child_process";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium, request as playwrightRequest } from "playwright";

import { checkLinks, faults, pokeControls, readScreen } from "./checks.mjs";
import { APP_SCREENS, APP_WIDTHS, SITE_SCREENS, WIDTHS } from "./screens.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const out = join(here, "report");

const flags = new Set(process.argv.slice(2));
const wanted = { site: flags.has("--site"), app: flags.has("--app"), review: flags.has("--review") };
if (!wanted.site && !wanted.app) {
  wanted.site = true;
  wanted.app = true;
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

async function withPage(browser, size, visit) {
  const context = await browser.newContext({ viewport: { width: size.width, height: size.height }, deviceScaleFactor: 1 });
  const page = await context.newPage();
  const consoleErrors = [];
  page.on("console", (message) => {
    if (message.type() === "error") consoleErrors.push(message.text());
  });
  page.on("pageerror", (error) => consoleErrors.push(String(error)));
  try {
    return await visit(page, consoleErrors);
  } finally {
    await context.close();
  }
}

/** Walks one target's screens at every width, saving a picture and a reading of each. */
async function walk({ browser, origin, screens, open, label, widths = WIDTHS }) {
  const found = [];
  const readings = [];
  for (const screen of screens) {
    for (const size of widths) {
      const shot = join(out, "screens", `${label}-${screen.name}-${size.name}.png`);
      const { reading, status, pressed } = await withPage(browser, size, async (page, consoleErrors) => {
        const status = await open(page, screen);
        await page.waitForTimeout(700); // Let anything that animates settle before it is judged.
        const reading = await readScreen(page);
        await page.screenshot({ path: shot, fullPage: false });
        found.push(...faults({ screen, width: size.name, reading, status, consoleErrors }));
        // One width is enough to learn whether the controls answer at all.
        let pressed = [];
        if (size.name === "laptop" && screen.expect?.status?.includes(404) !== true) {
          const poked = await pokeControls(page, screen);
          found.push(...poked.dead);
          pressed = poked.pressed;
        }
        return { reading, status, pressed };
      });
      if (size.name === "laptop") readings.push({ target: label, screen: screen.name, status, pressed, ...reading, shot });
    }
  }
  return { found, readings };
}

async function checkSite(browser) {
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
    return await walk({
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
  } finally {
    child.kill();
  }
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
  } finally {
    await browser.close();
  }

  let judgements = [];
  if (wanted.review) {
    const { review } = await import("./review.mjs");
    judgements = await review(readings);
  }

  await writeFile(join(out, "report.json"), JSON.stringify({ found, judgements, screens: readings.map((r) => r.screen) }, null, 2));

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
