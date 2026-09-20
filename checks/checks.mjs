/**
 * What is checked on every screen, and what is read off it for Jev to judge.
 *
 * Everything here is decidable: a number, a string, a box on screen. Taste, tone and whether a
 * screen makes sense are not decidable, so they are left to review.mjs, which asks Jev about the
 * facts this file collects.
 */

import { BANNED_CHARACTERS, NEVER_SAY } from "./screens.mjs";

/** Reads a screen: what it says, what it offers, and where its boxes sit. */
export async function readScreen(page) {
  return page.evaluate(() => {
    const visible = (el) => {
      const style = getComputedStyle(el);
      if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
      const box = el.getBoundingClientRect();
      return box.width > 0 && box.height > 0;
    };
    const name = (el) =>
      (el.getAttribute("aria-label") || el.textContent || el.getAttribute("title") || el.value || "").trim().replace(/\s+/g, " ");

    const headings = [...document.querySelectorAll("h1, h2, h3, h4")]
      .filter(visible)
      .map((h) => ({ level: Number(h.tagName[1]), text: name(h) }));

    const controls = [...document.querySelectorAll("button, a[href], input, select, summary, [role=button]")]
      .filter(visible)
      .map((el) => ({
        tag: el.tagName.toLowerCase(),
        text: name(el).slice(0, 80),
        href: el.getAttribute("href") || null,
        disabled: !!el.disabled,
      }));

    // Anything sticking out sideways: the page should never scroll horizontally.
    const overflow = document.documentElement.scrollWidth - document.documentElement.clientWidth;
    const wide = overflow > 1
      ? [...document.querySelectorAll("body *")]
          .filter(visible)
          .filter((el) => el.getBoundingClientRect().right > document.documentElement.clientWidth + 1)
          .slice(0, 5)
          .map((el) => `${el.tagName.toLowerCase()}.${String(el.className || "").split(" ")[0]}`)
      : [];

    // Text whose own box is shorter than the text inside it, which is how a clipped line looks.
    const clipped = [...document.querySelectorAll("p, h1, h2, h3, h4, li, td, th, button, span, small, b, code")]
      .filter(visible)
      .filter((el) => {
        const style = getComputedStyle(el);
        if (style.overflow === "visible" || el.textContent.trim().length < 4) return false;
        if (style.textOverflow === "ellipsis" || style.overflowX === "auto" || style.overflowY === "auto") return false;
        return el.scrollHeight > el.clientHeight + 2 || el.scrollWidth > el.clientWidth + 2;
      })
      .slice(0, 5)
      .map((el) => `${el.tagName.toLowerCase()}: ${name(el).slice(0, 60)}`);

    const imagesWithoutText = [...document.querySelectorAll("img")]
      .filter(visible)
      .filter((img) => !img.alt && img.getAttribute("aria-hidden") !== "true")
      .map((img) => img.getAttribute("src")?.slice(0, 60) ?? "image");

    const namelessControls = [...document.querySelectorAll("button, a[href], [role=button]")]
      .filter(visible)
      .filter((el) => !name(el) && !el.getAttribute("aria-label") && !el.querySelector("img[alt]"))
      .map((el) => `${el.tagName.toLowerCase()}.${String(el.className || "").split(" ")[0]}`);

    const text = document.body.innerText.replace(/\s+/g, " ").trim();
    return {
      title: document.title,
      description: document.querySelector('meta[name="description"]')?.content ?? null,
      headings,
      controls,
      overflow,
      wide,
      clipped,
      imagesWithoutText,
      namelessControls,
      text,
      textLength: text.length,
    };
  });
}

