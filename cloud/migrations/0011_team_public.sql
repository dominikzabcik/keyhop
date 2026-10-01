-- A published team can be drawn as a README image. Off until the owner turns it on.
-- The image is summed totals and a member count, never a name.

ALTER TABLE teams ADD COLUMN public INTEGER NOT NULL DEFAULT 0;
