import { test } from '@e2e-dev/web';
import { expect } from 'e2e';
import { assertReadable, openWindow } from './sample-window.ts';

test('the sidebar lists its sections from the top', async ({ app, browser }) => {
  await openWindow(app, 'overview');
  await expect.poll(() => browser.evaluate(() => {
    const label = document.querySelector('#cloud-label');
    return !!label && !(label as HTMLElement).hidden;
  })).toBe(true);

  const layout = await browser.evaluate(() => {
    const nav = document.querySelector('#nav');
    if (!nav) return null;
    const items = [...nav.children].filter((el) => !(el as HTMLElement).hidden);
    const boxes = items.map((el) => {
      const box = el.getBoundingClientRect();
      return { name: (el.textContent || '').replace(/\s+/g, ' ').trim(), top: box.top, bottom: box.bottom };
    });
    let maxGap = 0;
    for (let i = 1; i < boxes.length; i++) maxGap = Math.max(maxGap, boxes[i].top - boxes[i - 1].bottom);
    const settings = boxes.find((box) => box.name === 'Settings');
    const navBox = nav.getBoundingClientRect();
    return {
      names: boxes.map((box) => box.name),
      maxGap,
      tail: settings ? navBox.bottom - settings.bottom : 0,
    };
  });

  expect(layout?.names).toEqual([
    'Overview', 'Accounts', 'Usage', 'Budgets', 'Cloud',
    'Leaderboard', 'Season', 'Teams', 'Profile', 'Settings',
  ]);
  // The Cloud label's own margin is the widest intended gap. A stretched row is hundreds of pixels.
  expect(layout?.maxGap ?? 999).toBeLessThan(40);
  // Leftover height stays under Settings, above the footer, rather than between Budgets and Cloud.
  expect(layout?.tail ?? 0).toBeGreaterThan(80);
});

test('overview is this computer today', async ({ app, screen, browser }) => {
  await openWindow(app, 'overview');
  await expect(screen.getByRole('heading', 'Overview', { level: 1 })).toBeVisible();
  await expect(screen.getByRole('heading', 'In use')).toBeVisible();
  await assertReadable(browser);
});

test('accounts offers another login', async ({ app, screen, browser }) => {
  await openWindow(app, 'accounts');
  await expect(screen.getByRole('heading', 'Accounts', { level: 1 })).toBeVisible();
  await expect.poll(() => screen.getByRole('button', 'Add account').count()).toBeGreaterThan(0);
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
  await expect(screen.getByRole('heading', 'Budgets', { level: 1 })).toBeVisible();
  await expect(screen.getByRole('heading', 'Budgets', { level: 2 })).toBeVisible();
  await assertReadable(browser);
});

test('leaderboard is the ranks', async ({ app, screen, browser }) => {
  await openWindow(app, 'leaderboard');
  await expect(screen.getByRole('heading', 'Leaderboard', { level: 1 })).toBeVisible();
  await expect(screen.getByText('Your rank')).toBeVisible();
  await assertReadable(browser);
});

test('season is the standings', async ({ app, screen, browser }) => {
  await openWindow(app, 'season');
  await expect(screen.getByRole('heading', 'Season', { level: 1 })).toBeVisible();
  await expect(screen.getByRole('heading', 'Season standings')).toBeVisible();
  await assertReadable(browser);
});

test('teams opens on the list', async ({ app, screen, browser }) => {
  await openWindow(app, 'teams');
  await expect(screen.getByRole('heading', 'Teams', { level: 1 })).toBeVisible();
  await expect(screen.getByRole('heading', 'Your teams')).toBeVisible();
  await assertReadable(browser);
});

test('profile holds the pet, keeps, quests and badges', async ({ app, screen, browser }) => {
  await openWindow(app, 'profile');
  await expect(screen.getByRole('heading', 'Profile', { level: 1 })).toBeVisible();
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

test('settings keeps the link, the profile and the phone together', async ({ app, screen, browser }) => {
  await openWindow(app, 'settings');
  await expect(screen.getByRole('heading', 'Window Appearance')).toBeVisible();
  await screen.getByRole('button', 'Activity').tap();
  await expect(screen.getByRole('heading', 'Activity')).toBeVisible();
  await screen.getByRole('button', 'Cloud').tap();
  await expect(screen.getByRole('heading', 'How you appear')).toBeVisible();
  await expect(screen.getByRole('heading', 'This computer')).toBeVisible();
  await screen.getByRole('button', 'App & Privacy').tap();
  await expect(screen.getByRole('heading', 'App & Privacy')).toBeVisible();
  await assertReadable(browser);
});
