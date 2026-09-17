-- The hourly sweep deletes readings by age, so it needs to find them without scanning every row.
CREATE INDEX account_limits_updated ON account_limits(updated_at);
