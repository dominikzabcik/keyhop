-- A claimed day on the streak. The streak itself is still counted from usage.
-- This row is only the keep someone chose to take, and it goes when the account does.

CREATE TABLE claims (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day TEXT NOT NULL,
  streak INTEGER NOT NULL,
  PRIMARY KEY (user_id, day)
);
