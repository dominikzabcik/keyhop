import Foundation

/// The window's stylesheet: tokens first, with the day field's overrides, then the shell and each section.
extension DashboardPage {
    static let styles = ##"""
:root {
  --bg: hsl(0 0% 9%);
  --sidebar: hsl(0 0% 7.2%);
  --panel: hsl(0 0% 10.6%);
  --raised: hsl(0 0% 13.5%);
  --hover: hsl(var(--on) / .05);
  --border: hsl(var(--on) / .08);
  --border-strong: hsl(var(--on) / .14);
  --text: hsl(0 0% 92%);
  --muted: hsl(0 0% 63%);
  --subtle: hsl(0 0% 53%);
  --faint: hsl(var(--on) / .08);
  --primary: hsl(0 0% 95%);
  --on-primary: hsl(0 0% 9%);
  --focus: hsl(211 92% 62%);
  --good: #5CC98A;
  --warn: #E3A64F;
  --warn-ink: #f0c27a;
  --bad: #EE7A69;
  --info: #7eb0f2;
  /* The overlay tints: --on is the ink's hue, --off the surface's. Day flips them. */
  --on: 0 0% 100%;
  --off: 0 0% 0%;
  --bg-base: 0 0% 9%;
  --side: hsl(0 0% 56%);
  --overlay: hsl(0 0% 12.5% / .95);
  --scrim: hsl(0 0% 4% / .55);
  --headline-shadow: 0 1px 18px rgba(0, 0, 0, .55);
  --sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, "Segoe UI Variable Text", "Segoe UI", Roboto, Cantarell, "Noto Sans", sans-serif;
  --mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
  color-scheme: dark;
  /* Only the named content surfaces transition. The browser's implicit `root` snapshot includes
     the sidebar and cross-fades its old and new selection states over the moving thumb. */
  view-transition-name: none;
}
/* The day field: the same tokens read the other way up. Chosen in Settings, or follows the system. */
:root[data-theme="day"] {
  color-scheme: light;
  --bg: #f4f4f1;
  --sidebar: #efefec;
  --panel: #ffffff;
  --raised: #f1f1ee;
  --hover: hsl(0 0% 0% / .045);
  --border: hsl(0 0% 0% / .08);
  --border-strong: hsl(0 0% 0% / .14);
  --text: #1c1c1c;
  --muted: #5f5f5a;
  --subtle: #8a8a84;
  --faint: hsl(0 0% 0% / .08);
  --primary: #1c1c1c;
  --on-primary: #f4f4f1;
  --focus: hsl(211 60% 46%);
  --good: #1f8a4c;
  --warn: #b86e12;
  --warn-ink: #9a5b0c;
  --bad: #c44b3c;
  --info: #2f6fbe;
  --on: 0 0% 0%;
  --off: 0 0% 100%;
  --bg-base: 0 0% 96%;
  --side: #5c5c57;
  --overlay: hsl(var(--off) / .96);
  --scrim: hsl(0 0% 0% / .12);
  --headline-shadow: 0 1px 14px rgba(255, 255, 255, .75);
}

* { box-sizing: border-box; }
html, body { height: 100%; }
body {
  margin: 0;
  background: var(--bg);
  color: var(--text);
  font: 13.5px/1.5 var(--sans);
  -webkit-font-smoothing: antialiased;
  overflow: hidden;
}
button, input, select { font: inherit; color: inherit; }
button, a, input, select, summary { touch-action: manipulation; -webkit-tap-highlight-color: transparent; }
[hidden] { display: none !important; }
::-webkit-scrollbar { width: 8px; height: 8px; }
::-webkit-scrollbar-thumb { background: hsl(var(--on) / .12); border-radius: 99px; border: 2px solid transparent; background-clip: padding-box; }
::-webkit-scrollbar-track { background: transparent; }
.mono { font-family: var(--mono); font-size: 12px; }
.mark { width: 16px; height: 16px; flex: none; fill: currentColor; }
.nowrap { white-space: nowrap; }
.muted { color: var(--muted); }
.subtle { color: var(--subtle); }
.num { font-variant-numeric: tabular-nums; white-space: nowrap; }
[data-count], .mono, .table td, .ranked-share, .tile-foot, .limit-top b, .quest-state { font-variant-numeric: tabular-nums; }
.up { color: var(--good); }
.down { color: var(--bad); }
.skip-link { position: fixed; left: 12px; top: 12px; z-index: 100; padding: 8px 11px; border: 0; border-radius: 7px; background: var(--primary); color: var(--on-primary); font-weight: 600; cursor: pointer; transform: translateY(calc(-100% - 18px)); transition: transform .14s ease-out; }
.skip-link:focus-visible { transform: translateY(0); }

/* Shell */
.shell { display: grid; grid-template-columns: 252px minmax(0, 1fr); grid-template-rows: minmax(0, 1fr) 26px; height: 100vh; }
.sidebar { grid-column: 1; grid-row: 1; display: flex; flex-direction: column; background: var(--sidebar); border-right: 1px solid var(--border); min-height: 0; }
.brand, .hop-side, .side-label, .side-foot { flex: none; }
.brand { display: flex; align-items: center; gap: 10px; height: 52px; padding: 0 18px; border-bottom: 1px solid var(--border); }
.brand svg { width: 17px; height: 17px; flex: none; }
.brand b { font-weight: 650; font-size: 14px; letter-spacing: .01em; }
.brand .badge { margin-left: auto; }
.brand .channel-badge { margin-left: 0; color: var(--warn-ink); background: color-mix(in srgb, var(--warn) 16%, transparent); font-size: 10.5px; font-weight: 650; letter-spacing: .02em; }
/* Keys drawn as keys: a cap with a lip along its bottom edge. */
kbd { display: inline-grid; place-items: center; min-width: 20px; height: 20px; padding: 0 5px; border-radius: 5px; background: hsl(var(--on) / .07); box-shadow: inset 0 -1.5px 0 hsl(var(--on) / .09); color: var(--muted); font: 600 11px var(--sans); letter-spacing: .02em; }
.nav { position: relative; isolation: isolate; display: grid; align-content: start; gap: 2px; padding: 8px 10px 10px; flex: none; }
.nav-label { margin: 14px 10px 4px; color: var(--subtle); font-size: 12px; font-weight: 560; }
.nav.has-thumb::before { content: ""; position: absolute; z-index: -1; left: 10px; right: 10px; top: 0; height: var(--nav-h); transform: translateY(var(--nav-y)); border-radius: 8px; background: hsl(var(--on) / .08); transition: transform .3s cubic-bezier(.3, .8, .25, 1); }
.nav.no-slide::before { transition: none; }
.nav.has-thumb a[aria-current="page"] { background: transparent; }
.nav a {
  display: flex; align-items: center; gap: 10px; height: 34px; padding: 0 10px; border-radius: 8px;
  color: var(--side); text-decoration: none; font-weight: 520; transition: background .12s ease, color .12s ease;
}
.nav a:hover { background: var(--hover); color: var(--text); }
.nav a[aria-current="page"] { background: hsl(var(--on) / .08); color: var(--text); }
.nav svg, .icon { width: 16px; height: 16px; flex: none; fill: none; stroke: currentColor; stroke-width: 1.6; stroke-linecap: round; stroke-linejoin: round; }
.sidebar-foot { margin-top: auto; padding: 10px; border-top: 1px solid var(--border); display: grid; gap: 2px; }
.foot-row {
  display: flex; align-items: center; gap: 10px; width: 100%; padding: 8px 10px; border: 0; border-radius: 8px;
  background: transparent; text-align: left; cursor: pointer; color: var(--muted);
}
.foot-row:hover { background: var(--hover); color: var(--text); }
.foot-row span { display: grid; line-height: 1.3; min-width: 0; }
.foot-row b { font-weight: 560; color: var(--text); font-size: 13px; }
.foot-row small { font-size: 12px; color: var(--subtle); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.foot-row.spin .icon { animation: turn 1s linear infinite; }
@keyframes turn { to { transform: rotate(360deg); } }
/* Progress: one track, filled by width so its round ends stay round at every length. When the
   total isn't known yet, a short segment travels along it instead. */
.meter { position: relative; height: 4px; border-radius: 99px; background: var(--faint); overflow: hidden; }
.meter > span { position: absolute; left: 0; top: 0; bottom: 0; width: 0; border-radius: inherit; background: var(--text); transition: width .35s ease; }
.meter.unknown > span { width: 28%; animation: travel 1.3s ease-in-out infinite; }
@keyframes travel { from { left: -28%; } to { left: 100%; } }
.foot-row .meter { margin-top: 6px; height: 3px; }
/* A button doing its work keeps its label readable and says so with a turning ring. */
.btn.working { cursor: progress; }
.btn.working:disabled { opacity: 1; }
.btn .ring { width: 12px; height: 12px; flex: none; border-radius: 50%; border: 1.6px solid currentColor; border-right-color: transparent; animation: turn .8s linear infinite; }
/* In the Mac app's window the title bar buttons sit in the sidebar's top row, and that row and the
   top bar move the window. */
.mac-window .shell { grid-template-columns: 256px minmax(0, 1fr); }
.mac-window .brand { padding-left: 90px; }
.mac-window .brand, .mac-window .topbar { -webkit-user-select: none; user-select: none; cursor: default; }

.content { position: relative; display: flex; flex-direction: column; min-width: 0; min-height: 0; grid-column: 2; grid-row: 1; }
/* The backdrop: an illustrated scene behind the content. Its motion is transform and opacity
   only, so it stays smooth. */
.backdrop { position: absolute; inset: 0; z-index: 0; overflow: hidden; pointer-events: none; transition: opacity .4s ease; }
.backdrop.scoped-out { opacity: 0 !important; }
.topbar { position: relative; z-index: 3; display: flex; align-items: center; justify-content: space-between; gap: 16px; min-height: 52px; padding: 10px 24px; border-bottom: 1px solid var(--border); flex: none; }
/* Nothing scrolls under the top bar, so over the Field it simply gets out of the way. */
.has-backdrop .topbar { background: transparent; border-bottom-color: transparent; }
.topbar h1 { margin: 0; font-size: 18px; font-weight: 600; letter-spacing: -.01em; line-height: 1.2; }
.top-actions { display: flex; align-items: center; justify-content: flex-end; gap: 8px; min-width: 0; }
.hop { display: inline-flex; align-items: center; gap: 8px; height: 32px; padding: 0 8px 0 11px; border: 1px solid hsl(var(--on) / .1); border-radius: 8px; background: hsl(var(--on) / .045); color: var(--text); font-weight: 560; white-space: nowrap; cursor: pointer; transition: background-color .14s ease, border-color .14s ease, transform .08s ease-out; }
.hop:hover { background: hsl(var(--on) / .08); border-color: hsl(var(--on) / .16); }
.hop:active { transform: scale(.97); }
/* The whole window's progress, along the bottom edge of the top bar. */
.topbar .meter { position: absolute; left: 24px; right: 24px; bottom: -2px; height: 3px; background: transparent; opacity: 0; transition: opacity .25s ease; }
.topbar .meter.on { opacity: 1; }
.toolbar { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; justify-content: flex-end; }
.main { position: relative; z-index: 1; flex: 1; overflow: auto; padding: 22px 24px 40px; }
.page { max-width: 1320px; margin: 0 auto; display: grid; gap: 16px; }
.lede { margin: 0 0 4px; color: var(--muted); }

/* Components */
.card { background: var(--panel); border: 1px solid hsl(var(--on) / .06); border-radius: 12px; min-width: 0; box-shadow: inset 0 1px 0 hsl(var(--on) / .045); }
/* Over a scene, panels are tinted sheets: the scene reads through them, softened just enough to keep text crisp. */
.has-backdrop .card { background: hsl(var(--bg-base) / .64); border-color: hsl(var(--on) / .07); -webkit-backdrop-filter: blur(3px); backdrop-filter: blur(3px); }
/* The scenes are painted for the night. By day a card stays nearly solid over them. */
:root[data-theme="day"] .has-backdrop .card { background: hsl(var(--bg-base) / .92); }
/* In the Mac app the whole window can be glass: the desktop shows through, blurred, under one tint at
   the chosen window opacity. Panels, tabs and buttons turn into light washes over that glass, and
   scenes drop their own ground so only their artwork sits on it. */
.has-glass { --sidebar: hsl(var(--off) / .16); --panel: hsl(var(--on) / .035); --raised: hsl(var(--on) / .075); --border: hsl(var(--on) / .09); }
.has-glass body { background: transparent; }
.has-glass .shell { background: hsl(var(--bg-base) / var(--glass, .85)); }
.has-glass .card { background: var(--panel); -webkit-backdrop-filter: none; backdrop-filter: none; }
.has-glass .bd-scene:not(.bd-picture) { background: none; }
/* Overlays float over live content, so they stay nearly solid. */
.has-glass .tip, .has-glass .toast { background: var(--overlay); -webkit-backdrop-filter: blur(20px); backdrop-filter: blur(20px); }
.has-glass select.field option { background: var(--raised); }.range { width: 180px; accent-color: var(--text); }
.notices { display: grid; border-radius: 12px; border: 1px solid hsl(36 72% 60% / .24); background: hsl(36 40% 12% / .55); box-shadow: inset 0 1px 0 hsl(36 72% 70% / .06); }
.notice-row { display: flex; align-items: center; gap: 12px; padding: 12px 14px; }
.notice-row + .notice-row { border-top: 1px solid hsl(36 72% 60% / .12); }
.notice-row > .icon { color: var(--warn); }
.notice-row > div { flex: 1; min-width: 0; }
.notice-row b { font-weight: 600; }
.notice-row p { margin: 0; color: var(--muted); }
.pet-card { display: flex; align-items: center; gap: 8px 22px; padding: 8px 22px 8px 6px; }
.pet-card .pet { width: 140px; height: auto; flex: none; }
@media (prefers-reduced-motion: no-preference) {
  .pet { animation: pet-live 2.8s ease-in-out infinite; transform-box: fill-box; transform-origin: center 80%; }
}
@keyframes pet-live { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-3px); } }
.pet rect.flame { animation: pet-flame 1.1s steps(2, end) infinite; }
.pet rect.shine { animation: pet-blink 3.6s steps(1, end) infinite; }
@keyframes pet-flame { 50% { opacity: .45; } }
@keyframes pet-blink { 0%, 88%, 100% { opacity: 1; } 92%, 96% { opacity: 0; } }
.pet-card h2 { margin: 0; font-size: 20px; font-weight: 600; letter-spacing: -.02em; }
.pet-card p { margin: 6px 0 0; color: var(--muted); font-size: 14px; max-width: 62ch; }
.btn.claim-kick { height: 48px; padding: 0 22px; border-radius: 10px; font-size: 16px; font-weight: 650; }
.card-body .btn.claim-kick { width: 100%; }
.pet-slot { display: flex; align-items: center; justify-content: space-between; gap: 16px; padding: 18px 20px; }
.pet-slot p { margin: 4px 0 0; color: var(--muted); font-size: 14px; }
.card-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 12px 16px; border-bottom: 1px solid hsl(var(--on) / .05); min-height: 50px; flex-wrap: wrap; }
.card-head h2 { margin: 0; font-size: 14px; font-weight: 560; display: flex; align-items: center; gap: 8px; }
.card-head .hint { color: var(--subtle); font-size: 12.5px; }
.card-body { padding: 16px; }
.split { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
.split.wide-left { grid-template-columns: minmax(0, 1.55fr) minmax(0, 1fr); }
.stats { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 16px; }
.stats.three { grid-template-columns: repeat(3, minmax(0, 1fr)); }
.stat { padding: 14px 16px 16px; }
.stat .label { color: var(--muted); font-size: 12.5px; display: flex; justify-content: space-between; gap: 8px; }
.stat .value { margin-top: 6px; font-size: 24px; font-weight: 600; letter-spacing: -.02em; line-height: 1.2; font-variant-numeric: tabular-nums; }
.stat .foot { margin-top: 4px; font-size: 12px; color: var(--subtle); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

.btn {
  display: inline-flex; align-items: center; justify-content: center; gap: 6px; height: 32px; padding: 0 12px;
  border-radius: 7px; border: 1px solid transparent; cursor: pointer; font-weight: 560; font-size: 13px; white-space: nowrap;
  background: var(--primary); color: var(--on-primary); transition: background .12s ease, border-color .12s ease, color .12s ease;
}
.btn:hover { background: hsl(var(--on)); }
.btn.secondary { background: var(--raised); color: var(--text); border-color: var(--border); }
.btn.secondary:hover { background: hsl(var(--on) / .12); border-color: var(--border-strong); }
.btn.ghost { background: transparent; color: var(--muted); }
.btn.ghost:hover { background: var(--hover); color: var(--text); }
.btn.danger:hover { color: var(--bad); }
.btn.sm { height: 28px; padding: 0 10px; font-size: 12.5px; }
.btn:disabled { opacity: .45; cursor: default; }
/* A press gives way a little; nothing moves on hover. */
.btn:active:not(:disabled), .tabs button:active, button.tile:active { transform: scale(.975); }
.btn, button.tile { transition-property: background, border-color, color, transform; transition-duration: .14s, .14s, .14s, .08s; }
a.btn { text-decoration: none; }
.main p a:not(.btn) { color: var(--text); text-underline-offset: 3px; }
:focus-visible { outline: 2px solid var(--focus); outline-offset: 2px; }

/* A contained status, used sparingly: plain words on a quiet surface, no dot and no capitals. */
.badge {
  display: inline-flex; align-items: center; gap: 5px; height: 20px; padding: 0 8px; border-radius: 6px;
  background: hsl(var(--on) / .07); color: var(--muted); font-size: 11.5px; font-weight: 560; white-space: nowrap;
}
.badge.live { color: hsl(145 28% 72%); background: hsl(145 30% 50% / .1); }
.badge.sample { color: var(--warn); background: hsl(36 72% 60% / .1); }

.tabs { position: relative; isolation: isolate; display: inline-flex; padding: 3px; gap: 2px; border-radius: 8px; background: var(--raised); border: 1px solid var(--border); }
/* The pressed option rides a thumb that slides to the next one; without it, the option keeps its own fill. */
.tabs.has-thumb::before { content: ""; position: absolute; z-index: -1; top: 3px; bottom: 3px; left: 0; width: var(--thumb-w); transform: translateX(var(--thumb-x)); border-radius: 5px; background: hsl(var(--on) / .1); box-shadow: inset 0 1px 0 hsl(var(--on) / .06); transition: transform .28s cubic-bezier(.3, .8, .25, 1), width .28s cubic-bezier(.3, .8, .25, 1); }
.tabs.no-slide::before { transition: none; }
.tabs.has-thumb button[aria-pressed="true"] { background: transparent; }
.tabs button { height: 26px; padding: 0 10px; border: 0; border-radius: 5px; background: transparent; color: var(--muted); cursor: pointer; font-size: 12.5px; font-weight: 540; transition: color .18s ease; }
.tabs button:hover { color: var(--text); }
.tabs button[aria-pressed="true"] { background: hsl(var(--on) / .1); color: var(--text); }
.tabs button:disabled { opacity: .4; cursor: default; }

.field {
  height: 32px; width: 100%; padding: 0 10px; border-radius: 7px; border: 1px solid var(--border-strong);
  background: transparent; color: var(--text); transition: border-color .12s ease;
}
.field:hover { border-color: hsl(var(--on) / .22); }
.field::placeholder { color: var(--subtle); }
select.field { appearance: none; padding-right: 28px; background-image: linear-gradient(45deg, transparent 50%, var(--muted) 50%), linear-gradient(135deg, var(--muted) 50%, transparent 50%); background-position: calc(100% - 15px) 14px, calc(100% - 11px) 14px; background-size: 4px 4px; background-repeat: no-repeat; }
select.field option { background: var(--raised); }
.toolbar select.field { width: auto; height: 32px; }
.range-pick { position: relative; }
.range-button { display: inline-flex; align-items: center; gap: 8px; height: 32px; padding: 0 10px 0 12px; border-radius: 7px; border: 1px solid var(--border-strong); background: var(--raised); color: var(--text); font: inherit; font-size: 12.5px; font-weight: 560; cursor: pointer; white-space: nowrap; }
.range-button:hover { border-color: hsl(var(--on) / .22); }
.range-button svg { width: 10px; height: 10px; color: var(--muted); transition: transform .16s ease; }
.range-button[aria-expanded="true"] svg { transform: rotate(180deg); }
.range-menu { position: absolute; top: calc(100% + 6px); left: 0; z-index: 30; width: 268px; padding: 6px; border-radius: 10px; border: 1px solid var(--border-strong); background: var(--raised); box-shadow: 0 8px 20px -10px rgba(0, 0, 0, .6); }
.range-list { display: grid; grid-template-columns: 1fr 1fr; gap: 2px; }
.range-list button { height: 30px; padding: 0 10px; border: 0; border-radius: 6px; background: transparent; color: var(--muted); font: inherit; font-size: 12.5px; text-align: left; cursor: pointer; }
.range-list button:hover { color: var(--text); background: hsl(var(--on) / .05); }
.range-list button[aria-checked="true"] { color: var(--text); background: hsl(var(--on) / .1); font-weight: 560; }
.range-dates { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 6px; padding: 10px 4px 4px; border-top: 1px solid var(--border); }
.range-dates label { display: grid; gap: 4px; font-size: 11.5px; color: var(--muted); }
.range-dates .field { height: 30px; padding: 0 8px; font-size: 12.5px; }
.range-dates .btn { grid-column: 1 / -1; justify-content: center; }

.progress { position: relative; height: 6px; border-radius: 99px; background: var(--faint); overflow: visible; }
.progress > span { position: absolute; left: 0; top: 0; bottom: 0; border-radius: inherit; background: var(--text); transition: width .5s ease; }
.progress.warn > span { background: var(--warn); }
.progress.bad > span { background: var(--bad); }
.progress > i { position: absolute; top: -3px; bottom: -3px; width: 2px; margin-left: -1px; border-radius: 1px; background: hsl(var(--on) / .45); }

.list > .row { padding: 14px 16px; }
.list > .row + .row { border-top: 1px solid var(--border); }
.empty { padding: 20px 16px; color: var(--muted); }
.empty-inline { color: var(--muted); margin: 0; }

.notice { display: flex; align-items: center; gap: 12px; padding: 12px 14px; border: 1px solid hsl(36 72% 60% / .28); background: hsl(36 72% 60% / .06); border-radius: 10px; }
.notice .icon { color: var(--warn); }
.notice div { flex: 1; min-width: 0; }
.notice b { font-weight: 600; }
.notice p { margin: 0; color: var(--muted); }
.warn-text { color: var(--warn); }

/* Overview */
.tool-row { display: grid; grid-template-columns: minmax(190px, 1fr) minmax(260px, 1.6fr) 210px; gap: 20px; align-items: center; }
.who { display: flex; align-items: center; gap: 12px; min-width: 0; }
.who .mark { width: 18px; height: 18px; fill: var(--text); flex: none; }
.who div { min-width: 0; }
.who b { display: block; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.who small { display: block; color: var(--subtle); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.limits { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 18px; }
.limit-top { display: flex; justify-content: space-between; gap: 8px; font-size: 12.5px; color: var(--muted); margin-bottom: 7px; }
.limit-top b { color: var(--text); font-weight: 580; font-family: var(--mono); font-size: 12px; }
.limit-foot { margin-top: 6px; font-size: 11.5px; color: var(--subtle); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.row-actions { display: flex; gap: 6px; justify-content: flex-end; flex-wrap: wrap; }
.problem { color: var(--bad); font-size: 12.5px; margin: 0; }

/* Accounts */
.group { display: grid; gap: 6px; }
.group-head { display: flex; align-items: center; gap: 8px; min-height: 28px; }
.group-head .mark { width: 16px; height: 16px; fill: var(--text); }
.group-head h2 { margin: 0; font-size: 13px; font-weight: 600; letter-spacing: -.01em; }
.group-head .count { color: var(--subtle); font-family: var(--mono); font-size: 12px; }
.group-head .btn { margin-left: auto; }
.acct-sheet { width: min(860px, 100%); margin: 0 auto; display: grid; gap: 14px; }
.group .list > .row { padding: 8px 12px; }
.account-row { display: grid; grid-template-columns: minmax(0, 1fr) 132px minmax(108px, max-content); gap: 4px 16px; align-items: center; }
.account-row .row-actions { flex-wrap: nowrap; }
.account-id { display: flex; align-items: flex-start; gap: 8px; min-width: 0; }
.account-id .ldot { margin-top: 6px; }
.account-copy { min-width: 0; }
.account-name { display: flex; align-items: center; gap: 8px; min-width: 0; }
.account-name b { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.account-name b.warn { color: var(--warn-ink); }
.account-line { margin-top: 1px; color: var(--muted); font-size: 12.5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.in-use { display: inline-flex; align-items: center; flex: none; height: 20px; padding: 0 8px; border-radius: 6px; background: hsl(var(--on) / .1); color: var(--text); font-size: 11.5px; font-weight: 600; }
.account-row.active { background: hsl(var(--on) / .018); }
.list > .account-row:hover { background: var(--hover); }
.account-row .today { display: grid; gap: 0; justify-items: end; text-align: right; font-family: var(--sans); }
.account-row .today b { font-size: 14px; font-weight: 600; letter-spacing: -.01em; color: var(--text); line-height: 1.3; font-variant-numeric: tabular-nums; }
.account-row .today span { color: var(--subtle); font-size: 12px; white-space: nowrap; }
.menu-anchor { position: relative; display: inline-flex; }
.btn.icon-only { width: 28px; padding: 0; }
.btn.icon-only .icon { width: 16px; height: 16px; }
.row-menu { position: absolute; right: 0; top: calc(100% + 6px); z-index: 20; min-width: 190px; padding: 5px; display: grid; gap: 2px; border-radius: 10px; border: 1px solid var(--border-strong); background: var(--raised); box-shadow: 0 8px 20px -10px rgba(0, 0, 0, .6); animation: menu-in .14s cubic-bezier(.2, .8, .2, 1); }
.row-menu button { height: 30px; padding: 0 10px; border: 0; border-radius: 6px; background: transparent; color: var(--text); font: inherit; font-size: 13px; text-align: left; cursor: pointer; }
.row-menu button:hover { background: hsl(var(--on) / .06); }
.row-menu button.danger { color: var(--bad); }
@keyframes menu-in { from { opacity: 0; transform: translateY(-4px); } }
.account-name b { font-weight: 600; font-size: 14px; }

.today { color: var(--muted); font-size: 12px; font-family: var(--mono); line-height: 1.5; }
.rename { display: flex; gap: 8px; align-items: center; }
.rename .field { max-width: 260px; }
.waiting { display: flex; align-items: center; gap: 12px; color: var(--muted); }
.waiting small { color: var(--subtle); font-size: 12px; }
.waiting-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.pulse { display: inline-flex; gap: 3px; }
.busy { display: flex; align-items: center; gap: 10px; }
.loading { display: grid; gap: 10px; max-width: 420px; }
.loading .busy { margin: 0; }
.loading .busy b { font-weight: 560; color: var(--text); }
.loading .count { margin-left: auto; font-variant-numeric: tabular-nums; color: var(--muted); }
.loading small { color: var(--subtle); font-size: 12px; }
.busy-note { margin: 2px 0 0; color: var(--muted); }
.unset-row { display: grid; grid-template-columns: auto 1fr auto; align-items: center; gap: 14px; }
.unset-row p { margin: 0; }
.unset-marks { display: flex; gap: 6px; opacity: .55; }
.unset-marks .mark { width: 14px; height: 14px; }
.pulse i { width: 5px; height: 5px; border-radius: 50%; background: var(--text); opacity: .25; animation: pulse 1.2s ease-in-out infinite; }
.pulse i:nth-child(2) { animation-delay: .15s; } .pulse i:nth-child(3) { animation-delay: .3s; }
@keyframes pulse { 40% { opacity: 1; } }

/* Usage */
.legend { display: flex; flex-wrap: wrap; gap: 4px 14px; list-style: none; margin: 0; padding: 0; font-size: 12px; color: var(--muted); }
.legend li { display: flex; align-items: center; }
.legend-item { display: inline-flex; align-items: center; gap: 6px; padding: 2px 6px; margin: -2px -6px; border: 0; border-radius: 5px; background: transparent; color: inherit; font: inherit; cursor: pointer; transition: color .15s ease, opacity .15s ease, background .15s ease; }
.legend-item:hover { color: var(--text); background: hsl(var(--on) / .04); }
.legend-item[aria-pressed="false"] { opacity: .45; }
.legend-item[aria-pressed="false"] .swatch { background: transparent !important; box-shadow: inset 0 0 0 1.5px var(--subtle); }
.swatch { width: 8px; height: 8px; border-radius: 2px; flex: none; }
.chart { overflow-x: auto; }
.chart svg { display: block; }
.chart .grid { stroke: hsl(var(--on) / .06); }
.chart .base { stroke: hsl(var(--on) / .16); }
.chart .axis { fill: var(--subtle); font: 11px var(--mono); }
.chart .hit { fill: transparent; }
.chart .hit:hover { fill: hsl(var(--on) / .03); }
.chart .col { transition: opacity .18s ease; }
.chart svg[data-hover] .col { opacity: .4; }
.chart svg[data-hover] .col.on { opacity: 1; }
.heat rect[data-action] { cursor: pointer; }
.heat rect[data-action]:hover { stroke: hsl(var(--on) / .7); stroke-width: 1.2; }
::view-transition-group(usage-chart) { animation-duration: .24s; }
.heat rect.l0 { fill: hsl(var(--on) / .05); }
.heat rect.l1 { fill: hsl(var(--on) / .18); }
.heat rect.l2 { fill: hsl(var(--on) / .36); }
.heat rect.l3 { fill: hsl(var(--on) / .6); }
.heat rect.l4 { fill: hsl(var(--on) / .9); }
.heat text { fill: var(--subtle); font: 10.5px var(--mono); }
svg.heat { display: block; margin: 0 auto; }
.scale { display: inline-flex; align-items: center; gap: 3px; font-size: 11.5px; color: var(--subtle); }
.scale i { width: 10px; height: 10px; border-radius: 2px; }
.facts { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); border-top: 1px solid var(--border); }
.facts div { padding: 12px 16px; }
.facts div + div { border-left: 1px solid var(--border); }
.facts b { display: block; font-size: 18px; font-weight: 600; letter-spacing: -.01em; font-variant-numeric: tabular-nums; }
.facts span { color: var(--subtle); font-size: 12px; }
.mix-bar { display: flex; gap: 2px; height: 8px; border-radius: 99px; overflow: hidden; margin-bottom: 16px; }
.mix-bar span { min-width: 2px; }
.m1 { background: hsl(var(--on) / .9); } .m2 { background: hsl(var(--on) / .55); } .m3 { background: hsl(var(--on) / .3); } .m4 { background: hsl(var(--on) / .18); }
.m5 { background: hsl(var(--on) / .1); }
.table { width: 100%; border-collapse: collapse; }
.table th { text-align: left; font-weight: 500; color: var(--subtle); font-size: 12px; padding: 10px 16px; border-bottom: 1px solid var(--border); }
.table td { padding: 10px 16px; border-bottom: 1px solid hsl(var(--on) / .045); vertical-align: middle; font-variant-numeric: tabular-nums; }
.table tr:last-child td { border-bottom: 0; }
.table tbody tr:hover td { background: hsl(var(--on) / .02); }
.table tbody tr.clickable { cursor: pointer; }
.table .right { text-align: right; }
.table .bar-cell { width: 34%; }
.cell-name { display: flex; align-items: center; gap: 8px; min-width: 0; }
.cell-name span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
/* Usage sits in two columns that share one gutter: the rail, then the figure and the chart. */
.usage-board { display: grid; grid-template-columns: minmax(280px, 34%) minmax(0, 1fr); gap: 12px; align-items: start; }
.usage-side, .usage-main { display: grid; gap: 12px; align-content: start; min-width: 0; }
.usage-side svg.heat { max-width: 100%; height: auto; }
.total-card { padding: 20px 22px 22px; display: grid; gap: 14px; align-content: start; }
.total-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; min-height: 28px; color: var(--muted); font-size: 13px; }
.total-change { display: inline-flex; align-items: baseline; gap: 8px; font-size: 12.5px; }
.total-change .mono { font-size: 12.5px; }
.total-figure { font-weight: 600; font-size: clamp(36px, 4.4vw, 54px); line-height: 1.05; letter-spacing: -.035em; overflow-wrap: anywhere; font-variant-numeric: tabular-nums; }
.total-facts { margin: -4px 0 0; color: var(--muted); font-size: 13px; }
.share-bar { display: flex; gap: 3px; height: 10px; margin-top: 4px; }
.share-bar span { min-width: 4px; border-radius: 99px; flex-basis: 0; transition: flex-grow .7s cubic-bezier(.2, .8, .2, 1); }
.progress > span, .ranked-track span, .mix-bar span { transition: width .7s cubic-bezier(.2, .8, .2, 1); }
.tile-mid { display: flex; align-items: flex-end; justify-content: space-between; gap: 10px; min-width: 0; }
.spark { width: 64px; height: 24px; flex: none; overflow: visible; }
.tiles { display: grid; grid-template-columns: repeat(auto-fill, minmax(148px, 1fr)); gap: 8px; }
.tile { display: grid; gap: 6px; align-content: start; padding: 11px 12px 12px; border-radius: 10px; border: 1px solid hsl(var(--on) / .055); background: hsl(var(--on) / .022); color: var(--text); text-align: left; font: inherit; min-width: 0; }
button.tile { cursor: pointer; transition: background .14s ease, border-color .14s ease; }
button.tile:hover { background: hsl(var(--on) / .05); border-color: hsl(var(--on) / .1); }
.tile-name { display: flex; align-items: center; gap: 8px; min-width: 0; font-size: 12.5px; color: var(--muted); }
.tile-name > span:last-child { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.tile-name .mark { width: 14px; height: 14px; fill: var(--text); }
.tile-share { font-weight: 600; font-size: 20px; letter-spacing: -.02em; line-height: 1.15; font-variant-numeric: tabular-nums; }
.tile-foot { display: flex; align-items: center; gap: 6px; color: var(--subtle); font-size: 11.5px; font-variant-numeric: tabular-nums; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.tile-foot .swatch { width: 6px; height: 6px; border-radius: 50%; }
.summary-card { padding: 16px; display: grid; gap: 16px; align-content: start; }
.chips { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; }
.chip { display: grid; gap: 2px; padding: 10px 12px; border-radius: 10px; background: hsl(var(--on) / .03); }
.chip b { font-weight: 600; font-size: 18px; letter-spacing: -.015em; line-height: 1.2; font-variant-numeric: tabular-nums; }
.chip span { color: var(--subtle); font-size: 11.5px; }
.ranked { list-style: none; margin: 0; padding: 0; display: grid; gap: 12px; }
.ranked li { display: grid; grid-template-columns: 18px minmax(0, 1fr) auto; column-gap: 8px; row-gap: 6px; align-items: center; }
.ranked .place { color: var(--subtle); font: 11.5px var(--mono); text-align: center; }
.ranked-name { display: flex; align-items: center; gap: 8px; min-width: 0; }
.ranked-name .mark { width: 14px; height: 14px; fill: var(--muted); }
.ranked-name .mono { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.ranked-share { font: 12px var(--mono); color: var(--text); }
.ranked-value { margin-left: auto; font: 11.5px var(--mono); }
.ranked-track { grid-column: 2 / -1; height: 3px; border-radius: 99px; background: var(--faint); overflow: hidden; }
.ranked-track span { display: block; height: 100%; border-radius: inherit; background: hsl(var(--on) / .55); }
.summary-foot { display: flex; justify-content: space-between; gap: 12px; margin-top: auto; padding-top: 12px; border-top: 1px solid hsl(var(--on) / .05); color: var(--subtle); font-size: 12px; }
.chart-body { display: grid; gap: 14px; }
.table-wrap { overflow-x: auto; }
.table.data th, .table.data td { padding-left: 14px; padding-right: 14px; }
.table .strong { color: var(--text); font-weight: 600; }
.table td.mono { color: var(--muted); }
.table td.mono.strong { color: var(--text); }
.place-cell { width: 36px; text-align: center; }
.table-more { display: flex; justify-content: center; padding: 10px; border-top: 1px solid hsl(var(--on) / .045); }

/* Leaderboard */
.avatar { display: inline-grid; place-items: center; flex: none; border-radius: 50%; background: var(--raised); color: var(--muted); font-weight: 600; }
.podium { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 16px; }
/* Tiers read by their mark and their name, in a quiet tone of their own. */
.tier { display: inline-flex; align-items: center; gap: 8px; font-weight: 600; color: var(--tier); white-space: nowrap; }
.tier svg { width: 23px; height: 18px; fill: currentColor; flex: none; }
.tier.sm { gap: 6px; font-size: 12.5px; }
.tier.sm svg { width: 15px; height: 12px; }
.tier-bronze { --tier: hsl(26 20% 58%); }
.tier-silver { --tier: hsl(0 0% 68%); }
.tier-gold { --tier: hsl(42 26% 66%); }
.tier-platinum { --tier: hsl(190 12% 72%); }
.tier-diamond { --tier: hsl(205 20% 80%); }
.tier-master { --tier: var(--primary); }
.season-row { display: flex; align-items: center; gap: 16px; padding: 14px 16px; flex-wrap: wrap; }
.quest-row { display: grid; grid-template-columns: minmax(0, 1fr) 128px; gap: 4px 18px; align-items: center; padding: 11px 16px; }
.quest-row + .quest-row { border-top: 1px solid var(--border); }
.quest-row p { margin: 2px 0 0; color: var(--muted); font-size: 12.5px; }
.quest-track { height: 6px; border-radius: 99px; background: var(--faint); overflow: hidden; }
.quest-track span { display: block; height: 100%; border-radius: inherit; background: var(--text); }
.quest-row.done .quest-track span { background: var(--good); }
.quest-state { margin-top: 5px; font-size: 12px; color: var(--subtle); font-variant-numeric: tabular-nums; }
.quest-row.done .quest-state { color: var(--good); }
.season-row .grow { flex: 1; min-width: 200px; }
.season-row p { margin: 3px 0 0; color: var(--muted); }
.podium-card { padding: 16px; display: grid; gap: 12px; }
.podium-card .place { color: var(--subtle); font-size: 12px; }
.podium-card.you { border-color: var(--border-strong); }
.podium-value { font-size: 24px; font-weight: 600; letter-spacing: -.02em; line-height: 1.2; font-variant-numeric: tabular-nums; }
.podium .mix-bar, .table .mix-bar { margin: 0; height: 6px; }
.day-sum { display: flex; flex-wrap: wrap; gap: 8px 18px; margin: 0 0 16px; color: var(--muted); }
.day-sum b { color: var(--text); font-variant-numeric: tabular-nums; }
.day-head { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; flex-wrap: wrap; }
.day-figures { display: flex; gap: 16px; }
.day-figures div { text-align: right; }
.day-figures b { display: block; font-variant-numeric: tabular-nums; font-weight: 600; }
.live-dot { display: inline-block; width: 6px; height: 6px; margin-right: 5px; border-radius: 50%; background: var(--good); vertical-align: 1px; }
.team-digest { margin: 14px 0; padding-top: 14px; border-top: 1px solid var(--border); display: grid; gap: 6px; }
.team-digest b { font-weight: 600; }
/* Coach: findings first, then the figures that back them. */
.coach-finding { margin: 0 0 8px; padding: 10px 12px; border-radius: 8px; background: hsl(var(--on) / .04); font-size: 13px; }
.coach-finding.fine, .coach-finding.quiet { color: var(--muted); }
.coach-finding.cache, .coach-finding.premium, .coach-finding.session { border-left: 3px solid var(--warn); }
.coach-deltas { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 12px; }
.coach-delta { display: grid; gap: 2px; padding: 10px 12px; border-radius: 10px; background: hsl(var(--on) / .03); font-size: 12px; }
.coach-delta b { font-size: 18px; font-weight: 640; letter-spacing: -.02em; }
/* Plans: one card per login, the month's API value against the plan's price. */
.plans-headline { margin: 0 0 6px; font-size: 17px; font-weight: 620; letter-spacing: -.015em; text-wrap: pretty; }
.plans-head .subtle { margin: 0; font-size: 12.5px; max-width: 72ch; }
.plan-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 14px; margin-top: 14px; }
.plan-card .card-head h2 { gap: 8px; }
.plan-top { display: flex; justify-content: space-between; gap: 16px; margin-bottom: 10px; }
.plan-top > div { display: grid; gap: 2px; }
.plan-top b { font-size: 15px; font-weight: 620; }
.plan-value { text-align: right; }
.plan-value b { font-size: 20px; font-weight: 640; letter-spacing: -.02em; }
.plan-verdict { margin: 12px 0 0; font-size: 13px; }
.plan-advice { margin: 6px 0 0; font-size: 13px; color: var(--warn-ink); }
.plan-windows { display: grid; gap: 8px; margin-top: 12px; padding-top: 12px; border-top: 1px solid var(--border); }
.plan-window { display: grid; grid-template-columns: 64px minmax(0, 1fr) 78px; gap: 10px; align-items: center; font-size: 12px; }
.plan-window .num { text-align: right; }
.pill { display: inline-flex; align-items: center; height: 22px; padding: 0 8px; border-radius: 6px; background: hsl(var(--on) / .07); color: var(--muted); font-size: 11.5px; font-weight: 560; white-space: nowrap; }
.pill.bad { color: var(--bad); background: color-mix(in srgb, var(--bad) 16%, transparent); }
.pill.warn { color: var(--warn-ink); background: color-mix(in srgb, var(--warn) 16%, transparent); }
.outbound { border-top: 1px solid var(--border); }
.outbound summary { display: flex; gap: 12px; align-items: center; padding: 10px 0; cursor: pointer; list-style: none; }
.outbound summary::-webkit-details-marker { display: none; }
.outbound summary .subtle { font-size: 12.5px; }
.outbound pre { margin: 0 0 12px; max-height: 320px; overflow: auto; padding: 10px 12px; border-radius: 8px; background: hsl(var(--on) / .04); font-size: 11.5px; line-height: 1.45; white-space: pre-wrap; overflow-wrap: anywhere; }
.day-figures small, .task-meta, .day-note { color: var(--subtle); font-size: 12px; }
.task { padding: 12px 16px; border-top: 1px solid var(--border); }
.task h3 { margin: 0; font-size: 14px; font-weight: 600; }
.task-meta { display: flex; flex-wrap: wrap; gap: 4px 12px; margin-top: 4px; }
.commits { list-style: none; margin: 8px 0 0; padding: 0; display: grid; gap: 4px; }
.commit { display: flex; gap: 8px; align-items: baseline; color: var(--muted); font-size: 12.5px; }
.sha { font-family: var(--mono); font-size: 11.5px; color: var(--subtle); }
.day-nav { display: flex; align-items: center; gap: 6px; }
.day-nav .now { padding: 0 8px; font-weight: 600; }
.table tr.me td { background: hsl(var(--on) / .035); }
.plain-link { color: inherit; text-decoration: none; }
.plain-link:hover { text-decoration: underline; text-underline-offset: 3px; }

/* Budgets and settings */
.form { display: grid; gap: 14px; padding: 16px; }
.form label { display: grid; gap: 6px; font-size: 12.5px; color: var(--muted); font-weight: 520; }
.form .pair { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
.budget-row { display: grid; gap: 8px; }
.budget-top { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; }
.budget-top b { font-weight: 600; }
.kv { display: grid; grid-template-columns: 150px minmax(0, 1fr); gap: 16px; align-items: baseline; }
.kv > span:first-child { color: var(--muted); }
.kv .mono { overflow-wrap: anywhere; }
.setting-row { display: flex; align-items: center; justify-content: space-between; gap: 16px; }
.setting-row p { margin: 2px 0 0; color: var(--muted); }
.settings-shell { display: grid; grid-template-columns: 176px minmax(0, 1fr); gap: 16px; align-items: start; }
.settings-nav { position: sticky; top: 0; display: grid; gap: 3px; padding: 6px; }
.settings-nav button { display: flex; align-items: center; gap: 9px; width: 100%; height: 36px; padding: 0 10px; border: 0; border-radius: 8px; background: transparent; color: var(--muted); text-align: left; cursor: pointer; transition: background-color .12s ease, color .12s ease; }
.settings-nav button:hover { background: var(--hover); color: var(--text); }
.settings-nav button[aria-current="page"] { background: hsl(var(--on) / .08); color: var(--text); }
.settings-pane { display: grid; gap: 16px; min-width: 0; }
.settings-intro { padding: 4px 2px 2px; }
.settings-intro h2 { margin: 0; font-size: 17px; font-weight: 600; letter-spacing: -.01em; }
.settings-intro p { max-width: 62ch; margin: 4px 0 0; color: var(--muted); }
.update-status { display: inline-flex; align-items: center; gap: 8px; color: var(--muted); }
.update-status .ring { width: 12px; height: 12px; border: 1.5px solid currentColor; border-right-color: transparent; border-radius: 50%; animation: turn .8s linear infinite; }

/* Jump to */
#palette { position: fixed; inset: 0; z-index: 40; }
.palette-scrim { position: absolute; inset: 0; background: var(--scrim); animation: fade-in .14s ease; }
.palette { position: absolute; left: 50%; top: 14vh; width: min(560px, calc(100vw - 32px)); transform: translateX(-50%); display: grid; grid-template-rows: auto minmax(0, 1fr) auto; max-height: min(520px, 72vh);
  border-radius: 14px; border: 1px solid hsl(var(--on) / .1); background: var(--overlay); box-shadow: inset 0 1px 0 hsl(var(--on) / .06), 0 12px 24px -14px rgba(0, 0, 0, .75); animation: palette-in .16s cubic-bezier(.2, .8, .2, 1); overflow: hidden; }
@keyframes fade-in { from { opacity: 0; } }
@keyframes palette-in { from { opacity: 0; transform: translateX(-50%) translateY(-6px) scale(.985); } }
.palette-search { display: flex; align-items: center; gap: 10px; padding: 0 16px; height: 52px; border-bottom: 1px solid hsl(var(--on) / .06); color: var(--muted); }
.palette-search:focus-within { box-shadow: inset 0 0 0 2px var(--focus); }
.palette-search input { flex: 1; height: 100%; border: 0; background: transparent; outline: none; font-size: 15px; color: var(--text); }
.palette-search input::placeholder { color: var(--subtle); }
.palette-list { overflow-y: auto; padding: 6px; }
.palette-group { padding: 10px 10px 4px; color: var(--subtle); font-size: 11.5px; }
.palette-item { display: flex; align-items: center; gap: 10px; width: 100%; height: 36px; padding: 0 10px; border: 0; border-radius: 8px; background: transparent; color: var(--text); font: inherit; text-align: left; cursor: pointer; }
.palette-item .mark, .palette-item .icon { width: 15px; height: 15px; color: var(--muted); fill: var(--muted); }
.palette-item .icon { fill: none; }
.palette-item small { margin-left: auto; color: var(--subtle); font-size: 12px; }
.palette-item kbd { margin-left: auto; }
.palette-item small + kbd { margin-left: 8px; }
.palette-item[aria-selected="true"] { background: hsl(var(--on) / .07); }
.palette-dot { width: 15px; display: grid; place-items: center; }
.palette-dot::before { content: ""; width: 5px; height: 5px; border-radius: 50%; background: hsl(var(--on) / .28); }
.palette-empty { margin: 0; padding: 18px 12px; color: var(--muted); }
.palette-foot { display: flex; gap: 16px; padding: 10px 16px; border-top: 1px solid hsl(var(--on) / .06); color: var(--subtle); font-size: 12px; }
.palette-foot span { display: inline-flex; align-items: center; gap: 4px; }

/* Moving between sections: the page settles in place of the last one. */
.main { view-transition-name: main-view; }
.topbar h1 { view-transition-name: page-title; }
::view-transition-old(main-view) { animation: page-out .14s ease both; }
::view-transition-new(main-view) { animation: page-in .26s cubic-bezier(.2, .8, .2, 1) both; }
::view-transition-old(page-title), ::view-transition-new(page-title) { animation-duration: .2s; }
@keyframes page-out { to { opacity: 0; } }
@keyframes page-in { from { opacity: 0; transform: translateY(8px); } }

/* Overlays */
.tip {
  position: fixed; z-index: 20; pointer-events: none; min-width: 190px; max-width: 320px; padding: 10px 12px;
  background: var(--raised); border: 1px solid var(--border-strong); border-radius: 8px; font-size: 12px;
  box-shadow: 0 8px 20px -10px rgba(0, 0, 0, .6);
}
.tip b { display: block; font-weight: 600; margin-bottom: 6px; }
.tip div { display: grid; grid-template-columns: 10px minmax(0, 1fr) auto; gap: 8px; align-items: center; margin-top: 3px; }
.tip div span:nth-child(2) { color: var(--muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.toast {
  position: fixed; right: 20px; bottom: 40px; z-index: 30; max-width: min(460px, calc(100vw - 40px)); padding: 12px 14px;
  background: var(--raised); border: 1px solid var(--border-strong); border-radius: 10px; font-size: 13px;
  box-shadow: 0 10px 24px -12px rgba(0, 0, 0, .7); transition: transform .25s ease, opacity .25s ease;
}
.toast.away { transform: translateY(12px); opacity: 0; pointer-events: none; }
.toast.error { border-color: hsl(8 80% 67% / .45); }

/* The home shell: a night field, an account tree, and a limits board. */
.hop-side { width: calc(100% - 20px); margin: 8px 10px 0; justify-content: flex-start; }
.hop-side kbd { margin-left: auto; }
.nav a .nav-count {
  margin-left: auto; min-width: 16px; height: 16px; padding: 0 5px; border-radius: 99px;
  background: var(--warn); color: #1c1408; font-size: 11px; font-weight: 650;
  display: inline-flex; align-items: center; justify-content: center;
}
.side-label { margin: 12px 16px 4px; color: var(--subtle); font-size: 12px; }
.acct-tree { flex: 1 1 auto; min-height: 0; overflow: auto; padding: 0 8px 8px; display: grid; align-content: start; gap: 1px; }
.side-login {
  display: flex; align-items: center; gap: 9px; width: 100%; min-height: 40px; padding: 4px 8px; border: 0; border-radius: 8px;
  background: transparent; color: var(--muted); text-align: left; cursor: pointer;
}
.side-login:hover { background: var(--hover); color: var(--text); }
.side-login[aria-pressed="true"] { background: hsl(var(--on) / .08); }
.side-login .mark { width: 15px; height: 15px; color: var(--muted); }
.side-login .nm { flex: 1; min-width: 0; display: grid; line-height: 1.3; }
.side-login b { font-weight: 560; font-size: 12.5px; color: var(--text); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.side-login small { font-size: 11.5px; color: var(--subtle); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.side-login.needs small { color: var(--warn-ink); }
.side-pct { font-size: 11.5px; color: var(--subtle); font-variant-numeric: tabular-nums; }
.side-ring { width: 16px; height: 16px; flex: none; transform: rotate(-90deg); }
.side-ring circle { fill: none; stroke: hsl(var(--on) / .12); stroke-width: 3; }
.side-ring .fill { stroke: var(--info); stroke-linecap: round; }
.side-ring.needs .fill { stroke: var(--warn); }
.side-ring.room .fill, .side-ring.hot .fill { stroke: var(--good); }
.ldot { width: 8px; height: 8px; border-radius: 99px; flex: none; box-sizing: border-box; display: inline-block; }
.ldot.needs { background: var(--warn); }
.ldot.active { background: transparent; box-shadow: inset 0 0 0 1.6px var(--info); }
.ldot.room, .ldot.hot { background: var(--good); }
.ldot.quiet { background: transparent; box-shadow: inset 0 0 0 1.6px var(--subtle); }
.side-foot { flex: none; border-top: 1px solid var(--border); padding: 6px 0 8px; }
.foot-link {
  display: flex; align-items: center; gap: 8px; height: 30px; margin: 0 8px; padding: 0 8px; border-radius: 8px;
  color: var(--muted); text-decoration: none; font-weight: 520;
}
.foot-link:hover, .foot-link[aria-current="page"] { background: hsl(var(--on) / .08); color: var(--text); }
.pet-foot { display: flex; align-items: center; gap: 8px; padding: 2px 14px 6px; }
.pet-foot .pet { width: 36px; height: auto; flex: none; }
.pet-foot > span { display: grid; line-height: 1.25; min-width: 0; flex: 1; }
.pet-foot b { font-size: 12.5px; font-weight: 600; }
.pet-foot small { color: var(--subtle); font-size: 11.5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.pet-foot .btn { flex: none; }
/* The title, and the tabs of a place with more than one section. */
.top-title { display: flex; align-items: center; gap: 18px; min-width: 0; }
.subnav button { height: 26px; }
/* A place with tabs keeps its title bar to the tabs; the section's own controls lead the page. */
.page-tools { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }

/* Home: the wallpaper, the hop composer over its edge, then what needs you and the week. */
.home { max-width: 1120px; margin: 0 auto; display: grid; gap: 16px; }
.hero {
  position: relative; height: clamp(196px, 31vh, 290px); border-radius: 16px; overflow: hidden; isolation: isolate;
  background: radial-gradient(120% 140% at 80% 0%, hsl(228 34% 20%), hsl(230 26% 9%) 70%); border: 1px solid hsl(var(--on) / .07);
}
:root[data-theme="day"] .hero { background: radial-gradient(120% 140% at 80% 0%, #eef2f7, #e6e1d6 70%); }
.hero-art { position: absolute; inset: 0; z-index: 0; pointer-events: none; }
.hero-art #field { position: absolute; inset: 0; width: 100%; height: 100%; image-rendering: pixelated; }
.hero-scene { position: absolute; inset: 0; }
.hero::after { content: ""; position: absolute; inset: 0; z-index: 1; pointer-events: none; background: linear-gradient(100deg, rgba(0, 0, 0, .5), rgba(0, 0, 0, .12) 55%, transparent 75%); }
:root[data-theme="day"] .hero::after { background: linear-gradient(100deg, rgba(255, 255, 255, .7), rgba(255, 255, 255, .2) 55%, transparent 75%); }
.hero-copy { position: absolute; z-index: 2; left: 28px; top: 24px; right: 34%; display: grid; gap: 6px; }
.hero-date { margin: 0; color: var(--muted); font-size: 12.5px; font-weight: 560; text-shadow: var(--headline-shadow); }
.hero-title { margin: 0; font-size: 30px; font-weight: 660; letter-spacing: -.03em; line-height: 1.1; text-shadow: var(--headline-shadow); }
.hero .hsub, .hero .hnote { margin: 0; max-width: 470px; color: var(--text); opacity: .84; font-size: 13.5px; text-shadow: var(--headline-shadow); }
.hero .hnote { color: var(--warn-ink); opacity: 1; }
.hero-btn {
  position: absolute; z-index: 2; right: 14px; top: 14px; height: 28px; padding: 0 11px; border-radius: 8px; cursor: pointer;
  border: 1px solid hsl(var(--on) / .16); background: hsl(var(--off) / .32); color: var(--text); font-size: 12.5px; font-weight: 560;
  -webkit-backdrop-filter: blur(8px); backdrop-filter: blur(8px);
}
.hero-btn:hover { background: hsl(var(--off) / .5); }
.hcomposer {
  position: relative; z-index: 3; width: min(660px, calc(100% - 48px)); margin: -46px auto 0; overflow: visible;
  background: var(--panel); box-shadow: 0 18px 44px rgba(0, 0, 0, .34), inset 0 1px 0 hsl(var(--on) / .05);
}
:root[data-theme="day"] .hcomposer { box-shadow: 0 14px 36px rgba(0, 0, 0, .1); }
.hcomposer input {
  display: block; width: 100%; border: 0; background: transparent; outline: none;
  padding: 14px 14px 6px; font-size: 14px; color: var(--text);
}
.hcomposer input::placeholder { color: var(--subtle); }
.hcomposer-bar { display: flex; align-items: center; gap: 4px; padding: 6px 8px 8px; }
.hchip-wrap { position: relative; display: inline-flex; }
.hchip, .htext {
  height: 28px; padding: 0 8px; border: 0; border-radius: 8px; background: transparent; color: var(--muted); cursor: pointer; font-size: 12.5px;
}
.hchip { border: 1px solid var(--border); }
.hchip:hover, .htext:hover { background: var(--hover); color: var(--text); }
.hgo {
  margin-left: auto; width: 28px; height: 28px; border: 0; border-radius: 8px; background: var(--primary); color: var(--on-primary);
  display: grid; place-items: center; cursor: pointer;
}
.hpop {
  position: absolute; z-index: 6; top: calc(100% + 6px); left: 0; min-width: 200px; max-height: 240px; overflow: auto; padding: 4px;
  border-radius: 10px; border: 1px solid var(--border); background: var(--raised); box-shadow: 0 18px 50px rgba(0, 0, 0, .35);
}
.hpop button {
  display: flex; width: 100%; align-items: center; gap: 8px; height: 30px; padding: 0 8px; border: 0; border-radius: 6px;
  background: transparent; color: var(--text); text-align: left; cursor: pointer;
}
.hpop button small { margin-left: auto; color: var(--subtle); }
.hpop button.on, .hpop button:hover { background: var(--hover); }
.home-grid { display: grid; grid-template-columns: minmax(0, 1.2fr) minmax(0, 1fr); gap: 16px; align-items: start; margin-top: 4px; }
.card-head .count {
  display: inline-grid; place-items: center; min-width: 20px; height: 20px; padding: 0 6px; margin-right: auto; border-radius: 99px;
  background: hsl(var(--on) / .08); color: var(--muted); font-size: 11.5px; font-weight: 650; font-variant-numeric: tabular-nums;
}
.card-head .count.hot { background: color-mix(in srgb, var(--warn) 20%, transparent); color: var(--warn-ink); }
.card-head h2 + .hint { margin-right: auto; }
.alist { display: grid; }
.arow { display: flex; align-items: center; gap: 12px; padding: 12px 16px; }
.arow + .arow { border-top: 1px solid var(--border); }
.arow .ldot { align-self: flex-start; margin-top: 6px; }
.ldot.needs.bad { background: var(--bad); }
.arow-copy { flex: 1; min-width: 0; }
.arow-copy b { font-weight: 600; }
.arow-copy p { margin: 1px 0 0; color: var(--muted); font-size: 12.5px; }
.arow .btn { flex: none; }
.aclear { display: flex; align-items: center; gap: 10px; margin: 0; padding: 18px 16px; color: var(--muted); }
.aclear .icon { color: var(--good); }
.iu-list { display: grid; padding: 4px 0; }
.iu-row { display: grid; grid-template-columns: 16px minmax(0, 1fr) minmax(56px, 92px) 56px; align-items: center; gap: 10px; padding: 6px 16px; min-height: 44px; }
.iu-row .mark { color: var(--muted); }
.iu-main { display: grid; min-width: 0; padding: 0; border: 0; background: transparent; color: inherit; text-align: left; cursor: pointer; line-height: 1.3; }
.iu-main b { font-weight: 580; font-size: 13px; }
.iu-main span { color: var(--subtle); font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.iu-main:hover b { text-decoration: underline; text-underline-offset: 3px; text-decoration-color: hsl(var(--on) / .3); }
.iu-pct { justify-self: end; white-space: nowrap; font-size: 12.5px; color: var(--muted); font-variant-numeric: tabular-nums; }
.iu-pct.needs { color: var(--warn-ink); font-weight: 600; }
.iu-row .btn { justify-self: end; }
.section-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-top: 10px; }
.section-head h2 { margin: 0; font-size: 16px; font-weight: 620; letter-spacing: -.01em; }
.hstats { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; }
.hstat { display: grid; gap: 4px; padding: 14px 16px 15px; border-radius: 12px; background: var(--panel); border: 1px solid hsl(var(--on) / .06); box-shadow: inset 0 1px 0 hsl(var(--on) / .045); min-width: 0; }
.hstat-label { color: var(--muted); font-size: 12.5px; }
.hstat-value { font-size: 26px; font-weight: 640; letter-spacing: -.025em; line-height: 1.15; font-variant-numeric: tabular-nums; }
.hstat-foot { display: flex; gap: 6px; align-items: baseline; min-width: 0; color: var(--subtle); font-size: 12px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.hstat-foot .mono { font-size: 12px; font-weight: 600; }
.activity .card-head h2 .subtle { font-weight: 450; }
.activity-heat { padding: 12px 20px 8px; }
.hstreaks { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); border-top: 1px solid var(--border); }
.hstreak { display: grid; gap: 3px; padding: 14px 18px 16px; min-width: 0; }
.hstreak + .hstreak { border-left: 1px solid var(--border); }
.hstreak b { font-size: 18px; font-weight: 630; letter-spacing: -.015em; }
.hstreak .hstat-foot { white-space: normal; }

/* Limits: tool tabs, the pooled quota and its forecast, then every login by tool. */
.ptabs { display: flex; gap: 6px; flex-wrap: wrap; }
.ptabs button {
  display: inline-flex; align-items: center; gap: 7px; height: 30px; padding: 0 10px; border-radius: 99px; cursor: pointer;
  border: 1px solid var(--border); background: transparent; color: var(--muted); font-size: 12.5px; font-weight: 540;
}
.ptabs button:hover { color: var(--text); background: var(--hover); }
.ptabs button[aria-pressed="true"] { background: var(--primary); border-color: var(--primary); color: var(--on-primary); }
.ptabs .mark { width: 13px; height: 13px; }
.ptabs .n { color: inherit; opacity: .6; font-variant-numeric: tabular-nums; }
.qcard { overflow: hidden; }
.qhead { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; padding: 18px 20px 6px; flex-wrap: wrap; }
.qbig { display: grid; gap: 4px; }
.eyebrow { color: var(--muted); font-size: 12.5px; font-weight: 540; }
.qnum { display: flex; align-items: baseline; gap: 8px; flex-wrap: wrap; }
.qnum b { font-size: 40px; font-weight: 650; letter-spacing: -.035em; line-height: 1.05; font-variant-numeric: tabular-nums; }
.qnum.warn b { color: var(--warn-ink); }
.qnum.bad b { color: var(--bad); }
.qnum > span { color: var(--subtle); font-size: 18px; font-weight: 520; font-variant-numeric: tabular-nums; }
.qnum .qrate { margin-left: 6px; padding: 2px 8px; border-radius: 99px; background: hsl(var(--on) / .07); color: var(--muted); font-size: 12.5px; font-weight: 560; }
.qchart { padding: 6px 20px 0; }
.qchart .qline { fill: none; stroke: var(--text); stroke-width: 1.8; stroke-linejoin: round; }
.qchart .qline.ahead { stroke: var(--info); stroke-dasharray: 5 4; }
.qchart .qarea { fill: hsl(var(--on) / .07); }
.qchart .qarea.ahead { fill: color-mix(in srgb, var(--info) 9%, transparent); }
.qchart .qnow { stroke: hsl(var(--on) / .45); stroke-dasharray: 2 3; }
.qchart .qnow-label { fill: var(--muted); font: 600 11px var(--sans); }
.qchart .qreset { fill: var(--good); stroke: var(--panel); stroke-width: 2; }
.qchart .grid.day { stroke: hsl(var(--on) / .04); }
.qchart .qbar { fill: hsl(var(--on) / .55); }
.qchart .qbar:hover { fill: var(--text); }
.qfoot { display: flex; align-items: center; gap: 8px 20px; flex-wrap: wrap; padding: 10px 20px 14px; color: var(--muted); font-size: 12.5px; border-top: 1px solid hsl(var(--on) / .05); }
.qfact { display: inline-flex; align-items: center; gap: 6px; }
.qfact b { color: var(--text); font-weight: 600; }
.qfact.bad, .qfact.bad b { color: var(--bad); }
.qfact .icon { width: 14px; height: 14px; }
.qlegend { margin-left: auto; display: inline-flex; align-items: center; gap: 6px; color: var(--subtle); }
.qlegend i { display: inline-block; width: 16px; height: 0; border-top: 2px solid var(--text); margin-left: 8px; }
.qlegend i.dash { border-top: 2px dashed var(--info); }
.lgroup-head { display: flex; align-items: center; gap: 10px; padding: 10px 12px 10px 16px; border-bottom: 1px solid hsl(var(--on) / .05); min-height: 50px; }
.lgroup-head .mark { width: 16px; height: 16px; }
.lgroup-head h2 { margin: 0; font-size: 14px; font-weight: 600; }
.lgroup-head .count { color: var(--subtle); font-size: 12px; font-variant-numeric: tabular-nums; }
.lgroup-sum { color: var(--muted); font-size: 12.5px; }
.lgroup-sum b { color: var(--text); font-weight: 600; }
.lgroup-head .btn { margin-left: auto; }
.lrow { display: grid; grid-template-columns: minmax(170px, 1.1fr) minmax(220px, 1.7fr) minmax(96px, 128px) minmax(96px, max-content); gap: 6px 18px; align-items: center; }
.list > .lrow { padding: 12px 12px 12px 16px; }
.list > .lrow:hover { background: var(--hover); }
.lrow.active { background: hsl(var(--on) / .018); }
.lrow .row-actions { flex-wrap: nowrap; }
.lwins { display: grid; gap: 5px; min-width: 0; }
.lwin { display: grid; grid-template-columns: 92px minmax(60px, 1fr) 38px 52px; align-items: center; gap: 10px; font-size: 12px; }
.lwin-name { color: var(--muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.lwin-pct { text-align: right; font-variant-numeric: tabular-nums; color: var(--text); font-weight: 560; }
.lwin-foot { color: var(--subtle); font-variant-numeric: tabular-nums; white-space: nowrap; }
.lwin .progress { height: 5px; }
.lnote { margin: 0; color: var(--subtle); font-size: 12.5px; }
.loutlook { font-size: 12.5px; color: var(--text); font-weight: 560; font-variant-numeric: tabular-nums; }
.loutlook.warn { color: var(--warn-ink); }
.loutlook.bad { color: var(--bad); }
.loutlook.subtle { color: var(--subtle); font-weight: 500; }
details.setup summary { display: flex; align-items: center; gap: 10px; padding: 14px 16px; cursor: pointer; list-style: none; font-weight: 560; }
details.setup summary::-webkit-details-marker { display: none; }
details.setup summary .subtle { font-weight: 450; font-size: 12.5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0; }
details.setup[open] summary { border-bottom: 1px solid var(--border); }
.setup-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.setup-row .mark { margin-top: 2px; }
.statusbar {
  position: relative; grid-column: 1 / -1; grid-row: 2; display: flex; align-items: center; gap: 14px; padding: 0 12px;
  border-top: 1px solid var(--border); background: var(--sidebar); color: var(--muted); font-size: 11.5px;
  white-space: nowrap; overflow: hidden; min-width: 0;
}
.statusbar button, .statusbar a {
  display: inline-flex; align-items: center; gap: 6px; border: 0; background: transparent; color: inherit;
  padding: 0; height: 26px; text-decoration: none; cursor: pointer; min-width: 0;
}
.statusbar button:hover, .statusbar a:hover { color: var(--text); }
.statusbar .status-grow { flex: 1; }
.status-btn .icon { width: 12px; height: 12px; }
.status-btn.spin .icon { animation: turn 1s linear infinite; }
#read { overflow: hidden; text-overflow: ellipsis; }
.statusbar .meter { position: absolute; left: 0; right: 0; bottom: 0; height: 2px; background: transparent; }

@media (max-width: 1180px) {
  .usage-board { grid-template-columns: 1fr; }
  .usage-main { order: -1; }
  .chips { grid-template-columns: repeat(4, minmax(0, 1fr)); }
  .stats, .stats.three, .hstats { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .split, .split.wide-left, .home-grid { grid-template-columns: 1fr; }
  .hstreaks { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .hstreak:nth-child(3) { border-left: 0; }
  .hstreak:nth-child(n + 3) { border-top: 1px solid var(--border); }
  .lrow { grid-template-columns: minmax(0, 1fr) minmax(96px, max-content); }
  .lrow .lwins { grid-column: 1 / -1; grid-row: 2; }
  .lrow .loutlook { grid-column: 1; grid-row: 3; }
  .lrow .row-actions { grid-column: 2; grid-row: 1; }
  .tool-row { grid-template-columns: minmax(0, 1fr) minmax(0, 1.4fr); }
  .tool-row .row-actions { grid-column: 1 / -1; justify-content: flex-start; }
}
@media (max-width: 820px) {
  .shell { grid-template-columns: 1fr; grid-template-rows: auto minmax(240px, 1fr) auto; height: auto; min-height: 100vh; }
  body { overflow: auto; }
  .sidebar, .content, .statusbar { grid-column: 1; }
  .sidebar { grid-row: 1; border-right: 0; border-bottom: 1px solid var(--border); }
  .content { grid-row: 2; }
  .statusbar { grid-row: 3; }
  .nav { grid-auto-flow: column; overflow-x: auto; flex: none; min-height: auto; }
  .nav-label { margin: 0 4px 0 12px; align-self: center; white-space: nowrap; }
  .acct-tree, .side-label, .pet-foot { display: none; }
  .hero-copy { right: 24px; }
  .top-title { flex-wrap: wrap; gap: 8px; }
  .main { overflow: visible; }
  .stats, .limits, .account-row, .tool-row { grid-template-columns: 1fr; }
  .account-row .today { justify-items: start; text-align: left; }
  .account-row .row-actions { justify-content: flex-start; }
  .chips { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .top-actions { flex: 1; flex-wrap: wrap; }
  .hop kbd { display: none; }
  .settings-shell { grid-template-columns: 1fr; }
  .settings-nav { position: static; grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .kv { grid-template-columns: 1fr; gap: 2px; }
}
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { animation: none !important; transition: none !important; }
  /* A bar that can't travel would read as stuck part-way, so the words carry it alone. */
  .meter.unknown > span { display: none; }
}
@media (prefers-reduced-transparency: reduce) {
  .has-backdrop .card, .has-glass .tip, .has-glass .toast { -webkit-backdrop-filter: none; backdrop-filter: none; }
  .has-backdrop .card { background: hsl(var(--bg-base) / .98); }
}
"""##
}
