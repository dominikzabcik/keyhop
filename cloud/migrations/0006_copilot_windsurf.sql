-- Add GitHub Copilot and Windsurf to the tools a row may name, without changing any existing rows.
--
-- Both tables carry a CHECK on `tool`, and SQLite cannot widen one in place, so each is rebuilt the
-- way 0004 added Gemini. account_limits holds only current state, so it is simply recreated.
PRAGMA defer_foreign_keys = ON;

CREATE TABLE daily_usage_new (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day TEXT NOT NULL,
  tool TEXT NOT NULL CHECK (tool IN ('claude', 'cursor', 'codex', 'gemini', 'copilot', 'windsurf')),
  tokens INTEGER NOT NULL,
  cost_micros INTEGER NOT NULL,
  requests INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, day, tool)
);

INSERT INTO daily_usage_new (user_id, day, tool, tokens, cost_micros, requests, updated_at)
SELECT user_id, day, tool, tokens, cost_micros, requests, updated_at FROM daily_usage;

DROP TABLE daily_usage;
ALTER TABLE daily_usage_new RENAME TO daily_usage;
CREATE INDEX daily_usage_day ON daily_usage(day);

DROP TABLE account_limits;
CREATE TABLE account_limits (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  account_key TEXT NOT NULL,
  tool TEXT NOT NULL CHECK (tool IN ('claude', 'cursor', 'codex', 'gemini', 'copilot', 'windsurf')),
  label TEXT,
  window_label TEXT NOT NULL,
  used_percent REAL NOT NULL,
  resets_at INTEGER,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, account_key, window_label)
);
