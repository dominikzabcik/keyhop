-- Team digests: the owner can point a team at a Slack or Discord incoming webhook, and once a day,
-- at the hour they chose in UTC, the team's day is posted there. The URL is the owner's secret for
-- that channel; it is never shown back in full.
ALTER TABLE teams ADD COLUMN digest_url TEXT;
ALTER TABLE teams ADD COLUMN digest_hour INTEGER NOT NULL DEFAULT 17;
