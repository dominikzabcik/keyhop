import Foundation

/// The window's stylesheet: the Keyhop 2.0 world. One warm charcoal ramp, color is state only,
/// paper-on-ink actions, mono for figures, brand blue only in the K mark and the focus ring.
extension DashboardPage {
    static let styles = ##"""
:root {
  /* The ramp: chrome below ground below surface below hover below track. Depth is tonal, never shadowed. */
  --g0: #0c0b0a; --chrome: #090807; --g1: #121110; --g2: #181613; --g3: #201d19;
  --line: rgba(255, 250, 240, .06); --line-strong: rgba(255, 250, 240, .11);
  --fg: #eceae5; --fg2: #a8a49b; --fg3: #8b8780;
  --ok: #4fae72; --low: #d9a03a; --out: #e05746;
  --out-wash: rgba(224, 87, 70, .06); --ok-wash: rgba(79, 174, 114, .08);
  --brand: #2f5fd9;
  /* The same world under the names the section sheets read. */
  --bg: var(--g0); --panel: var(--g1); --raised: var(--g2); --hover: var(--g2);
  --border: var(--line); --border-strong: var(--line-strong);
  --text: var(--fg); --muted: var(--fg2); --subtle: var(--fg3); --faint: var(--g3);
  --primary: var(--fg); --on-primary: #121110; --focus: var(--brand);
  --good: var(--ok); --warn: var(--low); --warn-ink: var(--low); --bad: var(--out); --red: var(--out); --info: var(--fg2);
  --on: 43 100% 97%; --off: 30 14% 3%;
  --bg-base: 30 9% 4%;
  --overlay: #181613; --scrim: rgba(0, 0, 0, .55);
  --sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", system-ui, sans-serif;
  --mono: ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, monospace;
  color-scheme: dark;
  view-transition-name: none;
}

* { box-sizing: border-box; }
html, body { height: 100%; }
body {
  margin: 0;
  background: var(--g0);
  color: var(--fg);
  font: 400 13px/1.45 var(--sans);
  -webkit-font-smoothing: antialiased;
  overflow: hidden;
}
button, input, select { font: inherit; color: inherit; }
button, a, input, select, summary { touch-action: manipulation; -webkit-tap-highlight-color: transparent; }
[hidden] { display: none !important; }
::selection { background: rgba(47, 95, 217, .35); color: var(--fg); }
::-webkit-scrollbar { width: 8px; height: 8px; }
::-webkit-scrollbar-thumb { background: hsl(var(--on) / .12); border-radius: 99px; border: 2px solid transparent; background-clip: padding-box; }
::-webkit-scrollbar-track { background: transparent; }
:focus-visible { outline: 2px solid var(--brand); outline-offset: 2px; border-radius: 5px; }
.mono { font-family: var(--mono); font-size: 12px; }
.mark { width: 16px; height: 16px; flex: none; fill: currentColor; }
.nowrap { white-space: nowrap; }
.muted { color: var(--fg2); }
.subtle { color: var(--fg3); }
.num { font-variant-numeric: tabular-nums; white-space: nowrap; }
[data-count], .mono, .table td, .ranked-share, .tile-foot, .limit-top b, .quest-state { font-variant-numeric: tabular-nums; }
.up { color: var(--ok); }
.down { color: var(--out); }
.icon { width: 15px; height: 15px; flex: none; fill: none; stroke: currentColor; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; }
.skip-link { position: fixed; left: 12px; top: 12px; z-index: 100; padding: 8px 11px; border: 0; border-radius: 5px; background: var(--fg); color: var(--g1); font-weight: 600; cursor: pointer; transform: translateY(calc(-100% - 18px)); transition: transform .14s ease-out; }
.skip-link:focus-visible { transform: translateY(0); }
.sr-only { position: absolute; width: 1px; height: 1px; margin: -1px; padding: 0; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }

/* Shell: title bar on chrome, an optional view bar for the demoted views, then the work surface. */
.shell { display: flex; flex-direction: column; height: 100vh; }
.titlebar {
  position: relative; flex: none; display: flex; align-items: center; gap: 12px;
  height: 44px; padding: 0 12px 0 18px;
  background: var(--chrome);
  border-bottom: 1px solid var(--line);
}
.mac-window .titlebar { padding-left: 86px; -webkit-user-select: none; user-select: none; cursor: default; }
.app { display: flex; align-items: center; gap: 8px; font-weight: 600; }
/* The mark, bare on the chrome: paper K, the hopped arm in the one blue. */
.kmark { width: 17px; height: 17px; color: var(--fg); flex: none; display: block; }
.titlebar .right { margin-left: auto; display: flex; align-items: center; gap: 10px; }
.readtime { color: var(--fg3); font-size: 12px; font-variant-numeric: tabular-nums; white-space: nowrap; }
.readtime.stale { color: var(--low); }
.iconbtn {
  width: 28px; height: 28px; border: 0; border-radius: 5px; display: grid; place-items: center;
  background: none; color: var(--fg2); cursor: pointer;
  transition: background .15s ease-out, color .15s ease-out;
}
.iconbtn:hover { background: var(--g2); color: var(--fg); }
.iconbtn:disabled { opacity: .45; cursor: default; }
.iconbtn.spin .icon { animation: turn 1s linear infinite; }
.iconbtn[aria-current="page"] { color: var(--fg); background: var(--g2); }
@keyframes turn { to { transform: rotate(360deg); } }
/* The window's progress, along the bottom edge of the title bar. */
.titlebar .meter { position: absolute; left: 0; right: 0; bottom: -1px; height: 2px; background: transparent; opacity: 0; transition: opacity .25s ease-out; }
.titlebar .meter.on { opacity: 1; }
.meter { position: relative; height: 4px; border-radius: 99px; background: var(--g3); overflow: hidden; }
.meter > span { position: absolute; left: 0; top: 0; bottom: 0; width: 0; border-radius: inherit; background: var(--fg); transition: width .35s ease-out; }
.meter.unknown > span { width: 28%; animation: travel 1.3s ease-in-out infinite; }
@keyframes travel { from { left: -28%; } to { left: 100%; } }

/* The view bar: the way back to the core, the view's name, its sections, then its controls. */
.viewbar {
  flex: none; display: flex; align-items: center; gap: 12px;
  min-height: 44px; padding: 6px 16px;
  border-bottom: 1px solid var(--line);
}
.viewbar .back { flex: none; }
.viewbar .back .icon { transform: rotate(180deg); }
.viewbar h1 { margin: 0; font-size: 13px; font-weight: 600; letter-spacing: -.01em; white-space: nowrap; }
.viewbar .toolbar { margin-left: auto; display: flex; align-items: center; gap: 8px; justify-content: flex-end; min-width: 0; overflow-x: auto; scrollbar-width: none; padding: 2px; }
.viewbar .toolbar::-webkit-scrollbar { display: none; }
.viewbar .toolbar:has(.range-menu) { overflow: visible; }

.main { position: relative; flex: 1; overflow: auto; min-height: 0; }
.main:has(.page) { padding: 20px 24px 28px; }
.page { max-width: 1320px; margin: 0 auto; display: grid; gap: 14px; }

/* MARK: The core screen
   The window is the sheet: verdict, ranked login rows, today, straight on the surface and
   parted by hairlines. No card inside the window. */
.main:has(.core) { display: flex; flex-direction: column; padding: 0; }
.main:has(.core) > .page { width: 100%; max-width: none; margin: 0; padding: 16px 24px 0; }
.core { flex: 1; display: flex; flex-direction: column; }
.core .logins, .core .setup-list { flex: 1; }
.verdict {
  display: flex; align-items: center; gap: 16px;
  padding: 20px 24px; border-bottom: 1px solid var(--line);
}
.verdict p { margin: 0 auto 0 0; font-size: 15px; font-weight: 500; letter-spacing: -.01em; min-width: 0; view-transition-name: verdict; }
.verdict p .detail { color: var(--fg2); font-weight: 400; }

.logins { list-style: none; margin: 0; padding: 0; }
.core .row {
  display: grid;
  grid-template-areas: "dot tool login runway left";
  grid-template-columns: 8px 112px 220px minmax(0, 1fr) 190px;
  gap: 14px; align-items: center;
  height: 47px; padding: 0 24px;
  border-bottom: 1px solid var(--line);
  transition: background .15s ease-out;
}
.core .row:hover { background: var(--g2); }
.core .row.crit { background: var(--out-wash); }
.core .row.crit:hover { background: rgba(224, 87, 70, .1); }
.core .row.hopped { background: var(--ok-wash); }
.core .dot { grid-area: dot; width: 7px; height: 7px; border-radius: 50%; background: var(--ok); justify-self: center; }
.core .row.crit .dot { background: var(--out); }
.core .row.low .dot { background: var(--low); }
.core .row.idle .dot { background: var(--g3); }
.core .tool { grid-area: tool; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.core .login { grid-area: login; color: var(--fg2); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.core .login .flag {
  font-style: normal; font-size: 11px; color: var(--fg3);
  border: 1px solid var(--line-strong); border-radius: 5px;
  padding: 1.5px 6px; margin-left: 7px; white-space: nowrap;
}
.runway { grid-area: runway; height: 4px; border-radius: 99px; background: var(--g3); overflow: hidden; }
.runway i { display: block; height: 100%; border-radius: 99px; background: var(--ok); transition: width .2s ease-out; }
.core .row.crit .runway i { background: var(--out); }
.core .row.low .runway i { background: var(--low); }
.core .row.idle .runway { background: none; }
.core .left {
  grid-area: left; text-align: right; color: var(--fg2);
  font: 500 12px/1 var(--mono); font-variant-numeric: tabular-nums; white-space: nowrap;
}
.core .row.crit .left { color: var(--out); font-weight: 600; }
.core .row.idle .left, .core .row.idle .login { color: var(--fg3); }
.core .row .pulse i { background: var(--fg3); }

/* Today: the same grid as the rows, a step below the work surface. */
.core .today {
  display: grid;
  grid-template-columns: 8px 112px 220px minmax(0, 1fr) 190px;
  gap: 6px 14px; align-items: end;
  padding: 16px 24px 14px;
  background: var(--chrome);
}
.core .figure { grid-column: 1 / 4; align-self: start; min-width: 0; }
.core .figure .num { font: 600 20px/1.2 var(--mono); font-variant-numeric: tabular-nums; letter-spacing: -.02em; }
.core .figure .num .val { color: var(--fg2); font-weight: 500; }
.core .figure .sub { margin-top: 4px; color: var(--fg3); font-size: 12px; }
.core .shares { grid-column: 4 / 6; min-width: 0; }
.sharebar { display: flex; gap: 2px; height: 2px; border-radius: 99px; overflow: hidden; }
.sharebar i { height: 100%; }
.sharebar i:nth-child(1), .sharekey .ki:nth-child(1) i { background: #cfcbc3; }
.sharebar i:nth-child(2), .sharekey .ki:nth-child(2) i { background: #a39f97; }
.sharebar i:nth-child(3), .sharekey .ki:nth-child(3) i { background: #827d74; }
.sharebar i:nth-child(4), .sharekey .ki:nth-child(4) i { background: #666258; }
.sharebar i:nth-child(5), .sharekey .ki:nth-child(5) i { background: #4e4a42; }
.sharebar i:nth-child(6), .sharekey .ki:nth-child(6) i { background: #3a3731; }
.sharekey { margin-top: 9px; display: flex; flex-wrap: wrap; gap: 5px 14px; color: var(--fg3); font-size: 11.5px; }
.sharekey .ki { display: inline-flex; align-items: center; gap: 6px; white-space: nowrap; }
.sharekey .ki i { width: 8px; height: 8px; border-radius: 2px; flex: none; }
.sharekey .ki b { color: var(--fg2); font-weight: 500; }
.core .links { grid-column: 1 / 6; display: flex; gap: 16px; justify-content: flex-end; margin-top: 6px; }
.core .links a { color: var(--fg3); font-size: 12px; text-decoration: none; transition: color .15s ease-out; }
.core .links a:hover { color: var(--fg); }
.setup-mark { flex: none; width: 24px; height: 24px; display: grid; place-items: center; color: var(--fg2); }
.setup-mark .mark { width: 15px; height: 15px; }

/* MARK: Components */

.card { background: var(--g1); border: 1px solid var(--line); border-radius: 8px; min-width: 0; }
.card-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 14px 20px 6px; min-height: 0; flex-wrap: wrap; }
.card-head h2 { margin: 0; font-size: 13px; font-weight: 600; letter-spacing: -.01em; display: flex; align-items: center; gap: 8px; color: var(--fg); }
.lab { font-size: 12px; font-weight: 500; color: var(--fg3); }
.card-head .hint { color: var(--fg3); font-size: 12px; display: inline-flex; align-items: center; gap: 14px; }
.card-head .hint b { color: var(--fg); font-weight: 600; }
.card-head .tabs { margin-left: auto; }
.card-body { padding: 12px 20px 16px; }
.card-head .count {
  display: inline-grid; place-items: center; min-width: 20px; height: 20px; padding: 0 6px; border-radius: 5px;
  background: hsl(var(--on) / .08); color: var(--fg2); font: 600 11px var(--sans); font-variant-numeric: tabular-nums;
}
.card-head .count.hot { background: var(--out-wash); color: var(--out); }
.split { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }
.split.wide-left { grid-template-columns: minmax(0, 1.55fr) minmax(0, 1fr); }
.stats { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 14px; }
.stats.three { grid-template-columns: repeat(3, minmax(0, 1fr)); }
.stat { padding: 14px 16px 16px; }
.stat .label { color: var(--fg2); font-size: 12.5px; display: flex; justify-content: space-between; gap: 8px; }
.stat .value { margin-top: 6px; font-size: 24px; font-weight: 600; letter-spacing: -.02em; line-height: 1.2; font-variant-numeric: tabular-nums; }
.stat .foot { margin-top: 4px; font-size: 12px; color: var(--fg3); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

/* Paper on ink: the primary is the ink itself; nothing is filled with an accent. */
.btn {
  display: inline-flex; align-items: center; justify-content: center; gap: 7px; height: 32px; padding: 0 14px;
  border-radius: 5px; border: 1px solid transparent; cursor: pointer; font-weight: 600; font-size: 13px; white-space: nowrap;
  background: var(--fg); color: #121110; transition: background .15s ease-out, border-color .15s ease-out, color .15s ease-out;
}
.btn:hover { background: #fffdf8; }
.btn.secondary { background: var(--g2); color: var(--fg); border-color: var(--line); }
.btn.secondary:hover { background: var(--g3); border-color: var(--line-strong); }
.btn.ghost { background: transparent; color: var(--fg2); border-color: var(--line-strong); }
.btn.ghost:hover { background: var(--g2); color: var(--fg); }
.btn.quiet { background: hsl(var(--on) / .07); color: var(--fg); }
.btn.quiet:hover { background: hsl(var(--on) / .12); }
.btn.danger:hover { color: var(--out); }
.btn.sm { height: 28px; padding: 0 10px; font-size: 12.5px; }
.btn:disabled { opacity: .45; cursor: default; }
.btn:active:not(:disabled), .tabs button:active, button.tile:active { transform: scale(.98); }
.btn, button.tile { transition-property: background, border-color, color, transform; transition-duration: .15s, .15s, .15s, .1s; }
a.btn { text-decoration: none; }
.btn.icon-only { width: 28px; padding: 0; }
.btn.icon-only .icon { width: 16px; height: 16px; }
.btn.working { cursor: progress; }
.btn.working:disabled { opacity: 1; }
.btn .ring { width: 12px; height: 12px; flex: none; border-radius: 50%; border: 1.6px solid currentColor; border-right-color: transparent; animation: turn .8s linear infinite; }
.main p a:not(.btn) { color: var(--fg); text-underline-offset: 3px; }

.badge {
  display: inline-flex; align-items: center; gap: 5px; height: 20px; padding: 0 8px; border-radius: 5px;
  background: hsl(var(--on) / .07); color: var(--fg2); font-size: 11.5px; font-weight: 560; white-space: nowrap;
}
.badge.live { color: var(--ok); background: var(--ok-wash); }
.badge.sample { color: var(--low); background: rgba(217, 160, 58, .1); }
.pill { display: inline-flex; align-items: center; height: 22px; padding: 0 8px; border-radius: 5px; background: hsl(var(--on) / .07); color: var(--fg2); font-size: 11.5px; font-weight: 560; white-space: nowrap; }
.pill.bad { color: var(--out); background: var(--out-wash); }
.pill.warn { color: var(--low); background: rgba(217, 160, 58, .12); }
.pill.good { color: var(--ok); background: var(--ok-wash); }
kbd { display: inline-grid; place-items: center; min-width: 20px; height: 20px; padding: 0 5px; border-radius: 5px; background: hsl(var(--on) / .07); box-shadow: inset 0 -1.5px 0 hsl(var(--on) / .09); color: var(--fg2); font: 600 11px var(--sans); }

.tabs { position: relative; isolation: isolate; display: inline-flex; padding: 3px; gap: 2px; border-radius: 5px; background: var(--g1); border: 1px solid var(--line); }
.viewbar .tabs, .card .tabs { background: var(--chrome); }
.tabs.has-thumb::before { content: ""; position: absolute; z-index: -1; top: 3px; bottom: 3px; left: 0; width: var(--thumb-w); transform: translateX(var(--thumb-x)); border-radius: 3px; background: hsl(var(--on) / .09); transition: transform .2s ease-out, width .2s ease-out; }
.tabs.no-slide::before { transition: none; }
.tabs.has-thumb button[aria-pressed="true"] { background: transparent; }
.tabs button { height: 26px; padding: 0 12px; border: 0; border-radius: 3px; background: transparent; color: var(--fg2); cursor: pointer; font-size: 12px; font-weight: 500; transition: color .18s ease-out; }
.tabs button:hover { color: var(--fg); }
.tabs button[aria-pressed="true"] { background: hsl(var(--on) / .09); color: var(--fg); font-weight: 600; }
.tabs button:disabled { opacity: .4; cursor: default; }

.field {
  height: 32px; width: 100%; padding: 0 10px; border-radius: 5px; border: 1px solid var(--line-strong);
  background: transparent; color: var(--fg); transition: border-color .15s ease-out;
}
.field:hover { border-color: hsl(var(--on) / .22); }
.field::placeholder { color: var(--fg3); }
select.field { appearance: none; padding-right: 28px; background-image: linear-gradient(45deg, transparent 50%, var(--fg2) 50%), linear-gradient(135deg, var(--fg2) 50%, transparent 50%); background-position: calc(100% - 15px) 14px, calc(100% - 11px) 14px; background-size: 4px 4px; background-repeat: no-repeat; }
select.field option { background: var(--g2); }
.toolbar select.field { width: auto; height: 30px; }
.range { width: 180px; accent-color: var(--fg); }
.range-pick { position: relative; }
.range-button { display: inline-flex; align-items: center; gap: 8px; height: 30px; padding: 0 10px 0 12px; border-radius: 5px; border: 1px solid var(--line-strong); background: transparent; color: var(--fg); font: inherit; font-size: 12.5px; font-weight: 560; cursor: pointer; white-space: nowrap; }
.range-button:hover { background: var(--g2); }
.range-button svg { width: 10px; height: 10px; color: var(--fg2); transition: transform .16s ease-out; }
.range-button[aria-expanded="true"] svg { transform: rotate(180deg); }
.range-menu { position: absolute; top: calc(100% + 6px); right: 0; z-index: 30; width: 268px; padding: 6px; border-radius: 8px; border: 1px solid var(--line-strong); background: var(--g2); }
.range-list { display: grid; grid-template-columns: 1fr 1fr; gap: 2px; }
.range-list button { height: 30px; padding: 0 10px; border: 0; border-radius: 5px; background: transparent; color: var(--fg2); font: inherit; font-size: 12.5px; text-align: left; cursor: pointer; }
.range-list button:hover { color: var(--fg); background: hsl(var(--on) / .05); }
.range-list button[aria-checked="true"] { color: var(--fg); background: hsl(var(--on) / .1); font-weight: 560; }
.range-dates { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 6px; padding: 10px 4px 4px; border-top: 1px solid var(--line); }
.range-dates label { display: grid; gap: 4px; font-size: 11.5px; color: var(--fg2); }
.range-dates .field { height: 30px; padding: 0 8px; font-size: 12.5px; }
.range-dates .btn { grid-column: 1 / -1; justify-content: center; }

/* A limit reads by how full it is: amber from 75%, red from 90%. */
.progress { position: relative; height: 4px; border-radius: 99px; background: var(--g3); overflow: visible; }
.progress > span { position: absolute; left: 0; top: 0; bottom: 0; border-radius: inherit; background: hsl(var(--on) / .78); transition: width .5s ease-out; }
.progress.warn > span { background: var(--low); }
.progress.bad > span { background: var(--out); }
.progress > i { position: absolute; top: -3px; bottom: -3px; width: 2px; margin-left: -1px; border-radius: 1px; background: hsl(var(--on) / .45); }

.list > .row { padding: 14px 20px; }
.list > .row + .row { border-top: 1px solid var(--line); }
.empty { padding: 18px 20px; color: var(--fg2); }
.empty-inline { color: var(--fg2); margin: 0; }
.lede { margin: 0 0 4px; color: var(--fg2); }

.notice { display: flex; align-items: center; gap: 12px; padding: 12px 14px; border: 1px solid rgba(217, 160, 58, .28); background: rgba(217, 160, 58, .06); border-radius: 8px; }
.notice .icon { color: var(--low); }
.notice div { flex: 1; min-width: 0; }
.notice b { font-weight: 600; }
.notice p { margin: 0; color: var(--fg2); }
.warn-text { color: var(--low); }
.notices { display: grid; border-radius: 8px; border: 1px solid rgba(217, 160, 58, .24); background: rgba(217, 160, 58, .05); }
.notice-row { display: flex; align-items: center; gap: 12px; padding: 12px 14px; }
.notice-row + .notice-row { border-top: 1px solid rgba(217, 160, 58, .12); }
.notice-row > .icon { color: var(--low); }
.notice-row > div { flex: 1; min-width: 0; }
.notice-row b { font-weight: 600; }
.notice-row p { margin: 0; color: var(--fg2); }

.menu-anchor { position: relative; display: inline-flex; }
.row-menu { position: absolute; right: 0; top: calc(100% + 6px); z-index: 20; min-width: 190px; padding: 5px; display: grid; gap: 2px; border-radius: 8px; border: 1px solid var(--line-strong); background: var(--g2); animation: menu-in .14s ease-out; }
.row-menu button { height: 30px; padding: 0 10px; border: 0; border-radius: 5px; background: transparent; color: var(--fg); font: inherit; font-size: 13px; text-align: left; cursor: pointer; }
.row-menu button:hover { background: hsl(var(--on) / .06); }
.row-menu button.danger { color: var(--out); }
@keyframes menu-in { from { opacity: 0; transform: translateY(-4px); } }

.rename { display: flex; gap: 8px; align-items: center; }
.rename .field { max-width: 260px; }
.waiting { display: flex; align-items: center; gap: 12px; color: var(--fg2); }
.waiting small { color: var(--fg3); font-size: 12px; }
.waiting-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.pulse { display: inline-flex; gap: 3px; }
.pulse i { width: 5px; height: 5px; border-radius: 50%; background: var(--fg); opacity: .25; animation: pulse 1.2s ease-in-out infinite; }
.pulse i:nth-child(2) { animation-delay: .15s; } .pulse i:nth-child(3) { animation-delay: .3s; }
@keyframes pulse { 40% { opacity: 1; } }
.busy { display: flex; align-items: center; gap: 10px; }
.loading { display: grid; gap: 10px; max-width: 420px; }
.loading .busy { margin: 0; }
.loading .busy b { font-weight: 560; color: var(--fg); }
.loading .count { margin-left: auto; font-variant-numeric: tabular-nums; color: var(--fg2); }
.loading small { color: var(--fg3); font-size: 12px; }
.busy-note { margin: 2px 0 0; color: var(--fg2); }
.skel { display: block; border-radius: 5px; background: hsl(var(--on) / .07); }
@media (prefers-reduced-motion: no-preference) { .skel { animation: skel 1.4s ease-in-out infinite; } }
@keyframes skel { 50% { background: hsl(var(--on) / .12); } }
.skel-card { display: grid; gap: 14px; padding: 20px; }

.who { display: flex; align-items: center; gap: 12px; min-width: 0; }
.who .mark { width: 18px; height: 18px; fill: var(--fg); flex: none; }
.who div { min-width: 0; }
.who b { display: block; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.who small { display: block; color: var(--fg3); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.row-actions { display: flex; gap: 6px; justify-content: flex-end; flex-wrap: wrap; }
.problem { color: var(--out); font-size: 12.5px; margin: 0; }
.account-id { display: flex; align-items: flex-start; gap: 10px; min-width: 0; }
.account-copy { min-width: 0; }
.account-name { display: flex; align-items: center; gap: 8px; min-width: 0; }
.account-name b { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.account-line { margin-top: 1px; color: var(--fg2); font-size: 12.5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.in-use { display: inline-flex; align-items: center; flex: none; height: 20px; padding: 0 8px; border-radius: 5px; background: hsl(var(--on) / .1); color: var(--fg); font-size: 11.5px; font-weight: 600; }
.setup-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
details.setup summary { display: flex; align-items: center; gap: 10px; padding: 14px 16px; cursor: pointer; list-style: none; font-weight: 560; }
details.setup summary::-webkit-details-marker { display: none; }
details.setup summary .subtle { font-weight: 450; font-size: 12.5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0; }
details.setup[open] summary { border-bottom: 1px solid var(--line); }
.unset-row { display: grid; grid-template-columns: auto 1fr auto; align-items: center; gap: 14px; }
.unset-row p { margin: 0; }
.unset-marks { display: flex; gap: 6px; opacity: .55; }
.unset-marks .mark { width: 14px; height: 14px; }
.tile-mark { flex: none; width: 24px; height: 24px; display: grid; place-items: center; color: var(--fg); }
.tile-mark .mark { width: 15px; height: 15px; }
.avatar { display: inline-grid; place-items: center; flex: none; border-radius: 50%; background: var(--g2); color: var(--fg2); font-weight: 600; }

/* MARK: Data vis */
.legend { display: flex; flex-wrap: wrap; gap: 4px 14px; list-style: none; margin: 0; padding: 0; font-size: 12px; color: var(--fg2); }
.legend li { display: flex; align-items: center; }
.legend-item { display: inline-flex; align-items: center; gap: 6px; padding: 2px 6px; margin: -2px -6px; border: 0; border-radius: 5px; background: transparent; color: inherit; font: inherit; cursor: pointer; transition: color .15s ease-out, opacity .15s ease-out; }
.legend-item:hover { color: var(--fg); }
.legend-item[aria-pressed="false"] { opacity: .45; }
.legend-item[aria-pressed="false"] .swatch { background: transparent !important; box-shadow: inset 0 0 0 1.5px var(--fg3); }
.swatch { width: 8px; height: 8px; border-radius: 2px; flex: none; }
.chart { overflow-x: auto; }
.chart svg { display: block; }
.chart .grid { stroke: hsl(var(--on) / .06); }
.chart .base { stroke: hsl(var(--on) / .16); }
.chart .axis { fill: var(--fg3); font: 11px var(--mono); }
.chart .hit { fill: transparent; }
.chart .hit:hover { fill: hsl(var(--on) / .03); }
.chart .col { transition: opacity .18s ease-out; }
.chart svg[data-hover] .col { opacity: .4; }
.chart svg[data-hover] .col.on { opacity: 1; }
.heat rect[data-action] { cursor: pointer; }
.heat rect[data-action]:hover { stroke: hsl(var(--on) / .7); stroke-width: 1.2; }
::view-transition-group(usage-chart) { animation-duration: .2s; }
.heat text { fill: var(--fg3); font: 10.5px var(--mono); }
svg.heat { display: block; }
.scale { display: inline-flex; align-items: center; gap: 3px; font-size: 11.5px; color: var(--fg3); }
.scale i { width: 10px; height: 10px; border-radius: 2px; }
.facts { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); border-top: 1px solid var(--line); }
.facts div { padding: 12px 16px; }
.facts div + div { border-left: 1px solid var(--line); }
.facts b { display: block; font-size: 18px; font-weight: 600; letter-spacing: -.01em; font-variant-numeric: tabular-nums; }
.facts span { color: var(--fg3); font-size: 12px; }
.mix-bar { display: flex; gap: 2px; height: 8px; border-radius: 99px; overflow: hidden; margin-bottom: 16px; }
.mix-bar span { min-width: 2px; }
.m1 { background: hsl(var(--on) / .9); } .m2 { background: hsl(var(--on) / .55); } .m3 { background: hsl(var(--on) / .3); } .m4 { background: hsl(var(--on) / .18); }
.m5 { background: hsl(var(--on) / .1); }
.table { width: 100%; border-collapse: collapse; }
.table th { text-align: left; font-weight: 500; color: var(--fg3); font-size: 12px; padding: 10px 16px; border-bottom: 1px solid var(--line); }
.table td { padding: 10px 16px; border-bottom: 1px solid hsl(var(--on) / .045); vertical-align: middle; font-variant-numeric: tabular-nums; }
.table tr:last-child td { border-bottom: 0; }
.table tbody tr:hover td { background: hsl(var(--on) / .02); }
.table tbody tr.clickable { cursor: pointer; }
.table .right { text-align: right; }
.table .bar-cell { width: 34%; }
.table .strong { color: var(--fg); font-weight: 600; }
.table td.mono { color: var(--fg2); }
.table td.mono.strong { color: var(--fg); }
.cell-name { display: flex; align-items: center; gap: 8px; min-width: 0; }
.cell-name span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.place-cell { width: 36px; text-align: center; }
.table-more { display: flex; justify-content: center; padding: 10px; border-top: 1px solid hsl(var(--on) / .045); }
.spark { width: 64px; height: 24px; flex: none; overflow: visible; }

/* MARK: Motion between views */
.main { view-transition-name: main-view; }
::view-transition-old(main-view) { animation: page-out .12s ease-out both; }
::view-transition-new(main-view) { animation: page-in .2s ease-out both; }
@keyframes page-out { to { opacity: 0; } }
@keyframes page-in { from { opacity: 0; } }

/* MARK: Overlays */
.tip {
  position: fixed; z-index: 20; pointer-events: none; min-width: 190px; max-width: 320px; padding: 10px 12px;
  background: var(--g2); border: 1px solid var(--line-strong); border-radius: 5px; font-size: 12px;
}
.tip b { display: block; font-weight: 600; margin-bottom: 6px; }
.tip div { display: grid; grid-template-columns: 10px minmax(0, 1fr) auto; gap: 8px; align-items: center; margin-top: 3px; }
.tip div span:nth-child(2) { color: var(--fg2); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.toast {
  position: fixed; right: 20px; bottom: 24px; z-index: 30; max-width: min(460px, calc(100vw - 40px)); padding: 12px 14px;
  background: var(--g2); border: 1px solid var(--line-strong); border-radius: 8px; font-size: 13px;
  transition: transform .2s ease-out, opacity .2s ease-out;
}
.toast.away { transform: translateY(12px); opacity: 0; pointer-events: none; }
.toast.error { border-color: rgba(224, 87, 70, .45); }
.toast.rich { display: flex; align-items: center; gap: 12px; padding: 12px 14px; }
.toast-check { flex: none; width: 24px; height: 24px; border-radius: 5px; display: grid; place-items: center; background: var(--ok-wash); color: var(--ok); }
.toast-check .icon { width: 13px; height: 13px; stroke-width: 2; }
.toast-copy { flex: 1; min-width: 0; display: grid; line-height: 17px; }
.toast-copy b { font-weight: 600; }
.toast-copy small { color: var(--fg2); font-size: 12px; }

/* MARK: Settings shell */
.form { display: grid; gap: 14px; padding: 16px 20px 20px; }
.form label { display: grid; gap: 6px; font-size: 12.5px; color: var(--fg2); font-weight: 520; }
.form .pair { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
.form > .btn, .form .row-actions { justify-self: start; }
.budget-row { display: grid; gap: 8px; }
.budget-top { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; }
.budget-top b { font-weight: 600; }
.kv { display: grid; grid-template-columns: 150px minmax(0, 1fr); gap: 16px; align-items: baseline; }
.kv > span:first-child { color: var(--fg2); }
.kv .mono { overflow-wrap: anywhere; }
.setting-row { display: flex; align-items: center; justify-content: space-between; gap: 16px; }
.setting-row b { font-weight: 600; }
.setting-row p { margin: 2px 0 0; color: var(--fg2); font-size: 12.5px; }
.settings-shell { display: grid; grid-template-columns: 180px minmax(0, 1fr); gap: 14px; align-items: start; }
.settings-nav { position: sticky; top: 0; display: grid; gap: 3px; padding: 6px; }
.settings-nav button { display: flex; align-items: center; gap: 9px; width: 100%; height: 34px; padding: 0 10px; border: 0; border-radius: 5px; background: transparent; color: var(--fg2); text-align: left; cursor: pointer; transition: background .15s ease-out, color .15s ease-out; }
.settings-nav button:hover { background: var(--g2); color: var(--fg); }
.settings-nav button[aria-current="page"] { background: hsl(var(--on) / .07); color: var(--fg); font-weight: 560; }
.settings-pane { display: grid; gap: 14px; min-width: 0; }
.settings-intro { padding: 4px 2px 0; }
.settings-intro h2 { margin: 0; font-size: 17px; font-weight: 600; letter-spacing: -.01em; }
.settings-intro p { max-width: 62ch; margin: 4px 0 0; color: var(--fg2); font-size: 13px; }
.update-status { display: inline-flex; align-items: center; gap: 8px; color: var(--fg2); }
.update-status .ring { width: 12px; height: 12px; border: 1.5px solid currentColor; border-right-color: transparent; border-radius: 50%; animation: turn .8s linear infinite; }
.outbound { border-top: 1px solid var(--line); }
.outbound summary { display: flex; gap: 12px; align-items: center; padding: 10px 0; cursor: pointer; list-style: none; }
.outbound summary::-webkit-details-marker { display: none; }
.outbound summary .subtle { font-size: 12.5px; }
.outbound pre { margin: 0 0 12px; max-height: 320px; overflow: auto; padding: 10px 12px; border-radius: 5px; background: hsl(var(--on) / .04); font-size: 11.5px; line-height: 1.45; white-space: pre-wrap; overflow-wrap: anywhere; }
.plain-link { color: inherit; text-decoration: none; }
.plain-link:hover { text-decoration: underline; text-underline-offset: 3px; }
.live-dot { display: inline-block; width: 6px; height: 6px; margin-right: 5px; border-radius: 50%; background: var(--ok); vertical-align: 1px; }

/* Keyhop's pet, where the cloud shows it. */
.pet-card { display: flex; align-items: center; gap: 8px 22px; padding: 12px 20px 12px 8px; }
.pet-card .pet { width: 104px; height: auto; flex: none; }
@media (prefers-reduced-motion: no-preference) {
  .pet { animation: pet-live 2.8s ease-in-out infinite; transform-box: fill-box; transform-origin: center 80%; }
}
@keyframes pet-live { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-3px); } }
.pet rect.flame { animation: pet-flame 1.1s steps(2, end) infinite; }
.pet rect.shine { animation: pet-blink 3.6s steps(1, end) infinite; }
@keyframes pet-flame { 50% { opacity: .45; } }
@keyframes pet-blink { 0%, 88%, 100% { opacity: 1; } 92%, 96% { opacity: 0; } }
.pet-card h2 { margin: 0; font-size: 20px; font-weight: 600; letter-spacing: -.02em; }
.pet-card p { margin: 6px 0 0; color: var(--fg2); font-size: 13px; max-width: 62ch; }
.pet-slot { display: flex; align-items: center; justify-content: space-between; gap: 16px; padding: 16px 20px; }
.pet-slot p { margin: 4px 0 0; color: var(--fg2); font-size: 13px; }
.btn.claim-kick { height: 32px; padding: 0 14px; font-size: 13px; font-weight: 600; }
.card-body .btn.claim-kick { width: auto; }

/* MARK: Responsive */
@media (max-width: 640px) {
  .core .row {
    grid-template-areas: "dot tool left" "x login runway";
    grid-template-columns: 8px minmax(0, 1fr) 150px;
    height: auto; padding-block: 10px; row-gap: 6px;
  }
  .core .row .login { font-size: 12px; }
  .core .left .rw { display: none; }
  .core .row .runway { align-self: center; }
  .verdict { flex-wrap: wrap; }
  .core .today { grid-template-columns: 1fr; }
  .core .figure, .core .shares, .core .links { grid-column: 1; }
  .core .links { justify-content: flex-start; }
  .readtime { display: none; }
}
@media (max-width: 820px) {
  body { overflow: auto; }
  .main { overflow: visible; }
  .viewbar { flex-wrap: wrap; }
  .stats, .split, .split.wide-left { grid-template-columns: 1fr; }
  .settings-shell { grid-template-columns: 1fr; }
  .settings-nav { position: static; grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .kv { grid-template-columns: 1fr; gap: 2px; }
}
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { animation: none !important; transition: none !important; }
  /* A bar that can't travel would read as stuck part-way, so the words carry it alone. */
  .meter.unknown > span { display: none; }
}
"""##
}
