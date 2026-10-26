import { test } from '@e2e-dev/web';
import { expect } from 'e2e';
import { assertReadable, openWindow } from './sample-window.ts';

test('home is the verdict, the logins ranked by runway, and today', async ({ app, browser }) => {
  await openWindow(app, 'home');
  await expect(browser.locator('.core .verdict p')).toBeVisible();
  const core = await browser.evaluate(() => {
    const rows = [...document.querySelectorAll('.core .logins .row')];
    const verdict = document.querySelector('.core .verdict p')?.textContent?.trim() ?? '';
    return {
      verdict,
      rows: rows.length,
      firstIsCrit: rows[0]?.classList.contains('crit') ?? false,
      idleLast: rows.length > 0 && [...rows].reverse().findIndex((row) => !row.classList.contains('idle')) <= rows.length - 1
        && rows.findIndex((row) => row.classList.contains('idle')) > rows.findIndex((row) => !row.classList.contains('idle')),
      noSpare: document.querySelectorAll('.core .flag').length,
      sidebar: document.querySelectorAll('#nav, .sidebar').length,
    };
  });
  expect(core?.verdict.length ?? 0).toBeGreaterThan(10);
  expect(core?.rows ?? 0).toBeGreaterThan(5);
  // The row that stops you first sits on top, tinted; measured-only tools sink below the rest.
  expect(core?.firstIsCrit).toBe(true);
  expect(core?.idleLast).toBe(true);
  expect(core?.noSpare ?? 0).toBeGreaterThan(0);
  expect(core?.sidebar).toBe(0);
  await assertReadable(browser);
});

test('rows carry no controls; the verdict holds the one hop', async ({ app, browser }) => {
  await openWindow(app, 'home');
  await expect(browser.locator('.core .logins').first()).toBeVisible();
  const controls = await browser.evaluate(() => ({
    inRows: document.querySelectorAll('.core .logins button, .core .logins a').length,
    hops: document.querySelectorAll('.core .verdict button').length,
  }));
  expect(controls?.inRows).toBe(0);
  expect(controls?.hops ?? 9).toBeLessThan(2);
});

test('today sums the day in figures and the title bar holds the views', async ({ app, screen, browser }) => {
  await openWindow(app, 'home');
  await expect(browser.locator('.core .today .num')).toBeVisible();
  await expect(screen.getByText('tokens today at API prices', { exact: false })).toBeVisible();
  await expect(screen.getByText('requests', { exact: false }).first()).toBeVisible();
  // The share of the day, one bar and its key, tool by tool.
  await expect.poll(() => browser.evaluate(() => document.querySelectorAll('.core .sharebar i').length)).toBeGreaterThan(2);
  // The views live in the title bar, the way an app's do, and remember where they were.
  await expect(browser.locator('#topnav [data-group="home"]')).toHaveAttribute('aria-current', 'page');
  await browser.locator('#topnav [data-group="history"]').tap();
  await expect(screen.getByRole('heading', 'History', { level: 1 })).toBeVisible();
  await expect(browser.locator('#topnav [data-group="history"]')).toHaveAttribute('aria-current', 'page');
});

test('an old link to overview opens the core, and accounts opens limits', async ({ app, screen, browser }) => {
  await openWindow(app, 'overview');
  await expect(browser.locator('.core .verdict p')).toBeVisible();
  await openWindow(app, 'accounts');
  await expect(screen.getByRole('heading', 'History', { level: 1 })).toBeVisible();
  await expect(browser.locator('#viewtabs [data-section="limits"]')).toHaveAttribute('aria-pressed', 'true');
  await expect.poll(() => screen.getByRole('button', 'Add login').count()).toBeGreaterThan(0);
  await expect(screen.getByRole('button', 'Sign in').first()).toBeVisible();
  await assertReadable(browser);
});

