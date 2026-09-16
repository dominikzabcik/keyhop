-- Current limit state, so a linked phone can count down to a reset.
--
-- This table holds no history. Each upload replaces everything the computer sent before, and a row
-- is ignored and swept away once it is a day old, so what is here is only ever "where this person
-- stands right now". The label is the one a person typed for an account in Keyhop; emails and
-- account names are never sent.
CREATE TABLE account_limits (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- Opaque per-account key from the computer. Stable across uploads, meaningless off this row.
  account_key TEXT NOT NULL,
  tool TEXT NOT NULL CHECK (tool IN ('claude', 'cursor', 'codex', 'gemini')),
  label TEXT,
  -- The window's own name, as the provider draws it: "5h", "Week", "Auto".
  window_label TEXT NOT NULL,
  used_percent REAL NOT NULL,
  resets_at INTEGER,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, account_key, window_label)
);
