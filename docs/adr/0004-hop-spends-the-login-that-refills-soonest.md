# A hop spends the login that refills soonest

Smart Hop used to rank the spare logins by room and offer the biggest runway. From 0.14.x+1 the ordering flips: among logins with room worth hopping for (20% or more on the tightest window), the hop goes to the one whose window turns over soonest; room only decides between equal resets, and logins without a readable reset fall back to their score. Below the useful-room floor the old room ordering still applies, and "keep for last" still waits until nothing else has room.

Why: capacity burned on a login that resets in half an hour comes back in half an hour; the same burn on a login with a 4-hour runway is gone for 4 hours. Routing to the soonest reset keeps the long runways whole, which is what multi-account routers (CLIProxyAPI's reset-aware routing, 2026-10) converged on too. The one case it can look odd — a half-used login picked over a fuller one — is exactly the case where the choice is cheapest.

One ordering feeds every surface: the window's verdict hop, the menu, limit alerts and auto-hop all read `SmartHop.recommendation`.
