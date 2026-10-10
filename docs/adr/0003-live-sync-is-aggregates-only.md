# Live cloud sync sends only short-interval aggregates

V2's live team day and leaderboard are fed by a transient live layer: per-tool usage aggregates uploaded every minute or two, kept with a TTL and never stored durably — D1 keeps holding daily totals only. Event-level data (individual requests, sessions, prompts) never leaves the machine, and a `show-data` command and screen display the exact payload before anything is sent.

Why: privacy transparency is a selling point against other uploaders (ccclub's `show-data` is the benchmark), a finer stream would be a lasting storage and cost commitment on D1, and nothing in the live views needs more than aggregates. This is a boundary decision: richer live features must be built within it, not by widening the payload.
