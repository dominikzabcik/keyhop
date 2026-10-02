import { test } from '@e2e-dev/web';
import { expect } from 'e2e';

const pages: { path: string; heading: string; text?: string; link?: string; headings?: string[] }[] = [
  { path: '/', heading: 'Every account.', text: 'Download Keyhop' },
  { path: '/download', heading: 'Ready on every desktop.', headings: ['macOS', 'Linux', 'Windows'] },
  { path: '/leaderboard', heading: 'Leaderboard' },
  { path: '/season', heading: 'Season', text: 'A season runs for one calendar month.' },
  { path: '/privacy', heading: 'Your work is not the product.', text: 'What stays on your computer' },
  { path: '/terms', heading: 'Use Keyhop with accounts that are yours.', text: 'Provider rules still apply' },
  { path: '/security', heading: 'Report problems privately.', text: 'Open a private report' },
  { path: '/login', heading: 'Sign in to Keyhop', link: 'Continue with GitHub' },
];

for (const page of pages) {
  test(`${page.path} says what it is for`, async ({ app, screen, browser }) => {
    await app.open(page.path);
    await expect(screen.getByRole('heading', page.heading, { exact: false })).toBeVisible();
    if (page.text) await expect(screen.getByText(page.text, { exact: false })).toBeVisible();
    if (page.link) await expect(screen.getByRole('link', page.link)).toBeVisible();
    for (const heading of page.headings ?? []) await expect(screen.getByRole('heading', heading)).toBeVisible();
    await expect.poll(() => browser.evaluate(() => {
      const text = document.body?.innerText ?? '';
      const banned = ['undefined', 'NaN', '[object Object]', '\u2014', '\u2013'];
      return banned.find((item) => text.includes(item)) ?? '';
    })).toBe('');
  });
}

test('a missing page says it is missing', async ({ app, screen }) => {
  const response = await fetch(new URL('/no-such-page', app.baseUrl));
  expect(response.status).toBe(404);
  await app.open('/no-such-page');
  await expect(screen.getByRole('heading', 'Not found')).toBeVisible();
});
