-- Phone companions can read a person's season without receiving permission to alter usage or profile data.
ALTER TABLE sessions ADD COLUMN access TEXT NOT NULL DEFAULT 'write' CHECK (access IN ('read', 'write'));
ALTER TABLE device_links ADD COLUMN access TEXT NOT NULL DEFAULT 'write' CHECK (access IN ('read', 'write'));
