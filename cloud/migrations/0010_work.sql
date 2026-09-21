-- What someone built in a day, counted from the git repositories on their own computer.
--
-- Keyhop already knows what a day cost in tokens. This is the other half of the same day: the
-- commits that came out of it. The app reads its own clones with `git log`, counts only commits the
-- person authored, and leaves merges out, so the number is work done rather than history moved.
--
-- Each upload is a complete statement of one day in one repository, and replaces what was there.
-- That is what makes a rebase harmless: rewritten commits are new objects, but the day they belong
-- to is restated from scratch instead of added to, so nothing is ever counted twice.
--
-- A repository is named by its remote, as "owner/name". Nothing about the machine travels: no paths,
-- no branch names, no diffs, no file names.
CREATE TABLE daily_work (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day TEXT NOT NULL,
  repo TEXT NOT NULL,
  commits INTEGER NOT NULL,
  insertions INTEGER NOT NULL,
  deletions INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, day, repo)
);

-- Ranking and the team's day both read a date range across everyone.
CREATE INDEX daily_work_day ON daily_work(day);

-- The commit subjects behind those counts, so a day can be read rather than only measured.
--
-- This is the one part of Keyhop that carries words a person wrote, so it is off until it is turned
-- on, the way limit sharing is. Counts sync on their own; subjects only ever arrive from a computer
-- whose owner asked for it, and turning it back off deletes every row here.
--
-- Only the subject line travels, never the body, the diff or the file names.
CREATE TABLE work_commits (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day TEXT NOT NULL,
  repo TEXT NOT NULL,
  -- The abbreviated commit hash. Unique within a day and repository, and meaningless off this row.
  sha TEXT NOT NULL,
  subject TEXT NOT NULL,
  insertions INTEGER NOT NULL,
  deletions INTEGER NOT NULL,
  -- When it was authored, so a day reads in the order it happened.
  at INTEGER NOT NULL,
  -- Seconds east of UTC where it was authored. A day is bucketed in the author's own zone, so the
  -- clock has to be read in that zone too, or a late-evening commit would show as the next morning.
  offset_seconds INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, day, repo, sha)
);

CREATE INDEX work_commits_day ON work_commits(user_id, day);

-- How far a person's computer has got through their repositories.
--
-- A first index walks every clone on a disk, and until it finishes the commit counts are real but
-- partial. Without this, a teammate reading the day would take "4 commits" as the whole story when
-- it is four out of forty repositories, which is worse than saying nothing: it reports someone as
-- having done less than they did.
--
-- One row per person, replaced on every sync, with no history. A row nobody has refreshed for a few
-- hours is ignored, since the app that was indexing has clearly stopped.
CREATE TABLE work_index (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  done INTEGER NOT NULL,
  total INTEGER NOT NULL,
  complete INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
