import { test } from '@e2e-dev/web';
import { expect } from 'e2e';
import { assertReadable, openWindow } from './sample-window.ts';

test('the sidebar lists its five places from the top', async ({ app, browser }) => {
  await openWindow(app, 'overview');
  await expect.poll(() => browser.evaluate(() => {
    const community = document.querySelector('#nav a[data-group="community"]');
    return !!community && !(community as HTMLElement).hidden;
  })).toBe(true);

  const layout = await browser.evaluate(() => {
    const nav = document.querySelector('#nav');
    if (!nav) return null;
    const items = [...nav.children].filter((el) => !(el as HTMLElement).hidden);
    const boxes = items.map((el) => {
      const box = el.getBoundingClientRect();
      const clone = el.cloneNode(true) as HTMLElement;
      clone.querySelectorAll('.nav-count').forEach((node) => node.remove());
      return { name: (clone.textContent || '').replace(/\s+/g, ' ').trim(), top: box.top, bottom: box.bottom };
    });
    let maxGap = 0;
    for (let i = 1; i < boxes.length; i++) maxGap = Math.max(maxGap, boxes[i].top - boxes[i - 1].bottom);
    const tree = document.querySelector('#tree');
    const settings = document.querySelector('.side-foot a[data-section="settings"]');
    const treeBox = tree?.getBoundingClientRect();
    const settingsBox = settings?.getBoundingClientRect();
    return {
      names: boxes.map((box) => box.name),
      maxGap,
      treeHeight: treeBox?.height ?? 0,
      settingsBelow: !!treeBox && !!settingsBox && settingsBox.top >= treeBox.bottom - 1,
    };
  });

  expect(layout?.names).toEqual(['Home', 'Limits', 'Usage', 'Insights', 'Community']);
  expect(layout?.maxGap ?? 999).toBeLessThan(12);
  // The logins in use take the leftover height. Settings sits under them.
  expect(layout?.treeHeight ?? 0).toBeGreaterThan(24);
  expect(layout?.settingsBelow).toBe(true);
});

test('a place with several sections shows them as tabs and remembers the last one', async ({ app, screen, browser }) => {
  await openWindow(app, 'plans');
  await expect(screen.getByRole('heading', 'Insights', { level: 1 })).toBeVisible();
  await expect(browser.locator('#subnav [data-section="plans"]')).toHaveAttribute('aria-pressed', 'true');
  await browser.locator('#subnav [data-section="budgets"]').tap();
  await expect(screen.getByRole('heading', 'Budgets', { level: 2 })).toBeVisible();
  await browser.locator('#nav a[data-group="usage"]').tap();
  await expect(screen.getByRole('heading', 'Usage', { level: 1 })).toBeVisible();
  await browser.locator('#nav a[data-group="insights"]').tap();
  await expect(browser.locator('#subnav [data-section="budgets"]')).toHaveAttribute('aria-pressed', 'true');
});

