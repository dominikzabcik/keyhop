import { fileURLToPath } from 'node:url';
import { beforeAll, test } from '@e2e-dev/web';
import { expect } from 'e2e';
import { signIn } from '../../checks/signin.mjs';

const cloud = fileURLToPath(new URL('../../cloud/', import.meta.url));
let session: { name: string; value: string };

beforeAll(async () => {
  session = await signIn(cloud);
});

async function openSignedIn(
  app: { baseUrl?: string; open: (path?: string) => Promise<void> },
  browser: { setCookies: (cookies: { name: string; value: string; url: string }[]) => Promise<void> },
  path: string,
) {
  await browser.setCookies([{ name: session.name, value: session.value, url: app.baseUrl ?? '' }]);
  await app.open(path);
}

test('a signed-in profile shows the pet, keeps, quests and badges', async ({ app, screen, browser }) => {
  await openSignedIn(app, browser, '/u/checks-visitor');
  await expect(screen.getByRole('heading', 'Checks Visitor')).toBeVisible();
  await expect(screen.getByRole('heading', 'Keeps')).toBeVisible();
  await expect(screen.getByRole('heading', 'Quests')).toBeVisible();
  await expect(screen.getByText('Today and this week')).toBeVisible();
  await expect(screen.getByRole('heading', 'Badges')).toBeVisible();
  await expect(screen.getByText('Share image')).toBeVisible();
});

test('settings is the signed-in account', async ({ app, screen, browser }) => {
  await openSignedIn(app, browser, '/settings');
  await expect(screen.getByRole('heading', 'Settings')).toBeVisible();
  await expect(screen.getByText('Signed in as @checks-visitor with GitHub.')).toBeVisible();
});

test('teams lists the one this account owns', async ({ app, screen, browser }) => {
  await openSignedIn(app, browser, '/teams');
  await expect(screen.getByRole('heading', 'Teams')).toBeVisible();
  await expect(screen.getByRole('heading', 'Create a team')).toBeVisible();
  await expect(screen.getByText('Checks')).toBeVisible();
});

test('a team page is its ranks and points at the day', async ({ app, screen, browser }) => {
  await openSignedIn(app, browser, '/t/checks');
  await expect(screen.getByRole('heading', 'Checks')).toBeVisible();
  await expect(screen.getByRole('link', 'See today')).toBeVisible();
});

test('the team day is today and the work that was synced', async ({ app, screen, browser }) => {
  await openSignedIn(app, browser, '/t/checks/day');
  await expect(screen.getByRole('heading', 'Today')).toBeVisible();
  await expect(screen.getByText('importer', { exact: false })).toBeVisible();
});

test('the season is the standings and the ladder', async ({ app, screen, browser }) => {
  await openSignedIn(app, browser, '/season');
  await expect(screen.getByRole('heading', 'Season')).toBeVisible();
  await expect(screen.getByRole('heading', 'The ladder')).toBeVisible();
  await expect(screen.getByRole('heading', 'Keeps')).not.toBeVisible();
  await expect(screen.getByRole('heading', 'Quests')).not.toBeVisible();
});

test('welcome and link are the two ways onto the account', async ({ app, screen, browser }) => {
  await openSignedIn(app, browser, '/welcome');
  await expect(screen.getByRole('heading', 'Welcome, Checks Visitor')).toBeVisible();
  await openSignedIn(app, browser, '/link');
  await expect(screen.getByRole('heading', 'Link Keyhop')).toBeVisible();
});
