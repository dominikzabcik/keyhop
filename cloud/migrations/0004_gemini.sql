-- Add Gemini CLI to the daily tool totals without changing any existing rows.
PRAGMA defer_foreign_keys = ON;

CREATE TABLE daily_usage_new (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day TEXT NOT NULL,
  tool TEXT NOT NULL CHECK (tool IN ('claude', 'cursor', 'codex', 'gemini')),
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