/** Turns a reading into the problems it shows. Every entry here is something a person would call a bug. */
export function faults({ screen, width, reading, status, consoleErrors, failedRequests }) {
  const found = [];
  const fault = (kind, detail) => found.push({ screen: screen.name, width, kind, detail });

  const wanted = screen.expect?.status ?? [200];
  if (status != null && !wanted.includes(status)) fault("status", `answered ${status}, expected ${wanted.join(" or ")}`);

  // A browser logs one of these for every request that fails, which the requests below already
  // cover with the address attached. What is left here is the page's own errors.
  for (const message of consoleErrors) {
    if (message.startsWith("Failed to load resource")) continue;
    fault("console", message.slice(0, 200));
  }

  for (const request of failedRequests ?? []) {
    if (request.isDocument && wanted.includes(request.status)) continue;
    // Some requests are allowed to fail: an update check needs GitHub, and a machine without it
    // still has to show the page, which is what the screen says here.
    if ((screen.mayFail ?? []).some((path) => request.path.startsWith(path))) continue;
    fault("request", `${request.path} answered ${request.status}`);
  }

  for (const phrase of screen.mustSay ?? []) {
    if (!reading.text.includes(phrase)) fault("missing-text", `never says "${phrase}"`);
  }

  for (const phrase of NEVER_SAY) {
    if (reading.text.includes(phrase)) fault("bad-text", `says "${phrase}"`);
  }

  for (const { character, name } of BANNED_CHARACTERS) {
    if (reading.text.includes(character)) {
      const around = reading.text.slice(Math.max(0, reading.text.indexOf(character) - 40), reading.text.indexOf(character) + 40);
      fault("house-style", `${name} in "${around.trim()}"`);
    }
  }

  if (reading.overflow > 1) fault("overflow", `${reading.overflow}px sideways (${reading.wide.join(", ") || "unknown"})`);
  for (const one of reading.clipped) fault("clipped", one);
  for (const one of reading.imagesWithoutText) fault("image-without-text", one);
  for (const one of reading.namelessControls) fault("control-without-name", one);

  const h1s = reading.headings.filter((h) => h.level === 1);
  if (h1s.length === 0 && reading.textLength > 200) fault("headings", "no first-level heading");
  if (h1s.length > 1) fault("headings", `${h1s.length} first-level headings`);

  if (reading.textLength < 40) fault("empty", `only ${reading.textLength} characters of text`);
  return found;
}

/** Follows every link a screen offers, once per run, and reports the ones that lead nowhere. */
export async function checkLinks(request, origin, hrefs) {
  const broken = [];
  const seen = new Set();
  for (const href of hrefs) {
    if (!href || href.startsWith("#") || href.startsWith("mailto:")) continue;
    const url = new URL(href, origin);
    if (url.origin !== origin) continue; // Other people's sites are not ours to test.
    if (seen.has(url.pathname)) continue;
    seen.add(url.pathname);
    const response = await request.get(url.href, { failOnStatusCode: false });
    if (response.status() >= 400) broken.push({ href: url.pathname, status: response.status() });
  }
  return broken;
}

/** Controls nobody should click on a test run: they throw work away or sign someone out. */
const LEAVE_ALONE =
  /remove|delete|unlink|sign out|log out|stop|quit|reset|install|update|add account|add \w+ account|private|public|revoke|leave|disband|transfer|regenerate|rename/i;

/**
 * Presses every control a visitor could press and reports the ones that do nothing at all.
 *
 * "Does nothing" means the page did not change, the address did not change, and no message
 * appeared. A control that reports it can't act (sample data refuses changes) has still answered,
 * so it counts as alive.
 */
export async function pokeControls(page, screen) {
  const dead = [];
  const pressed = [];
  const handles = await page.$$("button:not([disabled]), summary, [role=button]:not([disabled])");
  for (const handle of handles) {
    let label;
    try {
      // A press a moment ago may have taken the page elsewhere, which leaves this handle behind.
      label = (await handle.evaluate((el) => (el.getAttribute("aria-label") || el.textContent || "").trim().replace(/\s+/g, " "))).slice(0, 60);
      if (!label || LEAVE_ALONE.test(label)) continue;
      if (!(await handle.isVisible()) || !(await handle.isEnabled())) continue;
    } catch {
      continue;
    }

    let before;
    try {
      before = await page.evaluate(() => ({
        html: document.body.innerHTML.length + ":" + document.body.innerText.length,
        url: location.href,
      }));
    } catch {
      continue;
    }
    try {
      await handle.click({ timeout: 2000, noWaitAfter: true });
    } catch {
      continue; // Something covered it mid-run; that is not the control's fault.
    }
    await page.waitForTimeout(450);
    let after;
    try {
      after = await page.evaluate(() => ({
        html: document.body.innerHTML.length + ":" + document.body.innerText.length,
        url: location.href,
        said: document.querySelector("#toast:not(.away), [role=status]")?.textContent?.trim() ?? "",
      }));
    } catch {
      // The page went somewhere while being read, which is the loudest possible answer.
      pressed.push(label);
      continue;
    }
    if (before.html === after.html && before.url === after.url && !after.said) {
      dead.push({ screen: screen.name, width: "laptop", kind: "dead-control", detail: `"${label}" does nothing when pressed` });
    }
    pressed.push(label);
  }
  return { dead, pressed };
}
