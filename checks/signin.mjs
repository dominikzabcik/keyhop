/**
 * A signed-in visitor for the local website.
 *
 * Half of Keyhop's pages only exist once someone is signed in, and signing in means GitHub. So the
 * local database is given an account and a browser session directly, the same rows the real sign-in
 * would write, and the browser is handed the matching cookie.
 *
 * This only ever touches the local database wrangler keeps under cloud/.wrangler. Nothing here can
 * reach the deployed site: it has no key for it, and it writes over a local file.
 */

import { execFile } from "node:child_process";
import { promisify } from "node:util";

const run = promisify(execFile);

export const SESSION_COOKIE = "keyhop_session";

/** The person the checks sign in as. Its usage makes the boards and the season worth looking at. */
export const VISITOR = {
  id: "11111111-1111-4111-8111-111111111111",
  githubId: 4242,
  login: "checks-visitor",
  name: "Checks Visitor",
};

const sha256 = async (text) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)))]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

async function sql(cwd, statements) {
  const command = statements.join("\n");
  await run("npx", ["wrangler", "d1", "execute", "switchr", "--local", "--command", command], { cwd, env: process.env });
}

/**
 * Puts an account, a session, a few days of usage and today's work into the local database, and
 * returns the cookie that signs a browser in as them. The work is one team and two tasks, so the
 * day page has something Jev can read rather than an empty state.
 */
export async function signIn(cloudDirectory) {
  const token = `checks-${crypto.randomUUID()}`;
  const hash = await sha256(token);
  const now = Math.floor(Date.now() / 1000);
  const day = (back) => new Date((now - back * 86_400) * 1000).toISOString().slice(0, 10);

  const quoted = (value) => `'${String(value).replace(/'/g, "''")}'`;
  const usage = ["claude", "codex", "cursor"]
    .flatMap((tool, index) =>
      [0, 1, 2, 3].map(
        (back) =>
          `INSERT OR REPLACE INTO daily_usage (user_id, day, tool, tokens, cost_micros, requests, updated_at)
           VALUES (${quoted(VISITOR.id)}, ${quoted(day(back))}, ${quoted(tool)}, ${(index + 1) * 1_000_000 + back * 1000},
                   ${(index + 1) * 250_000}, ${(index + 1) * 40 + back}, ${now});`,
      ),
    );

  await sql(cloudDirectory, [
    `INSERT OR REPLACE INTO users (id, github_id, login, name, avatar_url, public, created_at, updated_at)
     VALUES (${quoted(VISITOR.id)}, ${VISITOR.githubId}, ${quoted(VISITOR.login)}, ${quoted(VISITOR.name)}, NULL, 1, ${now}, ${now});`,
    `DELETE FROM sessions WHERE user_id = ${quoted(VISITOR.id)};`,
    `INSERT INTO sessions (id, token_hash, user_id, kind, created_at, last_used_at, expires_at)
     VALUES (${quoted(crypto.randomUUID())}, ${quoted(hash)}, ${quoted(VISITOR.id)}, 'web', ${now}, ${now}, ${now + 86_400});`,
    ...usage,
    `INSERT OR REPLACE INTO teams (id, slug, name, owner_id, created_at)
     VALUES ('22222222-2222-4222-8222-222222222222', 'checks', 'Checks', ${quoted(VISITOR.id)}, ${now});`,
    `INSERT OR REPLACE INTO team_members (team_id, user_id, role, joined_at)
     VALUES ('22222222-2222-4222-8222-222222222222', ${quoted(VISITOR.id)}, 'owner', ${now});`,
    `INSERT OR REPLACE INTO daily_work (user_id, day, repo, commits, insertions, deletions, updated_at)
     VALUES (${quoted(VISITOR.id)}, ${quoted(day(0))}, 'acme/atlas', 3, 40, 8, ${now});`,
    `INSERT OR REPLACE INTO work_commits (user_id, day, repo, sha, subject, insertions, deletions, at, offset_seconds)
     VALUES (${quoted(VISITOR.id)}, ${quoted(day(0))}, 'acme/atlas', 'a1b2c3d', 'feat(importer): stop a dead job retrying forever', 20, 4, ${now - 7200}, 0);`,
    `INSERT OR REPLACE INTO work_commits (user_id, day, repo, sha, subject, insertions, deletions, at, offset_seconds)
     VALUES (${quoted(VISITOR.id)}, ${quoted(day(0))}, 'acme/atlas', 'b2c3d4e', 'fix(importer): retry with a ceiling', 12, 3, ${now - 5400}, 0);`,
    `INSERT OR REPLACE INTO work_commits (user_id, day, repo, sha, subject, insertions, deletions, at, offset_seconds)
     VALUES (${quoted(VISITOR.id)}, ${quoted(day(0))}, 'acme/atlas', 'c3d4e5f', 'docs: write down what the sync actually does', 8, 1, ${now - 1800}, 0);`,
    `INSERT OR REPLACE INTO work_index (user_id, done, total, complete, updated_at)
     VALUES (${quoted(VISITOR.id)}, 1, 1, 1, ${now});`,
  ]);

  return { name: SESSION_COOKIE, value: token, path: "/", httpOnly: true, sameSite: "Lax" };
}