test('limits lists each login with what it has used, and no guesses', async ({ app, screen, browser }) => {
  await openWindow(app, 'limits');
  await expect(screen.getByRole('heading', 'History', { level: 1 })).toBeVisible();
  await expect(screen.getByRole('heading', 'Claude Code', { level: 2 })).toBeVisible();
  await expect(screen.getByText('In use', { exact: true }).first()).toBeVisible();
  await expect(screen.getByText('resets in', { exact: false }).first()).toBeVisible();
  // The detail view shows what the tools report, never when a limit might run out.
  for (const guess of ['runs out', 'Empty around', 'At this pace', 'Projected']) {
    await expect(screen.getByText(guess, { exact: false })).toHaveCount(0);
  }
  // Above the logins, what they have left and how it went: readings only, from 24 hours to 7 days.
  await expect(screen.getByRole('heading', 'What your logins have left', { level: 2 })).toBeVisible();
  await expect(screen.getByRole('heading', 'The last 24 hours', { level: 2 })).toBeVisible();
  await expect(browser.locator('.qchart svg .qline')).toHaveCount(1);
  await browser.locator('[data-action="quota-hours"][data-value="168"]').tap();
  await expect(screen.getByRole('heading', 'The last 7 days', { level: 2 })).toBeVisible();
  await browser.locator('[data-action="quota-view"][data-value="drain"]').tap();
  await expect.poll(() => browser.evaluate(() => document.querySelectorAll('.qchart svg .qbar').length)).toBeGreaterThan(0);
  await browser.locator('[data-action="quota-tool"][data-value="codex"]').tap();
  await expect(screen.getByRole('heading', 'Codex', { level: 2 })).toBeVisible();
  await expect(screen.getByRole('heading', 'Claude Code', { level: 2 })).toHaveCount(0);
  await assertReadable(browser);
});

test('a Claude Code login offers the command that runs it in one terminal', async ({ app, browser }) => {
  await openWindow(app, 'limits');
  await expect.poll(() => browser.evaluate(() => document.querySelectorAll('.lim-group[aria-label="Claude Code"] [data-action="account-menu"]').length)).toBeGreaterThan(0);
  const command = await browser.evaluate(() => {
    (document.querySelector('.lim-group[aria-label="Claude Code"] [data-action="account-menu"]') as HTMLElement).click();
    return new Promise((done) => setTimeout(() => done(document.querySelector('.row-menu [data-action="copy"]')?.getAttribute('data-value') ?? null), 300));
  });
  expect(command).toMatch(/^keyhop run \S+ --tool claude -- claude$/);
  const keep = await browser.evaluate(() => document.querySelector('.row-menu [data-action="reserve"]')?.textContent?.trim() ?? null);
  expect(keep).toBe('Keep for last');
});

