-- Editable public profiles. GitHub still supplies `name` and `avatar_url`, and rewrites them at every
-- sign-in, so anything a person edits lives in its own column and is left alone by that refresh.

-- Shown instead of the GitHub name when it is set.
ALTER TABLE users ADD COLUMN display_name TEXT;
-- A short line about themselves, on their public profile.
ALTER TABLE users ADD COLUMN bio TEXT;
-- One link of their choosing. Only http and https are accepted, checked before it is stored.
ALTER TABLE users ADD COLUMN link TEXT;
