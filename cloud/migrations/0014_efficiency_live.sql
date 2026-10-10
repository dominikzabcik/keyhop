-- Efficiency and the live layer.
--
-- cache_read is the part of a day's tokens that came back from a prompt cache, sent by apps that
-- count it; older apps leave it null, and a null never counts as a zero. A person's division is the
-- broadest paid plan among their logins, as the app reads it, so peers on the same plan rank together.
-- live_usage holds today's per-tool totals as the app last sent them, every minute or two. The hourly
-- sweep drops rows nobody has refreshed: this table is never history, daily_usage is.
ALTER TABLE daily_usage ADD COLUMN cache_read INTEGER;
ALTER TABLE users ADD COLUMN division TEXT CHECK (division IN ('free', 'pro', 'max'));

CREATE TABLE live_usage (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  tool TEXT NOT NULL CHECK (tool IN (
    'claude', 'cursor', 'codex', 'gemini', 'opencode', 'pi', 'copilot', 'windsurf', 'codebuff',
    'amp', 'goose', 'qwen', 'kimi', 'grok', 'kilo', 'openclaw'
  )),
  day TEXT NOT NULL,
  tokens INTEGER NOT NULL,
  cost_micros INTEGER NOT NULL,
  requests INTEGER NOT NULL,
  cache_read INTEGER,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, tool)
);
CREATE INDEX live_usage_updated ON live_usage(updated_at);