test('home is today: the wallpaper, what needs you and the week', async ({ app, screen, browser }) => {
  await openWindow(app, 'overview');
  await expect(screen.getByRole('heading', 'Home', { level: 1 })).toBeVisible();
  await expect(screen.getByRole('heading', 'Needs your attention')).toBeVisible();
  await expect(screen.getByRole('heading', 'In use')).toBeVisible();
  await expect(screen.getByRole('heading', 'Overview')).toBeVisible();
  await expect(screen.getByText('Current streak')).toBeVisible();
  // Work is counted in the sample, so the figures carry commits and the leaderboard's measure.
  await expect(screen.getByText('per M tokens', { exact: false }).first()).toBeVisible();
  // The wallpaper is one element, carried into Home's hero on every draw.
  await expect.poll(() => browser.evaluate(() => {
    const art = document.querySelector('.hero #hero-art') as HTMLElement | null;
    return !!art && !art.hidden && art.getBoundingClientRect().height > 100;
  })).toBe(true);
  await screen.getByRole('button', { name: '30 days', exact: true }).tap();
  await expect(screen.getByRole('button', { name: '30 days', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await expect(screen.getByText('vs the 30 days before').first()).toBeVisible();
  await assertReadable(browser);
});

test('limits pools every login and projects it', async ({ app, screen, browser }) => {
  await openWindow(app, 'limits');
  await expect(screen.getByRole('heading', 'Limits', { level: 1 })).toBeVisible();
  await expect(screen.getByText('Left across your own logins', { exact: false })).toBeVisible();
  await expect(screen.getByText('Next reset', { exact: false })).toBeVisible();
  await expect(browser.locator('.qchart svg .qline.ahead')).toBeVisible();
  await expect(screen.getByRole('heading', 'Claude Code', { level: 2 })).toBeVisible();
  await browser.locator('[data-action="quota-tool"][data-value="codex"]').tap();
  await expect(screen.getByText('Codex login', { exact: false }).first()).toBeVisible();
  await screen.getByRole('button', { name: 'Drain rate', exact: true }).tap();
  await expect(browser.locator('.qchart svg .qbar').first()).toBeVisible();
  await assertReadable(browser);
});

test('an old link to accounts opens limits, which can add another login', async ({ app, screen, browser }) => {
  await openWindow(app, 'accounts');
  await expect(screen.getByRole('heading', 'Limits', { level: 1 })).toBeVisible();
  await expect.poll(() => screen.getByRole('button', 'Add account').count()).toBeGreaterThan(0);
  await expect(screen.getByRole('button', 'Switch and sign in').first()).toBeVisible();
  await assertReadable(browser);
});

test('usage names the token columns', async ({ app, screen, browser }) => {
  await openWindow(app, 'usage');
  await expect(screen.getByRole('heading', 'Usage', { level: 1 })).toBeVisible();
  await expect(screen.getByRole('columnheader', 'Cache read')).toBeVisible();
  await expect(screen.getByRole('columnheader', 'API value')).toBeVisible();
  await assertReadable(browser);
});

test('budgets is its own list', async ({ app, screen, browser }) => {
  await openWindow(app, 'budgets');
  await expect(screen.getByRole('heading', 'Insights', { level: 1 })).toBeVisible();
  await expect(screen.getByRole('heading', 'Budgets', { level: 2 })).toBeVisible();
  await assertReadable(browser);
});

test('plans price each login against the month', async ({ app, screen, browser }) => {
  await openWindow(app, 'plans');
  await expect(screen.getByRole('heading', 'Insights', { level: 1 })).toBeVisible();
  await expect(browser.locator('#subnav [data-section="plans"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(screen.getByText('You pay', { exact: false })).toBeVisible();
  await expect(screen.getByText('API value this month', { exact: false }).first()).toBeVisible();
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
  await expect(browser.locator('#subnav [data-section="leaderboard"]')).toHaveAttribute('aria-pressed', 'true');
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
  await expect(browser.locator('#subnav [data-section="season"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(screen.getByRole('heading', 'Season standings')).toBeVisible();
  await assertReadable(browser);
});

test('teams opens on the list', async ({ app, screen, browser }) => {
  await openWindow(app, 'teams');
  await expect(screen.getByRole('heading', 'Community', { level: 1 })).toBeVisible();
  await expect(browser.locator('#subnav [data-section="teams"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(screen.getByRole('heading', 'Your teams')).toBeVisible();
  await assertReadable(browser);
});

test('profile holds the pet, keeps, quests and badges', async ({ app, screen, browser }) => {
  await openWindow(app, 'profile');
  await expect(screen.getByRole('heading', 'Community', { level: 1 })).toBeVisible();
  await expect(browser.locator('#subnav [data-section="profile"]')).toHaveAttribute('aria-pressed', 'true');
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

test('the sidebar stays packed in the smallest window', async ({ app, browser }) => {
  await openWindow(app, 'overview');
  await browser.setViewport({ width: 960, height: 620 });
  await expect.poll(() => browser.evaluate(() => {
    const community = document.querySelector('#nav a[data-group="community"]');
    if (!community || (community as HTMLElement).hidden) return 999;
    const nav = document.querySelector('#nav');
    if (!nav) return 999;
    const boxes = [...nav.children].filter((el) => !(el as HTMLElement).hidden).map((el) => el.getBoundingClientRect());
    let maxGap = 0;
    for (let i = 1; i < boxes.length; i++) maxGap = Math.max(maxGap, boxes[i].top - boxes[i - 1].bottom);
    return maxGap;
  })).toBeLessThan(12);
});

test('Hop lists the sections a linked account can open', async ({ app, screen }) => {
  await openWindow(app, 'overview');
  await screen.getByRole('button', 'Hop', { exact: true }).tap();
  await expect(screen.getByRole('dialog', 'Hop')).toBeVisible();
  for (const name of ['Home', 'Coach', 'Plans', 'Leaderboard', 'Season', 'Teams', 'Profile', 'Settings']) {
    await expect(screen.getByRole('option', name, { exact: false })).toBeVisible();
  }
});

test('settings keeps the link, the profile and the phone together', async ({ app, screen, browser }) => {
  await openWindow(app, 'settings');
  await expect(screen.getByRole('heading', 'Window Appearance')).toBeVisible();
  await screen.getByRole('button', 'Activity').tap();
  await expect(screen.getByRole('heading', 'Activity')).toBeVisible();
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

test('the status bar turns the field from night to day and back', async ({ app, screen, browser }) => {
  await openWindow(app, 'overview');
  const field = () => browser.evaluate(() => document.documentElement.dataset.theme ?? '');
  await expect.poll(field).toBe('night');
  await screen.getByRole('button', { name: 'Night', exact: true }).click();
  await expect.poll(field).toBe('day');
  await expect(screen.getByRole('button', { name: 'Day', exact: true })).toBeVisible();
  // The choice is saved, so another open of the window is still by day.
  await openWindow(app, 'usage');
  await expect.poll(field).toBe('day');
  await assertReadable(browser);
  await screen.getByRole('button', { name: 'Day', exact: true }).click();
  await expect.poll(field).toBe('night');
});
