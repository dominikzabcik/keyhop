import { readFileSync } from 'node:fs';
import { expect } from 'e2e';

type App = { open: (path?: string) => Promise<void> };
type Browser = { evaluate: (fn: () => unknown) => Promise<unknown> };

/** The address the sample dashboard printed, including its session key. Empty until it has. */
function printedUrl(): string {
  try {
    const text = readFileSync(new URL('../../.e2e/logs/dashboard.log', import.meta.url), 'utf8');
    const line = text.split('\n').findLast((row) => row.includes('"url"'));
    if (!line) return '';
    const url = JSON.parse(line).url;
    return typeof url === 'string' ? url : '';
  } catch {
    return '';
  }
}

/** Opens one section of the sample window. The page keeps the session key from the hash. */
export async function openWindow(app: App, section = 'overview') {
  await expect.poll(() => printedUrl().startsWith('http'), { timeout: 15_000 }).toBe(true);
  const url = new URL(printedUrl());
  const params = new URLSearchParams(url.hash.slice(1));
  params.set('s', section);
  url.hash = params.toString();
  await app.open(url.toString());
}

/** Words that mean a value never resolved, or a dash the writing does not use. */
export async function assertReadable(browser: Browser) {
  const hit = await browser.evaluate(() => {
    const text = document.querySelector('#main')?.textContent ?? '';
    const banned = ['undefined', 'NaN', '[object Object]', '\u2014', '\u2013'];
    return banned.find((item) => text.includes(item)) ?? '';
  });
  expect(hit).toBe('');
}
