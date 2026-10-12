# keyhop-native

Keyhop's window drawn natively with [GPUI](https://gpui.rs) through [GPUI Kit](https://gpui-kit.com),
as a spike next to the HTML window. It is one more client of the local API the HTML window reads:
it starts `keyhop dashboard --no-open --json` (or attaches to one with `--url`) and draws the
sidebar (Home, Limits, the logins in use), Home, Limits pooled and projected from `/api/quota`, and the status bar from `/api/state`, with the night and day
tokens of `design/keyhop-v2/index.html`. Hop, Refresh and the field switch call the same
endpoints. The Swift core stays the only code that reads logins, limits and usage.

```sh
cargo run --release -- --sample          # made-up logins
cargo run --release                      # yours, through keyhop dashboard
cargo run --release -- --section limits --theme day
cargo test                               # lanes, best hop, headline, formatting
```

It finds Keyhop through `KEYHOP_BIN`, the binary beside it (inside Keyhop.app), `keyhop` on PATH,
or `/Applications/Keyhop.app`. On Linux it needs the GPUI build dependencies (xkbcommon, wayland,
vulkan, fontconfig). `scripts/build-app.sh` puts it into Keyhop.app when `KEYHOP_NATIVE_BIN`
points at a built binary; the nightly does that on macOS.

Not yet here: the field canvas, Accounts, Usage, Budgets, Plans, Coach, the cloud sections and
Settings, the Hop palette and keyboard navigation. The HTML window keeps all of them.
