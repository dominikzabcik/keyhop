-- Add Codebuff account limits. Its credit/subscription counters are exact, but its local history
-- does not expose model token counts, so it remains outside MEASURED_TOOLS.
PRAGMA defer_foreign_keys = ON;

CREATE TABLE daily_usage_new (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day TEXT NOT NULL,
  tool TEXT NOT NULL CHECK (tool IN ('claude', 'cursor', 'codex', 'gemini', 'opencode', 'pi', 'copilot', 'windsurf', 'codebuff')),
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

CREATE TABLE account_limits_new (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  account_key TEXT NOT NULL,
  tool TEXT NOT NULL CHECK (tool IN ('claude', 'cursor', 'codex', 'gemini', 'opencode', 'pi', 'copilot', 'windsurf', 'codebuff')),
  label TEXT,
  window_label TEXT NOT NULL,
  used_percent REAL NOT NULL,
  resets_at INTEGER,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, account_key, window_label)
);

INSERT INTO account_limits_new (user_id, account_key, tool, label, window_label, used_percent, resets_at, updated_at)
SELECT user_id, account_key, tool, label, window_label, used_percent, resets_at, updated_at FROM account_limits;

DROP TABLE account_limits;
ALTER TABLE account_limits_new RENAME TO account_limits;
CREATE INDEX account_limits_updated ON account_limits(updated_at);