test('usage names the token columns', async ({ app, screen, browser }) => {
  await openWindow(app, 'usage');
  await expect(screen.getByRole('heading', 'History', { level: 1 })).toBeVisible();
  await expect(browser.locator('#viewtabs [data-section="usage"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(screen.getByRole('columnheader', 'Cache read')).toBeVisible();
  await expect(screen.getByRole('columnheader', 'API value')).toBeVisible();
  await assertReadable(browser);
});

test('insights holds coach, plans and budgets as tabs', async ({ app, screen, browser }) => {
  await openWindow(app, 'plans');
  await expect(screen.getByRole('heading', 'Insights', { level: 1 })).toBeVisible();
  await expect(browser.locator('#viewtabs [data-section="plans"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(screen.getByText('a month in plans', { exact: true })).toBeVisible();
  // One row a login, and no paragraphs: no verdicts and no pace.
  await expect.poll(() => browser.evaluate(() => document.querySelectorAll('.plans-table tbody tr').length)).toBeGreaterThan(1);
  await expect(screen.getByText('on pace for', { exact: false })).toHaveCount(0);
  await browser.locator('#viewtabs [data-section="budgets"]').tap();
  await expect(screen.getByRole('heading', 'Budgets', { level: 2 })).toBeVisible();
  // The group remembers the tab it was on.
  await openWindow(app, 'usage');
  await expect(screen.getByRole('heading', 'History', { level: 1 })).toBeVisible();
  await assertReadable(browser);
});

test('coach reads optimize, compare and yield', async ({ app, screen, browser }) => {
  await openWindow(app, 'coach');
  await expect(screen.getByRole('heading', 'Insights', { level: 1 })).toBeVisible();
  await expect(screen.getByRole('heading', 'Optimize', { level: 2 })).toBeVisible();
  await expect(screen.getByRole('heading', 'Compare', { level: 2 })).toBeVisible();
  await expect(screen.getByRole('heading', 'Yield', { level: 2 })).toBeVisible();
  await expect(screen.getByText('Per merge').first()).toBeVisible();
  await assertReadable(browser);
});

test('leaderboard is the ranks, by efficiency first', async ({ app, screen, browser }) => {
  await openWindow(app, 'leaderboard');
  await expect(screen.getByRole('heading', 'Community', { level: 1 })).toBeVisible();
  await expect(browser.locator('#viewtabs [data-section="leaderboard"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(screen.getByText('Your rank')).toBeVisible();
  await expect(screen.getByRole('button', { name: 'Efficiency', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await expect(screen.getByText('Commits per M tokens')).toBeVisible();
  await expect(screen.getByRole('button', { name: 'Everyone', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await screen.getByRole('button', { name: 'Tokens', exact: true }).tap();
  await expect(screen.getByRole('button', { name: 'Tokens', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await assertReadable(browser);
});

test('season is the standings', async ({ app, screen, browser }) => {
  await openWindow(app, 'season');
  await expect(screen.getByRole('heading', 'Community', { level: 1 })).toBeVisible();
  await expect(browser.locator('#viewtabs [data-section="season"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(screen.getByRole('heading', 'Season standings')).toBeVisible();
  await assertReadable(browser);
});

test('teams opens on the list', async ({ app, screen, browser }) => {
  await openWindow(app, 'teams');
  await expect(screen.getByRole('heading', 'Community', { level: 1 })).toBeVisible();
  await expect(browser.locator('#viewtabs [data-section="teams"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(screen.getByRole('heading', 'Your teams')).toBeVisible();
  await assertReadable(browser);
});

test('profile holds the pet, keeps, quests and badges', async ({ app, screen, browser }) => {
  await openWindow(app, 'profile');
  await expect(screen.getByRole('heading', 'Community', { level: 1 })).toBeVisible();
  await expect(browser.locator('#viewtabs [data-section="profile"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(screen.getByRole('heading', 'Keeps')).toBeVisible();
  await expect(screen.getByRole('heading', 'Quests')).toBeVisible();
  await expect(screen.getByRole('heading', 'Badges')).toBeVisible();
  await assertReadable(browser);
});

test('a team splits into its day, its ranks and its members', async ({ app, screen, browser }) => {
  await openWindow(app, 'teams');
  await expect(screen.getByRole('heading', 'Your teams')).toBeVisible();
  await browser.locator('[data-action="board-pick"][data-value="night-shift"]').tap();
  await expect(screen.getByText('Open this day on the website')).toBeVisible();
  await browser.locator('[data-action="board-view"][data-value="ranks"]').tap();
  await expect(screen.getByText('Your rank')).toBeVisible();
  await browser.locator('[data-action="board-view"][data-value="members"]').tap();
  await expect(screen.getByRole('button', 'Leave Night Shift')).toBeVisible();
  await assertReadable(browser);
});

test('the core fits the smallest window with nothing cut off sideways', async ({ app, browser }) => {
  await openWindow(app, 'home');
  await browser.setViewport({ width: 760, height: 520 });
  await expect(browser.locator('.core .verdict p')).toBeVisible();
  const overflow = await browser.evaluate(() => {
    const doc = document.scrollingElement!;
    return Math.max(doc.scrollWidth - doc.clientWidth, document.querySelector('.main')!.scrollWidth - document.querySelector('.main')!.clientWidth);
  });
  expect(overflow).toBe(0);
});

test('escape steps back from a demoted view to the core', async ({ app, screen, browser }) => {
  await openWindow(app, 'usage');
  await expect(screen.getByRole('heading', 'History', { level: 1 })).toBeVisible();
  await browser.evaluate(() => document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })));
  await expect(browser.locator('.core .verdict p')).toBeVisible();
});

test('settings opens on activity, with no appearance pane left', async ({ app, screen, browser }) => {
  await openWindow(app, 'settings');
  await expect(screen.getByRole('heading', 'Settings', { level: 1 })).toBeVisible();
  await expect(screen.getByRole('heading', 'Activity')).toBeVisible();
  await expect(screen.getByText('Window Appearance', { exact: false })).toHaveCount(0);
  await screen.getByRole('button', 'Cloud').tap();
  await expect(screen.getByRole('heading', 'How you appear')).toBeVisible();
  await expect(screen.getByRole('heading', 'This computer')).toBeVisible();
  await expect(screen.getByRole('heading', 'Live')).toBeVisible();
  // The exact payloads are shown on request, section by section, before anything is sent.
  await expect(screen.getByRole('heading', 'What this computer sends')).toBeVisible();
  await screen.getByRole('button', 'Show the exact data').tap();
  await expect(screen.getByText('POST /api/usage')).toBeVisible();
  await expect(screen.getByText('POST /api/live')).toBeVisible();
  await screen.getByRole('button', 'App & Privacy').tap();
  await expect(screen.getByRole('heading', 'App & Privacy')).toBeVisible();
  await assertReadable(browser);
});

test('settings sets up the browser extension and says whether it is connected', async ({ app, screen, browser }) => {
  await openWindow(app, 'settings');
  await browser.locator('[data-action="settings-pane"][data-value="browser"]').tap();
  await expect(screen.getByRole('heading', 'Chrome extension', { level: 2 })).toBeVisible();
  await expect(screen.getByText('Connected', { exact: false }).first()).toBeVisible();
  await expect(screen.getByText('Site logins kept', { exact: false })).toBeVisible();
  await expect(screen.getByRole('button', 'Set up again')).toBeVisible();
  await assertReadable(browser);
});
