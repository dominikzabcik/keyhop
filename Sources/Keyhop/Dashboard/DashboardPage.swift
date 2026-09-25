import Foundation

/// The dashboard app: one page of HTML, CSS and JavaScript with no outside resources. Served live by
/// `keyhop dashboard`, or saved with its data inside by `keyhop insights --output`.
enum DashboardPage {
    static func render(boot: String?) -> String {
        // One symbol per tool, from the tool list itself, so a newly added tool always has its mark.
        let marks = Provider.allCases.map { provider in
            #"<symbol id="mark-\#(provider.rawValue)" viewBox="0 0 24 24"><path d="\#(ProviderMarks.path(for: provider))"/></symbol>"#
        }.joined(separator: "\n  ")
        let page = template
            .replacingOccurrences(of: "{{marks}}", with: marks)
            .replacingOccurrences(of: "{{icons}}", with: InterfaceIcons.symbols)
            .replacingOccurrences(of: "{{backdrop}}", with: Backdrop.script)
        // Inside a script element, "<" could close it early; JSON allows it escaped.
        let data = boot.map { $0.replacingOccurrences(of: "<", with: "\\u003c") } ?? "null"
        return page.replacingOccurrences(of: "{{boot}}", with: data)
    }

    private static let template = ##"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark">
<title>Keyhop</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='7' fill='%23171717'/%3E%3Cg fill='%23EBEBEB'%3E%3Crect x='3.3' y='3.3' width='8' height='26' rx='2'/%3E%3Crect x='12.8' y='12.3' width='8' height='8' rx='2'/%3E%3Crect x='21.3' y='1.3' width='8' height='8' rx='2'/%3E%3Crect x='21.3' y='22.7' width='8' height='8' rx='2'/%3E%3C/g%3E%3C/svg%3E">
<style>
:root {
  --bg: hsl(0 0% 9%);
  --sidebar: hsl(0 0% 7.2%);
  --panel: hsl(0 0% 10.6%);
  --raised: hsl(0 0% 13.5%);
  --hover: hsl(0 0% 100% / .05);
  --border: hsl(0 0% 100% / .08);
  --border-strong: hsl(0 0% 100% / .14);
  --text: hsl(0 0% 92%);
  --muted: hsl(0 0% 63%);
  --subtle: hsl(0 0% 53%);
  --faint: hsl(0 0% 100% / .08);
  --primary: hsl(0 0% 95%);
  --on-primary: hsl(0 0% 9%);
  --focus: hsl(211 92% 62%);
  --good: #5CC98A;
  --warn: #E3A64F;
  --bad: #EE7A69;
  --sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, "Segoe UI Variable Text", "Segoe UI", Roboto, Cantarell, "Noto Sans", sans-serif;
  --mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
  color-scheme: dark;
  /* Only the named content surfaces transition. The browser's implicit `root` snapshot includes
     the sidebar and cross-fades its old and new selection states over the moving thumb. */
  view-transition-name: none;
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
::-webkit-scrollbar-thumb { background: hsl(0 0% 100% / .12); border-radius: 99px; border: 2px solid transparent; background-clip: padding-box; }
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
.shell { display: grid; grid-template-columns: 236px minmax(0, 1fr); height: 100vh; }
.sidebar { display: flex; flex-direction: column; background: var(--sidebar); border-right: 1px solid var(--border); min-height: 0; }
.brand { display: flex; align-items: center; gap: 10px; height: 52px; padding: 0 18px; border-bottom: 1px solid var(--border); }
.brand svg { width: 17px; height: 17px; flex: none; }
.brand b { font-weight: 650; font-size: 14px; letter-spacing: .01em; }
.brand .badge { margin-left: auto; }
/* Keys drawn as keys: a cap with a lip along its bottom edge. */
kbd { display: inline-grid; place-items: center; min-width: 20px; height: 20px; padding: 0 5px; border-radius: 5px; background: hsl(0 0% 100% / .07); box-shadow: inset 0 -1.5px 0 hsl(0 0% 100% / .09); color: var(--muted); font: 600 11px var(--sans); letter-spacing: .02em; }
.nav { position: relative; isolation: isolate; display: grid; gap: 2px; padding: 12px 10px; }
.nav.has-thumb::before { content: ""; position: absolute; z-index: -1; left: 10px; right: 10px; top: 0; height: var(--nav-h); transform: translateY(var(--nav-y)); border-radius: 8px; background: hsl(0 0% 100% / .08); transition: transform .3s cubic-bezier(.3, .8, .25, 1); }
.nav.no-slide::before { transition: none; }
.nav.has-thumb a[aria-current="page"] { background: transparent; }
.nav a {
  display: flex; align-items: center; gap: 10px; height: 34px; padding: 0 10px; border-radius: 8px;
  color: hsl(0 0% 56%); text-decoration: none; font-weight: 520; transition: background .12s ease, color .12s ease;
}
.nav a:hover { background: var(--hover); color: var(--text); }
.nav a[aria-current="page"] { background: hsl(0 0% 100% / .08); color: var(--text); }
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

.content { position: relative; display: flex; flex-direction: column; min-width: 0; min-height: 0; }
/* The backdrop: an illustrated scene behind the content. Its motion is transform and opacity
   only, so it stays smooth. */
.backdrop { position: absolute; inset: 0; z-index: 0; overflow: hidden; pointer-events: none; transition: opacity .4s ease; }
.backdrop.scoped-out { opacity: 0 !important; }
.topbar { position: relative; z-index: 3; display: flex; align-items: center; justify-content: space-between; gap: 16px; min-height: 52px; padding: 10px 24px; border-bottom: 1px solid var(--border); flex: none; }
/* Nothing scrolls under the top bar, so over the Field it simply gets out of the way. */
.has-backdrop .topbar { background: transparent; border-bottom-color: transparent; }
.topbar h1 { margin: 0; font-size: 18px; font-weight: 600; letter-spacing: -.01em; line-height: 1.2; }
.top-actions { display: flex; align-items: center; justify-content: flex-end; gap: 8px; min-width: 0; }
.hop { display: inline-flex; align-items: center; gap: 8px; height: 32px; padding: 0 8px 0 11px; border: 1px solid hsl(0 0% 100% / .1); border-radius: 8px; background: hsl(0 0% 100% / .045); color: var(--text); font-weight: 560; white-space: nowrap; cursor: pointer; transition: background-color .14s ease, border-color .14s ease, transform .08s ease-out; }
.hop:hover { background: hsl(0 0% 100% / .08); border-color: hsl(0 0% 100% / .16); }
.hop:active { transform: scale(.97); }
/* The whole window's progress, along the bottom edge of the top bar. */
.topbar .meter { position: absolute; left: 24px; right: 24px; bottom: -2px; height: 3px; background: transparent; opacity: 0; transition: opacity .25s ease; }
.topbar .meter.on { opacity: 1; }
.toolbar { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; justify-content: flex-end; }
.main { position: relative; z-index: 1; flex: 1; overflow: auto; padding: 22px 24px 40px; }
.page { max-width: 1320px; margin: 0 auto; display: grid; gap: 16px; }
.lede { margin: 0 0 4px; color: var(--muted); }

/* Components */
.card { background: var(--panel); border: 1px solid hsl(0 0% 100% / .06); border-radius: 12px; min-width: 0; box-shadow: inset 0 1px 0 hsl(0 0% 100% / .045); }
/* Over a scene, panels are tinted sheets: the scene reads through them, softened just enough to keep text crisp. */
.has-backdrop .card { background: hsl(0 0% 9.5% / .64); border-color: hsl(0 0% 100% / .07); -webkit-backdrop-filter: blur(3px); backdrop-filter: blur(3px); }
/* In the Mac app the whole window can be glass: the desktop shows through, blurred, under one tint at
   the chosen window opacity. Panels, tabs and buttons turn into light washes over that glass, and
   scenes drop their own ground so only their artwork sits on it. */
.has-glass { --sidebar: hsl(0 0% 0% / .16); --panel: hsl(0 0% 100% / .035); --raised: hsl(0 0% 100% / .075); --border: hsl(0 0% 100% / .09); }
.has-glass body { background: transparent; }
.has-glass .shell { background: hsl(0 0% 9% / var(--glass, .85)); }
.has-glass .card { background: var(--panel); -webkit-backdrop-filter: none; backdrop-filter: none; }
.has-glass .bd-scene:not(.bd-picture) { background: none; }
/* Overlays float over live content, so they stay nearly solid. */
.has-glass .tip, .has-glass .toast { background: hsl(0 0% 12.5% / .95); -webkit-backdrop-filter: blur(20px); backdrop-filter: blur(20px); }
.has-glass select.field option { background: hsl(0 0% 13.5%); }.range { width: 180px; accent-color: hsl(0 0% 92%); }
/* Overview opens on today's figure, set large over the Field. */
.hero { position: relative; padding: 44px 4px 36px; display: grid; grid-template-columns: minmax(0, 1fr) auto; align-items: end; gap: 24px 40px; }
.hero-main { display: grid; gap: 10px; min-width: 0; }
.hero-hours { margin: 0; display: grid; gap: 8px; justify-items: start; }
.hero-hours figcaption { color: var(--subtle); font-size: 12px; }
.has-backdrop .hero-hours figcaption { text-shadow: 0 1px 12px hsl(0 0% 9% / .9); }
.notices { display: grid; border-radius: 12px; border: 1px solid hsl(36 72% 60% / .24); background: hsl(36 40% 12% / .55); box-shadow: inset 0 1px 0 hsl(36 72% 70% / .06); }
.notice-row { display: flex; align-items: center; gap: 12px; padding: 12px 14px; }
.notice-row + .notice-row { border-top: 1px solid hsl(36 72% 60% / .12); }
.notice-row > .icon { color: var(--warn); }
.notice-row > div { flex: 1; min-width: 0; }
.notice-row b { font-weight: 600; }
.notice-row p { margin: 0; color: var(--muted); }
/* While a refresh runs, a pixel runner hops along the bottom of the hero. */
.hero-run { position: absolute; left: 0; right: 0; bottom: 12px; height: 24px; opacity: 0; transition: opacity .3s ease; pointer-events: none; }
.hero-run.on { opacity: 1; }
.hero-figure { display: flex; align-items: baseline; gap: 14px; flex-wrap: wrap; margin: 0; font-weight: 400; }
.hero-figure .num { font-size: 56px; font-weight: 600; letter-spacing: -.03em; line-height: 1; font-variant-numeric: tabular-nums; }
.hero-figure .unit { font-size: 19px; color: var(--muted); font-weight: 520; }
.hero-line { margin: 0; color: var(--muted); font-size: 14px; }
/* A soft shadow right behind the words keeps them clear of bright dots, without a band behind them. */
.has-backdrop .hero-figure, .has-backdrop .hero-line { text-shadow: 0 1px 20px hsl(0 0% 9% / .95), 0 0 2px hsl(0 0% 9% / .8); }
.card-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 12px 16px; border-bottom: 1px solid hsl(0 0% 100% / .05); min-height: 50px; flex-wrap: wrap; }
.card-head h2 { margin: 0; font-size: 14px; font-weight: 560; display: flex; align-items: center; gap: 8px; }
.card-head .hint { color: var(--subtle); font-size: 12.5px; }
.card-body { padding: 16px; }
.split { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
.split.wide-left { grid-template-columns: minmax(0, 1.55fr) minmax(0, 1fr); }
.stats { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 16px; }
.stat { padding: 14px 16px 16px; }
.stat .label { color: var(--muted); font-size: 12.5px; display: flex; justify-content: space-between; gap: 8px; }
.stat .value { margin-top: 6px; font-size: 24px; font-weight: 600; letter-spacing: -.02em; line-height: 1.2; font-variant-numeric: tabular-nums; }
.stat .foot { margin-top: 4px; font-size: 12px; color: var(--subtle); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

.btn {
  display: inline-flex; align-items: center; justify-content: center; gap: 6px; height: 32px; padding: 0 12px;
  border-radius: 7px; border: 1px solid transparent; cursor: pointer; font-weight: 560; font-size: 13px; white-space: nowrap;
  background: var(--primary); color: var(--on-primary); transition: background .12s ease, border-color .12s ease, color .12s ease;
}
.btn:hover { background: hsl(0 0% 100%); }
.btn.secondary { background: var(--raised); color: var(--text); border-color: var(--border); }
.btn.secondary:hover { background: hsl(0 0% 16%); border-color: var(--border-strong); }
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
  background: hsl(0 0% 100% / .07); color: var(--muted); font-size: 11.5px; font-weight: 560; white-space: nowrap;
}
.badge.live { color: hsl(145 28% 72%); background: hsl(145 30% 50% / .1); }
.badge.sample { color: var(--warn); background: hsl(36 72% 60% / .1); }

.tabs { position: relative; isolation: isolate; display: inline-flex; padding: 3px; gap: 2px; border-radius: 8px; background: var(--raised); border: 1px solid var(--border); }
/* The pressed option rides a thumb that slides to the next one; without it, the option keeps its own fill. */
.tabs.has-thumb::before { content: ""; position: absolute; z-index: -1; top: 3px; bottom: 3px; left: 0; width: var(--thumb-w); transform: translateX(var(--thumb-x)); border-radius: 5px; background: hsl(0 0% 100% / .1); box-shadow: inset 0 1px 0 hsl(0 0% 100% / .06); transition: transform .28s cubic-bezier(.3, .8, .25, 1), width .28s cubic-bezier(.3, .8, .25, 1); }
.tabs.no-slide::before { transition: none; }
.tabs.has-thumb button[aria-pressed="true"] { background: transparent; }
.tabs button { height: 26px; padding: 0 10px; border: 0; border-radius: 5px; background: transparent; color: var(--muted); cursor: pointer; font-size: 12.5px; font-weight: 540; transition: color .18s ease; }
.tabs button:hover { color: var(--text); }
.tabs button[aria-pressed="true"] { background: hsl(0 0% 100% / .1); color: var(--text); }
.tabs button:disabled { opacity: .4; cursor: default; }

.field {
  height: 32px; width: 100%; padding: 0 10px; border-radius: 7px; border: 1px solid var(--border-strong);
  background: transparent; color: var(--text); transition: border-color .12s ease;
}
.field:hover { border-color: hsl(0 0% 100% / .22); }
.field::placeholder { color: var(--subtle); }
select.field { appearance: none; padding-right: 28px; background-image: linear-gradient(45deg, transparent 50%, var(--muted) 50%), linear-gradient(135deg, var(--muted) 50%, transparent 50%); background-position: calc(100% - 15px) 14px, calc(100% - 11px) 14px; background-size: 4px 4px; background-repeat: no-repeat; }
select.field option { background: var(--raised); }
.toolbar select.field { width: auto; height: 32px; }
.range-pick { position: relative; }
.range-button { display: inline-flex; align-items: center; gap: 8px; height: 32px; padding: 0 10px 0 12px; border-radius: 7px; border: 1px solid var(--border-strong); background: var(--raised); color: var(--text); font: inherit; font-size: 12.5px; font-weight: 560; cursor: pointer; white-space: nowrap; }
.range-button:hover { border-color: hsl(0 0% 100% / .22); }
.range-button svg { width: 10px; height: 10px; color: var(--muted); transition: transform .16s ease; }
.range-button[aria-expanded="true"] svg { transform: rotate(180deg); }
.range-menu { position: absolute; top: calc(100% + 6px); left: 0; z-index: 30; width: 268px; padding: 6px; border-radius: 10px; border: 1px solid var(--border-strong); background: hsl(0 0% 12.5%); box-shadow: 0 8px 20px -10px rgba(0, 0, 0, .6); }
.range-list { display: grid; grid-template-columns: 1fr 1fr; gap: 2px; }
.range-list button { height: 30px; padding: 0 10px; border: 0; border-radius: 6px; background: transparent; color: var(--muted); font: inherit; font-size: 12.5px; text-align: left; cursor: pointer; }
.range-list button:hover { color: var(--text); background: hsl(0 0% 100% / .05); }
.range-list button[aria-checked="true"] { color: var(--text); background: hsl(0 0% 100% / .1); font-weight: 560; }
.range-dates { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 6px; padding: 10px 4px 4px; border-top: 1px solid var(--border); }
.range-dates label { display: grid; gap: 4px; font-size: 11.5px; color: var(--muted); }
.range-dates .field { height: 30px; padding: 0 8px; font-size: 12.5px; color-scheme: dark; }
.range-dates .btn { grid-column: 1 / -1; justify-content: center; }

.progress { position: relative; height: 6px; border-radius: 99px; background: var(--faint); overflow: visible; }
.progress > span { position: absolute; left: 0; top: 0; bottom: 0; border-radius: inherit; background: var(--text); transition: width .5s ease; }
.progress.warn > span { background: var(--warn); }
.progress.bad > span { background: var(--bad); }
.progress > i { position: absolute; top: -3px; bottom: -3px; width: 2px; margin-left: -1px; border-radius: 1px; background: hsl(0 0% 100% / .45); }

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
.dots { display: block; max-width: 100%; height: auto; }
.dots circle { fill: var(--faint); }
.dots circle.on { fill: hsl(0 0% 100% / .62); }
.dots circle.now { fill: var(--text); }
.dots text { fill: var(--subtle); font: 10.5px var(--mono); }

/* Accounts */
.group { display: grid; gap: 10px; }
.group-head { display: flex; align-items: center; gap: 10px; }
.group-head .mark { width: 18px; height: 18px; fill: var(--text); }
.group-head h2 { margin: 0; font-size: 16px; font-weight: 600; letter-spacing: -.01em; }
.group-head .count { color: var(--subtle); font-family: var(--mono); font-size: 12px; }
.group-head .btn { margin-left: auto; }
/* Fixed outer columns, so every row's limits and figures line up whatever its buttons are. */
.account-row { display: grid; grid-template-columns: minmax(220px, 1.1fr) minmax(280px, 1.6fr) 150px 132px; gap: 20px; align-items: center; }
.account-row .row-actions { flex-wrap: nowrap; }
.account-name { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.account-meta { margin-top: 3px; color: var(--subtle); font-size: 12.5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.in-use { display: inline-flex; align-items: center; height: 20px; padding: 0 8px; border-radius: 6px; background: hsl(0 0% 100% / .1); color: var(--text); font-size: 11.5px; font-weight: 600; }
.account-row.active { background: hsl(0 0% 100% / .018); }
.account-row .today { display: grid; gap: 1px; font-family: var(--sans); }
.account-row .today b { font-size: 16px; font-weight: 600; letter-spacing: -.01em; color: var(--text); line-height: 1.3; font-variant-numeric: tabular-nums; }
.account-row .today span { color: var(--subtle); font-size: 12px; }
.menu-anchor { position: relative; display: inline-flex; }
.btn.icon-only { width: 28px; padding: 0; }
.btn.icon-only .icon { width: 16px; height: 16px; }
.row-menu { position: absolute; right: 0; top: calc(100% + 6px); z-index: 20; min-width: 190px; padding: 5px; display: grid; gap: 2px; border-radius: 10px; border: 1px solid var(--border-strong); background: hsl(0 0% 12.5%); box-shadow: 0 8px 20px -10px rgba(0, 0, 0, .6); animation: menu-in .14s cubic-bezier(.2, .8, .2, 1); }
.row-menu button { height: 30px; padding: 0 10px; border: 0; border-radius: 6px; background: transparent; color: var(--text); font: inherit; font-size: 13px; text-align: left; cursor: pointer; }
.row-menu button:hover { background: hsl(0 0% 100% / .06); }
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
.legend-item:hover { color: var(--text); background: hsl(0 0% 100% / .04); }
.legend-item[aria-pressed="false"] { opacity: .45; }
.legend-item[aria-pressed="false"] .swatch { background: transparent !important; box-shadow: inset 0 0 0 1.5px var(--subtle); }
.swatch { width: 8px; height: 8px; border-radius: 2px; flex: none; }
.chart { overflow-x: auto; }
.chart svg { display: block; }
.chart .grid { stroke: hsl(0 0% 100% / .06); }
.chart .base { stroke: hsl(0 0% 100% / .16); }
.chart .axis { fill: var(--subtle); font: 11px var(--mono); }
.chart .hit { fill: transparent; }
.chart .hit:hover { fill: hsl(0 0% 100% / .03); }
.chart .col { transition: opacity .18s ease; }
.chart svg[data-hover] .col { opacity: .4; }
.chart svg[data-hover] .col.on { opacity: 1; }
.heat rect[data-action] { cursor: pointer; }
.heat rect[data-action]:hover { stroke: hsl(0 0% 100% / .7); stroke-width: 1.2; }
::view-transition-group(usage-chart) { animation-duration: .24s; }
.heat rect.l0 { fill: hsl(0 0% 100% / .05); }
.heat rect.l1 { fill: hsl(0 0% 100% / .18); }
.heat rect.l2 { fill: hsl(0 0% 100% / .36); }
.heat rect.l3 { fill: hsl(0 0% 100% / .6); }
.heat rect.l4 { fill: hsl(0 0% 100% / .9); }
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
.m1 { background: hsl(0 0% 100% / .9); } .m2 { background: hsl(0 0% 100% / .55); } .m3 { background: hsl(0 0% 100% / .3); } .m4 { background: hsl(0 0% 100% / .18); }
.m5 { background: hsl(0 0% 100% / .1); }
.table { width: 100%; border-collapse: collapse; }
.table th { text-align: left; font-weight: 500; color: var(--subtle); font-size: 12px; padding: 10px 16px; border-bottom: 1px solid var(--border); }
.table td { padding: 10px 16px; border-bottom: 1px solid hsl(0 0% 100% / .045); vertical-align: middle; font-variant-numeric: tabular-nums; }
.table tr:last-child td { border-bottom: 0; }
.table tbody tr:hover td { background: hsl(0 0% 100% / .02); }
.table tbody tr.clickable { cursor: pointer; }
.table .right { text-align: right; }
.table .bar-cell { width: 34%; }
.cell-name { display: flex; align-items: center; gap: 8px; min-width: 0; }
.cell-name span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
/* Usage: the total, the quick figures, the ranking and the breakdown. */
.usage-top { display: grid; grid-template-columns: minmax(0, 1.75fr) minmax(300px, 1fr); gap: 16px; align-items: stretch; }
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
.tile { display: grid; gap: 6px; align-content: start; padding: 11px 12px 12px; border-radius: 10px; border: 1px solid hsl(0 0% 100% / .055); background: hsl(0 0% 100% / .022); color: var(--text); text-align: left; font: inherit; min-width: 0; }
button.tile { cursor: pointer; transition: background .14s ease, border-color .14s ease; }
button.tile:hover { background: hsl(0 0% 100% / .05); border-color: hsl(0 0% 100% / .1); }
.tile-name { display: flex; align-items: center; gap: 8px; min-width: 0; font-size: 12.5px; color: var(--muted); }
.tile-name > span:last-child { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.tile-name .mark { width: 14px; height: 14px; fill: var(--text); }
.tile-share { font-weight: 600; font-size: 20px; letter-spacing: -.02em; line-height: 1.15; font-variant-numeric: tabular-nums; }
.tile-foot { display: flex; align-items: center; gap: 6px; color: var(--subtle); font-size: 11.5px; font-variant-numeric: tabular-nums; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.tile-foot .swatch { width: 6px; height: 6px; border-radius: 50%; }
.summary-card { padding: 16px; display: grid; gap: 16px; align-content: start; }
.chips { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; }
.chip { display: grid; gap: 2px; padding: 10px 12px; border-radius: 10px; background: hsl(0 0% 100% / .03); }
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
.ranked-track span { display: block; height: 100%; border-radius: inherit; background: hsl(0 0% 100% / .55); }
.summary-foot { display: flex; justify-content: space-between; gap: 12px; margin-top: auto; padding-top: 12px; border-top: 1px solid hsl(0 0% 100% / .05); color: var(--subtle); font-size: 12px; }
.chart-body { display: grid; gap: 14px; }
.table-wrap { overflow-x: auto; }
.table.data th, .table.data td { padding-left: 14px; padding-right: 14px; }
.table .strong { color: var(--text); font-weight: 600; }
.table td.mono { color: var(--muted); }
.table td.mono.strong { color: var(--text); }
.place-cell { width: 36px; text-align: center; }
.table-more { display: flex; justify-content: center; padding: 10px; border-top: 1px solid hsl(0 0% 100% / .045); }

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
.tier-master { --tier: hsl(0 0% 95%); }
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
.table tr.me td { background: hsl(0 0% 100% / .035); }
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
.settings-nav button[aria-current="page"] { background: hsl(0 0% 100% / .08); color: var(--text); }
.settings-pane { display: grid; gap: 16px; min-width: 0; }
.settings-intro { padding: 4px 2px 2px; }
.settings-intro h2 { margin: 0; font-size: 17px; font-weight: 600; letter-spacing: -.01em; }
.settings-intro p { max-width: 62ch; margin: 4px 0 0; color: var(--muted); }
.update-status { display: inline-flex; align-items: center; gap: 8px; color: var(--muted); }
.update-status .ring { width: 12px; height: 12px; border: 1.5px solid currentColor; border-right-color: transparent; border-radius: 50%; animation: turn .8s linear infinite; }

/* Jump to */
#palette { position: fixed; inset: 0; z-index: 40; }
.palette-scrim { position: absolute; inset: 0; background: hsl(0 0% 4% / .55); animation: fade-in .14s ease; }
.palette { position: absolute; left: 50%; top: 14vh; width: min(560px, calc(100vw - 32px)); transform: translateX(-50%); display: grid; grid-template-rows: auto minmax(0, 1fr) auto; max-height: min(520px, 72vh);
  border-radius: 14px; border: 1px solid hsl(0 0% 100% / .1); background: hsl(0 0% 11.5%); box-shadow: inset 0 1px 0 hsl(0 0% 100% / .06), 0 12px 24px -14px rgba(0, 0, 0, .75); animation: palette-in .16s cubic-bezier(.2, .8, .2, 1); overflow: hidden; }
@keyframes fade-in { from { opacity: 0; } }
@keyframes palette-in { from { opacity: 0; transform: translateX(-50%) translateY(-6px) scale(.985); } }
.palette-search { display: flex; align-items: center; gap: 10px; padding: 0 16px; height: 52px; border-bottom: 1px solid hsl(0 0% 100% / .06); color: var(--muted); }
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
.palette-item[aria-selected="true"] { background: hsl(0 0% 100% / .07); }
.palette-dot { width: 15px; display: grid; place-items: center; }
.palette-dot::before { content: ""; width: 5px; height: 5px; border-radius: 50%; background: hsl(0 0% 100% / .28); }
.palette-empty { margin: 0; padding: 18px 12px; color: var(--muted); }
.palette-foot { display: flex; gap: 16px; padding: 10px 16px; border-top: 1px solid hsl(0 0% 100% / .06); color: var(--subtle); font-size: 12px; }
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
  position: fixed; right: 20px; bottom: 20px; z-index: 30; max-width: min(460px, calc(100vw - 40px)); padding: 12px 14px;
  background: var(--raised); border: 1px solid var(--border-strong); border-radius: 10px; font-size: 13px;
  box-shadow: 0 10px 24px -12px rgba(0, 0, 0, .7); transition: transform .25s ease, opacity .25s ease;
}
.toast.away { transform: translateY(12px); opacity: 0; pointer-events: none; }
.toast.error { border-color: hsl(8 80% 67% / .45); }

@media (max-width: 1180px) {
  .hero { grid-template-columns: 1fr; }
  .usage-top { grid-template-columns: 1fr; }
  .chips { grid-template-columns: repeat(4, minmax(0, 1fr)); }
  .stats { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .split, .split.wide-left { grid-template-columns: 1fr; }
  .account-row { grid-template-columns: minmax(0, 1fr) minmax(0, 1.3fr); }
  .account-row .today { display: none; }
  .account-row .row-actions { grid-column: 1 / -1; justify-content: flex-start; }
  .tool-row { grid-template-columns: minmax(0, 1fr) minmax(0, 1.4fr); }
  .tool-row .row-actions { grid-column: 1 / -1; justify-content: flex-start; }
}
@media (max-width: 820px) {
  .shell { grid-template-columns: 1fr; grid-template-rows: auto 1fr; }
  body { overflow: auto; }
  .shell { height: auto; min-height: 100vh; }
  .sidebar { border-right: 0; border-bottom: 1px solid var(--border); }
  .nav { grid-auto-flow: column; overflow-x: auto; }
  .sidebar-foot { display: none; }
  .main { overflow: visible; }
  .stats, .limits, .account-row, .tool-row { grid-template-columns: 1fr; }
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
  .has-backdrop .card { background: hsl(0 0% 10% / .98); }
}
</style>
</head>
<body>
<button class="skip-link" type="button" data-action="skip-content">Skip to content</button>
<svg width="0" height="0" style="position:absolute" aria-hidden="true">
  {{marks}}
  {{icons}}
</svg>

<div class="shell">
  <aside class="sidebar">
    <div class="brand">
      <svg viewBox="0 0 24 24" aria-hidden="true"><g fill="#EBEBEB"><rect x="2.5" y="2.5" width="6" height="19.5" rx="1.5"/><rect x="9.6" y="9.2" width="6" height="6" rx="1.5"/><rect x="16" y="1" width="6" height="6" rx="1.5"/><rect x="16" y="17" width="6" height="6" rx="1.5"/></g></svg>
      <b>Keyhop</b>
      <span id="mode"></span>
    </div>
    <nav class="nav" id="nav" aria-label="Sections">
      <a href="#overview" data-section="overview"><svg><use href="#i-overview"/></svg>Overview</a>
      <a href="#accounts" data-section="accounts"><svg><use href="#i-accounts"/></svg>Accounts</a>
      <a href="#usage" data-section="usage"><svg><use href="#i-usage"/></svg>Usage</a>
      <a href="#budgets" data-section="budgets"><svg><use href="#i-budgets"/></svg>Budgets</a>
      <a href="#leaderboard" data-section="leaderboard" hidden><svg><use href="#i-leaderboard"/></svg>Leaderboard</a>
      <a href="#settings" data-section="settings"><svg><use href="#i-settings"/></svg>Settings</a>
    </nav>
    <div class="sidebar-foot">
      <button class="foot-row" id="refresh" data-action="refresh"><svg class="icon"><use href="#i-refresh"/></svg><span style="flex:1"><b>Refresh</b><small id="read">Limits not read yet</small><span class="meter" id="foot-meter" hidden><span></span></span></span></button>
    </div>
  </aside>
  <div class="content">
    <div class="backdrop" id="backdrop" aria-hidden="true"></div>
    <header class="topbar"><h1 id="title">Overview</h1><div class="top-actions"><div class="toolbar" id="toolbar"></div><button class="hop" type="button" data-action="palette" aria-keyshortcuts="Meta+K Control+K" aria-haspopup="dialog" aria-controls="palette"><svg class="icon" aria-hidden="true"><use href="#i-hop"/></svg><span>Hop</span><kbd id="hop-key">⌘K</kbd></button></div><div class="meter" id="top-meter" role="progressbar" aria-label="Keyhop is reading" aria-hidden="true"><span></span></div></header>
    <main class="main" id="main" tabindex="-1" aria-busy="true"><div class="page"><p class="lede busy" role="status"><span class="pulse" aria-hidden="true"><i></i><i></i><i></i></span>Reading your accounts…</p></div></main>
  </div>
</div>
<div class="tip" id="tip" hidden></div>
<div id="palette" hidden></div>
<div class="toast away" id="toast" role="status" aria-live="polite"></div>
<script>{{backdrop}}</script>
<script id="boot" type="application/json">{{boot}}</script>
<script>
(() => {
  "use strict";
  const SECTIONS = ["overview", "accounts", "usage", "budgets", "leaderboard", "settings"];
  const TITLES = { overview: "Overview", accounts: "Accounts", usage: "Usage", budgets: "Budgets", leaderboard: "Leaderboard", settings: "Settings" };
  const $ = (selector, root = document) => root.querySelector(selector);
  const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  const store = {
    get(key) { try { return sessionStorage.getItem(key); } catch { return null; } },
    set(key, value) { try { sessionStorage.setItem(key, value); } catch {} },
  };

  const boot = JSON.parse($("#boot").textContent || "null");
  const isStatic = !!boot;
  const params = new URLSearchParams(location.hash.slice(1));
  if (params.get("w") === "mac") document.documentElement.classList.add("mac-window");
  let token = params.get("k") || store.get("keyhop-token");
  if (params.get("k")) store.set("keyhop-token", token);
  const wanted = params.get("s") || location.hash.slice(1);
  const ui = {
    section: SECTIONS.includes(wanted) ? wanted : (boot?.section || "overview"),
    menu: null, hidden: { account: [], tool: [], model: [] },
    range: "week", rangeOpen: false, metric: "tokens", tool: "all", group: "account", breakdown: "periods", allPeriods: false,
    boardPeriod: "week", boardMetric: "tokens", boardTeam: "",
    editing: null, confirming: null, budgetEdit: null, offline: null,
    settingsPane: "general", checkingUpdate: false,
    pending: new Map(), loadingUsage: 0,
  };
  history.replaceState(null, "", "#" + ui.section);
  const data = { state: boot?.state || null, usage: {}, usageErrors: {}, doctor: null, update: null, updateError: null };
  if (isStatic) for (const [range, doc] of Object.entries(boot.usage || {})) data.usage[range + ":all"] = doc;

  // MARK: Formatting

  const fmt = {
    tokens(n) {
      const value = Math.abs(n || 0);
      const trim = (x, s) => { const t = x >= 100 ? x.toFixed(0) : x.toFixed(1); return (t.endsWith(".0") ? t.slice(0, -2) : t) + s; };
      return value >= 1e9 ? trim(n / 1e9, "B") : value >= 1e6 ? trim(n / 1e6, "M") : value >= 1e3 ? trim(n / 1e3, "K") : String(Math.round(n || 0));
    },
    usd(amount) {
      const a = amount || 0;
      return a >= 1000 ? "$" + Math.round(a).toLocaleString("en-US") : a >= 100 ? "$" + a.toFixed(0) : "$" + a.toFixed(2);
    },
    count(n) { return Math.round(n || 0).toLocaleString("en-US"); },
    relative(date) {
      const s = Math.round((Date.now() - new Date(date)) / 1000);
      const formatter = new Intl.RelativeTimeFormat(undefined, { numeric: "auto", style: "narrow" });
      if (s < 60) return formatter.format(0, "second");
      if (s < 3600) return formatter.format(-Math.floor(s / 60), "minute");
      if (s < 86400) return formatter.format(-Math.floor(s / 3600), "hour");
      return formatter.format(-Math.floor(s / 86400), "day");
    },
    until(date) {
      const s = Math.max(0, Math.round((new Date(date) - Date.now()) / 1000));
      const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
      return d ? `${d}d ${h}h` : h ? `${h}h ${m}m` : `${m}m`;
    },
    clock(date) { return new Intl.DateTimeFormat(undefined, { hour: "2-digit", minute: "2-digit" }).format(new Date(date)); },
    day(date, options) { return new Intl.DateTimeFormat(undefined, options).format(new Date(date)); },
    change(now, before) {
      if (!before) return "";
      const pct = Math.round(((now - before) / before) * 100);
      // Past ten times as much, a percentage stops meaning anything.
      if (pct >= 900) return `<span class="mono up">${Math.round(now / before)}×</span>`;
      return pct === 0 ? `<span class="mono subtle">0%</span>` : `<span class="mono ${pct > 0 ? "up" : "down"}">${pct > 0 ? "+" : ""}${pct}%</span>`;
    },
  };
  const windowName = (label) => ({ "5h": "5-hour", "Week": "Weekly", "Opus": "Opus weekly", "Sonnet": "Sonnet weekly", "Auto": "Auto", "API": "API", "Plan": "Plan" })[label] || label;
  const mark = (tool) => `<svg class="mark" aria-hidden="true"><use href="#mark-${esc(tool)}"/></svg>`;
  // Every wait looks the same: the three-dot pulse, then what is being read. The words are always
  // there; only the dots move.
  const busy = (text, cls = "empty-inline") => `<p class="${cls} busy" role="status"><span class="pulse" aria-hidden="true"><i></i><i></i><i></i></span>${text}</p>`;
  // A wait that can say how far it has got: the step Keyhop is on, a count and a bar, updated in
  // place while the step runs. Before the first report it reads like any other wait.
  const loading = (text, cls = "empty-inline") => `<div class="loading ${cls === "empty" ? "empty" : ""}" data-loading="${esc(text)}">${loadingInner(text)}</div>`;
  function loadingInner(text) {
    const step = data.state?.activity;
    const title = step ? step.title : text;
    const count = step?.count ? `<span class="count">${esc(step.count)}</span>` : "";
    const hints = {
      history: "The first read goes through every log on this computer. After that, only what is new.",
      repositories: "The first index reads every repository you have. After that, only the ones that changed.",
    };
    const hint = hints[step?.step] ? `<small>${hints[step.step]}</small>` : step?.detail ? `<small>${esc(step.detail)}</small>` : "";
    const width = step?.fraction != null ? `style="width:${(step.fraction * 100).toFixed(1)}%"` : "";
    return `<p class="busy" role="status"><span class="pulse" aria-hidden="true"><i></i><i></i><i></i></span><b>${esc(title)}</b>${count}</p>
      <div class="meter${step?.fraction != null ? "" : " unknown"}" role="progressbar" aria-label="${esc(title)}" ${step?.fraction != null ? `aria-valuemin="0" aria-valuemax="100" aria-valuenow="${Math.round(step.fraction * 100)}"` : ""}><span ${width}></span></div>${hint}`;
  }
  const icon = (name) => `<svg class="icon" aria-hidden="true"><use href="#i-${name}"/></svg>`;
  const maxUsed = (account) => Math.max(0, ...(account.limits || []).map((l) => l.usedPercent));
  const toolName = (id) => (data.state?.status.tools.find((t) => t.id === id) || {}).name || id;

  // MARK: Data

  async function api(path, body) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 30_000);
    const init = { method: body === undefined ? "GET" : "POST", headers: { Authorization: "Bearer " + token }, signal: controller.signal };
    if (body !== undefined) { init.headers["Content-Type"] = "application/json"; init.body = JSON.stringify(body); }
    let response;
    try {
      response = await fetch(path, init);
    } catch (error) {
      if (error.name === "AbortError") throw new Error("Keyhop took too long to answer. Try again.");
      throw new Error("Keyhop isn't running anymore. Open it again from the tray or with keyhop dashboard.");
    } finally {
      clearTimeout(timeout);
    }
    let payload = {};
    try { payload = await response.json(); } catch {}
    if (!response.ok) throw new Error(payload.error || `Keyhop answered ${response.status}.`);
    return payload;
  }

  async function loadState() {
    if (isStatic) return;
    data.state = await api("/api/state");
    ui.offline = null;
    for (const message of data.state.messages || []) toast(message);
  }

  async function loadUsage(range, tool = "all") {
    const key = `${range}:${tool}`;
    if (isStatic) return data.usage[key] || data.usage[`${range}:all`];
    // Only a first read shows a wait: after that the last figures stay up while new ones come in.
    const first = !data.usage[key];
    if (first) { ui.loadingUsage = (ui.loadingUsage || 0) + 1; watchActivity(); }
    try {
      data.usage[key] = await api(`/api/usage?range=${encodeURIComponent(range)}&tool=${encodeURIComponent(tool)}`);
      delete data.usageErrors[key];
    } catch (error) {
      data.usageErrors[key] = error.message;
      if (!data.usage[key]) throw error;
    } finally {
      if (first) ui.loadingUsage -= 1;
    }
    return data.usage[key];
  }

  // The providers' status pages are read on their own, so a slow page never holds Overview up.
  // Read again at most every two minutes; Keyhop caches each page for five.
  let servicesLoading = false;
  function loadServices() {
    if (isStatic || servicesLoading || (data.servicesAt && Date.now() - data.servicesAt < 120_000)) return;
    servicesLoading = true;
    api("/api/services")
      .then((list) => { data.services = list; data.servicesAt = Date.now(); if (ui.section === "overview") render(); })
      .catch(() => {})
      .finally(() => { servicesLoading = false; });
  }

  // Release checks have their own state. They never borrow the limits progress bar or make the
  // rest of the window look busy.
  async function loadUpdate(force = false) {
    if (isStatic || ui.checkingUpdate || (!force && (data.update || data.updateError))) return;
    ui.checkingUpdate = true;
    data.updateError = null;
    if (ui.section === "settings") render();
    try {
      data.update = await api("/api/update");
    } catch (error) {
      data.updateError = error.message;
    } finally {
      ui.checkingUpdate = false;
      if (ui.section === "settings") render();
    }
  }

  async function loadSection() {
    try {
      if (ui.section === "overview") { loadServices(); await Promise.all([loadUsage("today"), loadUsage("week")]); }
      if (ui.section === "usage") await loadUsage(ui.range, ui.tool);
      if (ui.section === "budgets") await loadUsage("month");
      if (ui.section === "leaderboard" && !isStatic && data.state?.cloud?.linked) {
        try {
          data.board = await api(`/api/cloud/leaderboard?period=${ui.boardPeriod}&metric=${ui.boardMetric}&team=${encodeURIComponent(ui.boardTeam)}`);
          data.boardError = null;
        } catch (error) {
          data.boardError = error.message;
        }
      }
      if (ui.section === "settings" && !isStatic) {
        const doctor = api("/api/doctor");
        loadUpdate();
        data.doctor = await doctor;
      }
    } catch (error) {
      ui.offline = error.message;
    }
    applyBackdrop();
  }

  // MARK: Shell

  // MARK: Motion

  // Motion only ever carries a change the page already shows. Every value is written into the
  // markup first, then eased there from where it was, so a skipped, throttled or reduced animation
  // leaves the page right, never blank or half-way.
  const still = matchMedia("(prefers-reduced-motion: reduce)");
  const memory = new Map();
  const ease = (t) => 1 - Math.pow(1 - t, 3);
  const FORMATS = {
    count: fmt.count,
    tokens: fmt.tokens,
    usd: fmt.usd,
    usdExact: (v) => "$" + (v || 0).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 }),
    pct: (v) => (v > 0 && v < 1 ? "<1%" : `${Math.round(v)}%`),
  };

  // Numbers count from their last value to the new one; on first sight, marked ones count up.
  function countNumbers(root) {
    for (const el of root.querySelectorAll("[data-count]")) {
      const key = "n:" + el.dataset.countKey, to = +el.dataset.count, final = el.textContent;
      const from = memory.has(key) ? memory.get(key) : el.hasAttribute("data-count-intro") ? to * 0.35 : to;
      memory.set(key, to);
      if (still.matches || !isFinite(from) || !isFinite(to) || from === to) continue;
      const format = FORMATS[el.dataset.format] || fmt.count;
      const began = performance.now(), length = 760;
      const frame = (now) => {
        if (!el.isConnected) return;
        const t = Math.min(1, (now - began) / length);
        el.textContent = t < 1 ? format(from + (to - from) * ease(t)) : final;
        if (t < 1) requestAnimationFrame(frame);
      };
      requestAnimationFrame(frame);
      // Whatever happens to the frames, the exact value is back when the count should be done.
      setTimeout(() => { if (el.isConnected) el.textContent = final; }, length + 240);
    }
  }

  // Bars grow from their last length to the new one, and from nothing the first time.
  function growBars(root) {
    const grown = [];
    for (const el of root.querySelectorAll("[data-grow]")) {
      const key = "g:" + el.dataset.grow, prop = el.dataset.growProp || "width";
      const to = el.style[prop];
      const from = memory.has(key) ? memory.get(key) : prop === "flexGrow" ? "0" : "0%";
      memory.set(key, to);
      if (still.matches || from === to) continue;
      el.style.transition = "none";
      el.style[prop] = from;
      grown.push([el, prop, to]);
    }
    if (!grown.length) return;
    // One layout read, so every bar starts from its old length before easing to the new one.
    void document.body.offsetWidth;
    for (const [el, prop, to] of grown) { el.style.transition = ""; el.style[prop] = to; }
  }

  // A segmented control's pressed option sits on a thumb that slides between options.
  function slideThumbs(root) {
    for (const group of root.querySelectorAll(".tabs[data-tabs]")) {
      const on = group.querySelector('[aria-pressed="true"]');
      if (!on || !on.offsetWidth) continue;
      const key = "t:" + group.dataset.tabs, next = { x: on.offsetLeft, w: on.offsetWidth };
      placeThumb(group, key, next, "--thumb-x", "--thumb-w", (p) => `${p.x}px`, (p) => `${p.w}px`);
    }
  }

  function placeThumb(group, key, next, xVar, sizeVar, x, size) {
    const last = memory.get(key);
    memory.set(key, next);
    group.classList.add("has-thumb");
    const set = (p) => { group.style.setProperty(xVar, x(p)); group.style.setProperty(sizeVar, size(p)); };
    if (last && !still.matches && (last.x !== next.x || last.w !== next.w)) {
      group.classList.add("no-slide");
      set(last);
      group.getBoundingClientRect();
      group.classList.remove("no-slide");
    }
    set(next);
  }

  // The sidebar's current section, on the same kind of thumb, running down the list.
  function labelNav() {
    shownSections().forEach((section, i) => {
      const link = $(`#nav a[data-section="${section}"]`);
      if (link) link.title = `${TITLES[section]} · press ${i + 1}`;
    });
  }

  function slideNav() {
    const nav = $("#nav"), on = nav?.querySelector('a[aria-current="page"]');
    if (!on || !on.offsetHeight) return;
    placeThumb(nav, "nav", { x: on.offsetTop, w: on.offsetHeight }, "--nav-y", "--nav-h", (p) => `${p.x}px`, (p) => `${p.w}px`);
  }

  function animate(root = document) {
    growBars(root);
    countNumbers(root);
    slideThumbs(root);
  }

  // Moving between sections cross-fades and settles the page, where the browser can. Elsewhere the
  // page simply changes, as it always has.
  function transition(change) {
    if (!document.startViewTransition || still.matches) { change(); return; }
    try { document.startViewTransition(change); } catch { change(); }
  }

  // A small line of how something moved across the range, drawn to fill its box. Long ranges are
  // averaged into fewer steps, so it shows the trend rather than every weekday dip.
  function sparkline(values, color, per) {
    if (values.length < 3 || !values.some((v) => v > 0)) return "";
    // `per` groups a fixed number of buckets into one step, like whole weeks of days.
    const steps = per ? Math.ceil(values.length / per) : Math.min(20, values.length), size = values.length / steps;
    const points = Array.from({ length: steps }, (_, i) => {
      const slice = values.slice(Math.floor(i * size), Math.max(Math.floor(i * size) + 1, Math.floor((i + 1) * size)));
      return slice.reduce((s, v) => s + v, 0) / slice.length;
    });
    const peak = Math.max(...points) || 1, n = points.length - 1;
    const xy = points.map((v, i) => [(i / n) * 100, 21 - (v / peak) * 18]);
    // Through the midpoints between samples, so the line bends instead of kinking.
    let line = `M${xy[0][0].toFixed(1)},${xy[0][1].toFixed(1)}`;
    for (let i = 1; i < xy.length; i++) {
      const [px, py] = xy[i - 1], [x, y] = xy[i];
      line += `Q${px.toFixed(1)},${py.toFixed(1)} ${((px + x) / 2).toFixed(1)},${((py + y) / 2).toFixed(1)}`;
    }
    line += `L${xy[n][0].toFixed(1)},${xy[n][1].toFixed(1)}`;
    return `<svg class="spark" viewBox="0 0 100 24" preserveAspectRatio="none" aria-hidden="true">
      <path d="${line}L100,24L0,24Z" fill="${color}" fill-opacity=".14"/>
      <path d="${line}" fill="none" stroke="${color}" stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke"/>
    </svg>`;
  }

  // A hover card's content, kept in the element and shown by the shared tip.
  const tipAttr = (title, lines = []) => ` data-tip="${esc(`<b>${esc(title)}</b>${lines.map(([k, v]) => `<div><span></span><span>${esc(k)}</span><span class="mono">${esc(v)}</span></div>`).join("")}`)}"`;

  // MARK: Jump to

  // One keystroke to anywhere: a section, a range, a tool, an account to switch to, or an action.
  let palette = null;
  const isMac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent);

  // The sections the sidebar shows, in its order; key 1 opens the first, 2 the second, and so on.
  const shownSections = () => [...document.querySelectorAll("#nav a")].filter((a) => !a.hidden).map((a) => a.dataset.section);

  function paletteItems() {
    const items = [];
    const tools = data.state?.status.tools || [];
    for (const section of SECTIONS) {
      if (section === "leaderboard" && (isStatic || !data.state?.cloud?.available)) continue;
      const place = shownSections().indexOf(section);
      items.push({ group: "Go to", label: TITLES[section], icon: section, key: place >= 0 && place < 9 ? String(place + 1) : "", run: () => go(section) });
    }
    for (const [value, label] of RANGES) {
      if (isStatic && !data.usage[`${value}:all`]) continue;
      items.push({ group: "Usage over", label, run: () => showUsage({ range: value }) });
    }
    items.push({ group: "Usage for", label: "All tools", run: () => showUsage({ tool: "all" }) });
    if (!isStatic) for (const tool of tools) items.push({ group: "Usage for", label: tool.name, mark: tool.id, run: () => showUsage({ tool: tool.id }) });
    items.push({ group: "Usage in", label: "Tokens", run: () => showUsage({ metric: "tokens" }) });
    items.push({ group: "Usage in", label: "API value", run: () => showUsage({ metric: "cost" }) });
    if (!isStatic) {
      for (const tool of tools) {
        for (const account of tool.accounts.filter((a) => !a.active)) {
          items.push({ group: "Switch", label: account.name, detail: tool.name, mark: tool.id,
            run: () => act(null, () => api("/api/switch", { id: account.id }), "Switching") });
        }
      }
      items.push({ group: "Do", label: "Read limits and usage now", icon: "refresh", run: () => { if (!data.state?.refreshing) act(null, () => { data.state.refreshing = true; renderActivity(); return api("/api/refresh", {}); }); } });
      items.push({ group: "Do", label: "Check for updates", icon: "update", run: () => { ui.settingsPane = "app"; go("settings"); } });
    }
    return items;
  }

  async function showUsage(change) {
    Object.assign(ui, change);
    if (ui.section !== "usage") { await go("usage"); return; }
    render();
    await loadSection();
    render();
  }

  if ($("#hop-key")) $("#hop-key").textContent = isMac ? "⌘K" : "Ctrl K";

  function openPalette() {
    palette = { query: "", index: 0 };
    drawPalette();
    $("#palette input")?.focus();
  }

  function closePalette() {
    palette = null;
    $("#palette").innerHTML = "";
    $("#palette").hidden = true;
  }

  function paletteMatches() {
    const words = palette.query.toLowerCase().split(/\s+/).filter(Boolean);
    return paletteItems().filter((item) => {
      const text = `${item.group} ${item.label} ${item.detail || ""}`.toLowerCase();
      return words.every((w) => text.includes(w));
    });
  }

  function drawPalette() {
    const host = $("#palette");
    const matches = paletteMatches();
    palette.index = Math.max(0, Math.min(palette.index, matches.length - 1));
    let group = "";
    const rows = matches.map((item, i) => {
      const head = item.group !== group ? `<div class="palette-group">${esc((group = item.group))}</div>` : "";
      const glyph = item.mark ? mark(item.mark) : item.icon ? `<svg class="icon"><use href="#i-${item.icon}"/></svg>` : `<span class="palette-dot"></span>`;
      return `${head}<button type="button" class="palette-item" role="option" data-palette="${i}" aria-selected="${i === palette.index}">${glyph}<span>${esc(item.label)}</span>${item.detail ? `<small>${esc(item.detail)}</small>` : ""}${item.key ? `<kbd>${item.key}</kbd>` : ""}</button>`;
    }).join("");
    const list = rows || `<p class="palette-empty">Nothing matches "${esc(palette.query)}".</p>`;
    if (!host.firstElementChild) {
      host.hidden = false;
      host.innerHTML = `<div class="palette-scrim" data-palette-close></div>
        <div class="palette" role="dialog" aria-modal="true" aria-label="Hop">
          <label class="palette-search"><svg class="icon"><use href="#i-hop"/></svg><input type="text" name="hop-search" autocomplete="off" spellcheck="false" placeholder="Search sections, ranges, tools, or accounts…" aria-label="Search Hop"></label>
          <div class="palette-list" role="listbox"></div>
          <div class="palette-foot"><span><kbd>↑</kbd><kbd>↓</kbd> move</span><span><kbd>↵</kbd> open</span><span><kbd>esc</kbd> close</span></div>
        </div>`;
    }
    host.querySelector(".palette-list").innerHTML = list;
    host.querySelector('[aria-selected="true"]')?.scrollIntoView({ block: "nearest" });
  }

  function runPalette(index) {
    const item = paletteMatches()[index];
    closePalette();
    if (item) item.run();
  }

  let linkPoll = null;

  function render() {
    renderSidebar();
    if (!data.state) return;
    const tools = data.state.status.tools;
    const cloud = data.state.cloud;
    $("#backdrop")?.classList.toggle("scoped-out", data.state.appearance?.scope === "overview" && ui.section !== "overview");
    const boardLink = $('#nav a[data-section="leaderboard"]');
    if (boardLink) boardLink.hidden = isStatic || !cloud?.available;
    if (ui.section === "leaderboard" && (isStatic || !cloud?.available)) ui.section = "overview";
    // While a link waits for approval in the browser, check every few seconds instead of every 20.
    if (cloud?.linking && !linkPoll) {
      linkPoll = setTimeout(async () => {
        linkPoll = null;
        try { await loadState(); if (data.state.cloud.linked) await loadSection(); } catch {}
        render();
      }, 3000);
    }
    const page = { overview: overviewPage, accounts: accountsPage, usage: usagePage, budgets: budgetsPage, leaderboard: leaderboardPage, settings: settingsPage }[ui.section](tools);
    $("#title").textContent = TITLES[ui.section];
    $("#toolbar").innerHTML = page.toolbar || "";
    const offline = ui.offline ? `<div class="notice">${icon("alert")}<div><p>${esc(ui.offline)}</p></div></div>` : "";
    $("#main").innerHTML = `<div class="page">${offline}${page.body}</div>`;
    $("#main").setAttribute("aria-busy", (ui.loadingUsage || data.state.refreshing) ? "true" : "false");
    applyPending();
    renderActivity();
    animate();
  }

  // MARK: Progress

  // How long a new login has been awaited, as a clock that ticks in place ("0:42").
  const waited = (tool) => {
    const since = data.state?.addingSince?.[tool];
    return since ? `<span class="num subtle" data-since="${esc(since)}">${clock(since)}</span>` : "";
  };
  function clock(since) {
    const seconds = Math.max(0, Math.floor((Date.now() - new Date(since).getTime()) / 1000));
    return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
  }
  setInterval(() => { for (const node of document.querySelectorAll("[data-since]")) node.textContent = clock(node.dataset.since); }, 1000);

  // Updates every progress display in place, so a running refresh never re-draws the page.
  function renderActivity() {
    const state = data.state;
    const step = state?.activity;
    const busyNow = !!(state?.refreshing || step || ui.loadingUsage);
    const read = state?.status?.refreshedAt;
    const label = step ? `${step.title}${step.count ? ` · ${step.count}` : ""}` : state?.refreshing ? "Starting…" : ui.loadingUsage ? "Reading usage" : read ? `Limits read ${fmt.relative(read)}` : "Limits not read yet";
    $("#read").textContent = label;
    $("#main")?.setAttribute("aria-busy", busyNow ? "true" : "false");
    for (const meter of [$("#foot-meter"), $("#top-meter")]) {
      if (!meter) continue;
      const known = step?.fraction != null;
      meter.classList.toggle("unknown", busyNow && !known);
      meter.firstElementChild.style.width = known ? `${(step.fraction * 100).toFixed(1)}%` : "";
      if (meter.id === "foot-meter") meter.hidden = !busyNow; else meter.classList.toggle("on", busyNow);
      meter.setAttribute("aria-hidden", busyNow ? "false" : "true");
      if (known) meter.setAttribute("aria-valuenow", Math.round(step.fraction * 100)); else meter.removeAttribute("aria-valuenow");
    }
    for (const node of document.querySelectorAll("[data-loading]")) node.innerHTML = loadingInner(node.dataset.loading);
    const run = $(".hero-run");
    if (run) run.classList.toggle("on", busyNow);
  }

  // While Keyhop is working, ask how far it has got a few times a second; otherwise every 20 seconds.
  let watching = false;
  async function watchActivity() {
    if (watching || isStatic) return;
    watching = true;
    try {
      const busyNow = () => data.state?.refreshing || data.state?.activity || ui.loadingUsage || ui.pending.size;
      // A new login can take minutes to arrive, so that wait is checked less often.
      while (busyNow() || data.state?.adding?.length) {
        await new Promise((resolve) => setTimeout(resolve, busyNow() ? 450 : 1500));
        try {
          const wasRefreshing = data.state?.refreshing;
          const wasAdding = (data.state?.adding || []).join();
          await loadState();
          renderActivity();
          const addingChanged = wasAdding !== (data.state.adding || []).join();
          if ((wasRefreshing && !data.state.refreshing || addingChanged) && !ui.pending.size) {
            await loadSection();
            if (!editing()) render(); else renderSidebar();
          }
        } catch {
          // Keyhop stopped answering: whatever was running is no longer known to be running, and a
          // bar that keeps moving would say otherwise.
          if (data.state) { data.state.refreshing = false; data.state.activity = null; }
          break;
        }
      }
    } finally {
      watching = false;
      renderActivity();
    }
  }

  // Buttons whose work is still running, keyed by what they act on, so a re-drawn page keeps them busy.
  const pendingKey = (el) => [el.dataset.action, el.dataset.id || el.dataset.tool || el.dataset.scope || el.dataset.value || ""].join(":");
  function applyPending() {
    for (const el of document.querySelectorAll("button[data-action]")) {
      const label = ui.pending.get(pendingKey(el));
      if (label === undefined) continue;
      el.disabled = true;
      el.classList.add("working");
      el.setAttribute("aria-busy", "true");
      el.innerHTML = `<span class="ring" aria-hidden="true"></span>${esc(label || el.textContent.trim())}`;
    }
  }

  function renderSidebar() {
    for (const link of document.querySelectorAll("#nav a")) {
      if (link.dataset.section === ui.section) link.setAttribute("aria-current", "page"); else link.removeAttribute("aria-current");
    }
    const state = data.state;
    $("#mode").innerHTML = isStatic ? `<span class="badge">Saved</span>` : state?.mode === "sample" ? `<span class="badge sample">Sample</span>` : "";
    const read = state?.status?.refreshedAt;
    $("#refresh").hidden = isStatic;
    $("#refresh").classList.toggle("spin", !!state?.refreshing);
    $("#refresh").setAttribute("aria-busy", state?.refreshing ? "true" : "false");
    renderActivity();
    labelNav();
    slideNav();
  }

  function tabs(name, options, current, disabled = false) {
    return `<div class="tabs" role="group" data-tabs="${esc(name)}">${options.map(([value, label]) =>
      `<button type="button" data-action="${name}" data-value="${value}" aria-pressed="${value === current}" ${disabled ? "disabled" : ""}>${esc(label)}</button>`).join("")}</div>`;
  }

  // `grow`, when given, names the bar so it grows from its last length (see growBars).
  function progress(percent, pace, tone, grow) {
    const width = Math.min(100, Math.max(0, percent));
    // "plain" is for rankings, where a full bar means the largest, not a limit running out.
    const state = tone === "plain" ? "" : tone || (width >= 90 ? "bad" : pace != null && width > pace * 100 + 6 ? "warn" : "");
    return `<div class="progress ${state}"><span style="width:${width.toFixed(1)}%"${grow ? ` data-grow="${esc(ui.section + ":" + grow)}"` : ""}></span>${pace != null ? `<i style="left:${Math.min(100, pace * 100).toFixed(1)}%" title="Time passed"></i>` : ""}</div>`;
  }

  function limitFoot(limit) {
    if (limit.runsOutAt && new Date(limit.runsOutAt) > Date.now() && (!limit.resetsAt || new Date(limit.runsOutAt) < new Date(limit.resetsAt))) {
      return `Runs out ~${fmt.clock(limit.runsOutAt)}`;
    }
    return limit.resetsAt ? `Resets in ${fmt.until(limit.resetsAt)}` : "";
  }

  function limits(account, count = 2, note = null) {
    if (!account.limits?.length) {
      return account.error ? `<p class="problem">${esc(account.error)}</p>` : `<p class="empty-inline subtle">${esc(note || "Limits not read yet")}</p>`;
    }
    return `<div class="limits">${account.limits.slice(0, count).map((limit) => `
      <div>
        <div class="limit-top"><span>${esc(windowName(limit.label))}</span><b>${Math.round(limit.usedPercent)}%</b></div>
        ${progress(limit.usedPercent, limit.pace, undefined, `limit:${account.id}:${limit.label}`)}
        <div class="limit-foot">${esc(limitFoot(limit))}</div>
      </div>`).join("")}</div>`;
  }

  function closest(tools) {
    let best = null;
    for (const tool of tools) for (const account of tool.accounts) {
      if (!account.active || !account.limits?.length) continue;
      const top = account.limits.reduce((a, b) => (b.usedPercent > a.usedPercent ? b : a));
      if (!best || top.usedPercent > best.limit.usedPercent) best = { tool, account, limit: top };
    }
    return best;
  }

  function alternative(tool, current) {
    const pick = tool.accounts.filter((a) => !a.active && a.limits?.length).sort((a, b) => maxUsed(a) - maxUsed(b))[0];
    return pick && (!current || maxUsed(pick) + 15 < maxUsed(current)) ? pick : null;
  }

  // MARK: Overview

  function overviewPage(tools) {
    const status = data.state.status;
    const near = closest(tools);
    const today = data.usage["today:all"];
    const week = data.usage["week:all"];

    const alerts = (status.alerts || []).map((alert) => `
      <div class="notice-row">${icon("alert")}<div><b>${esc(alert.title)}</b><p>${esc(alert.body)}</p></div>
      ${alert.switchTo && !isStatic ? `<button class="btn sm" data-action="switch" data-id="${esc(alert.switchTo)}">Switch</button>` : ""}</div>`).join("");

    // A provider's own outage, which no account switch gets around. Maintenance is said plainly,
    // without the advice, since it's planned and usually brief.
    const levelWords = { maintenance: "under maintenance", degraded: "degraded performance", partial: "partial outage", major: "major outage" };
    const services = data.services || [];
    const troubled = services.filter((s) => levelWords[s.level]);
    const outages = troubled.map((s) => {
      const incident = s.incidents[0];
      const detail = incident ? `${esc(incident.name)}. ${esc(incident.stage[0].toUpperCase() + incident.stage.slice(1))}${incident.updated ? ` ${esc(ago(incident.updated))}` : ""}.` : "";
      const advice = s.level === "maintenance" ? "" : " Every account is affected, so switching won't help.";
      return `<div class="notice-row">${icon("alert")}<div><b>${esc(toolName(s.tool))}: ${levelWords[s.level]}</b><p>${detail}${advice}</p></div>
        <a class="btn sm secondary" href="${esc(incident?.link || s.page)}" target="_blank" rel="noopener">Status page</a></div>`;
    }).join("");
    const serviceHint = services.length && !troubled.length && services.some((s) => s.level === "operational") ? " · Services operational" : "";

    const streak = (week || today)?.streak;
    // Everything that needs a look, in one place instead of a stack of boxes.
    const notices = alerts + outages ? `<section class="notices" aria-label="Needs a look">${alerts}${outages}</section>` : "";
    const hero = `<section class="hero">
      <div class="hero-main">
      <h2 class="hero-figure"><span class="num" data-count="${status.today.tokens}" data-count-key="today" data-format="tokens" data-count-intro>${fmt.tokens(status.today.tokens)}</span><span class="unit">tokens today</span></h2>
      <p class="hero-line">${today ? `${fmt.change(today.total.tokens, today.previous.tokens)} on yesterday · ` : ""}${fmt.count(status.today.requests)} requests${today && today.total.requests ? ` · ${esc(busiestHour(today))}` : ""}</p>
      </div>
      ${today && today.total.requests ? `<figure class="hero-hours"><figcaption>Today by hour</figcaption>${dotHours(today)}</figure>` : ""}
      <div class="hero-run${data.state.refreshing ? " on" : ""}" aria-hidden="true">${window.KeyhopBackdrop ? window.KeyhopBackdrop.sprite("blip", "top:0") : ""}</div>
    </section>`;
    const stats = hero + `<div class="stats">
      <div class="card stat"><div class="label">Streak</div><div class="value">${streak ? `${streak.current} ${streak.current === 1 ? "day" : "days"}` : "…"}</div><div class="foot">${streak ? `Longest ${streak.longest} · ${fmt.count(streak.activeDays)} active days` : ""}</div></div>
      <div class="card stat"><div class="label">API value today</div><div class="value">${fmt.usd(status.today.cost)}</div><div class="foot">At standard API prices</div></div>
      <div class="card stat"><div class="label">This week ${week ? fmt.change(week.total.tokens, week.previous.tokens) : ""}</div><div class="value">${week ? fmt.tokens(week.total.tokens) : "…"}</div><div class="foot">${week ? `${fmt.usd(week.total.cost)} API value` : ""}</div></div>
      <div class="card stat"><div class="label">Closest to a limit</div><div class="value">${near ? `${Math.round(near.limit.usedPercent)}%` : "None"}</div><div class="foot">${near ? `${esc(near.tool.name)} · ${esc(windowName(near.limit.label))}` : "No limits read yet"}</div></div>
    </div>`;

    // Tools with nothing saved would each be a row of instructions; they share one line instead.
    // On a first run, when nothing is set up at all, every tool keeps its row and its sign-in hint.
    const isSetUp = (tool) => tool.accounts.length > 0 || data.state.adding.includes(tool.id);
    const anySetUp = tools.some(isSetUp);
    const inUseTools = anySetUp ? tools.filter(isSetUp) : tools;
    const unsetTools = anySetUp ? tools.filter((tool) => !isSetUp(tool)) : [];
    const inUse = `<section class="card">
      <div class="card-head"><h2>In use</h2><span class="hint">Each tool's current account and its limits${serviceHint}</span></div>
      <div class="list">${inUseTools.map((tool) => {
        const account = tool.accounts.find((a) => a.active);
        const other = alternative(tool, account);
        const adding = data.state.adding.includes(tool.id);
        const outage = troubled.find((s) => s.tool === tool.id);
        const identity = account
          ? `<div class="who">${mark(tool.id)}<div><b>${esc(tool.name)}</b><small>${esc(account.name)}${account.plan ? ` · ${esc(account.plan)}` : ""}${outage ? ` · <span class="warn-text">${esc(levelWords[outage.level][0].toUpperCase() + levelWords[outage.level].slice(1))}</span>` : ""}</small></div></div>`
          : `<div class="who">${mark(tool.id)}<div><b>${esc(tool.name)}</b><small>${tool.accounts.length ? "Signed out" : "No saved accounts"}</small></div></div>`;
        const middle = adding ? `<div class="waiting"><span class="pulse"><i></i><i></i><i></i></span><span>Waiting for the new login ${waited(tool.id)}</span></div>`
          : account ? limits(account, 2, tool.limitsNote) : `<p class="empty-inline subtle">${esc(tool.signInHint)}</p>`;
        const actions = isStatic ? "" : other
          ? `<button class="btn sm secondary" data-action="switch" data-id="${esc(other.id)}">Switch to ${esc(other.name)}</button>`
          : `<button class="btn sm ghost" data-action="goto" data-section="accounts">Accounts</button>`;
        return `<div class="row tool-row">${identity}${middle}<div class="row-actions">${actions}</div></div>`;
      }).join("")}${unsetTools.length ? `<div class="row unset-row">
        <div class="unset-marks" aria-hidden="true">${unsetTools.map((tool) => mark(tool.id)).join("")}</div>
        <p class="subtle">Not set up: ${esc(unsetTools.map((tool) => tool.name).join(", "))}</p>
        <div class="row-actions">${isStatic ? "" : `<button class="btn sm ghost" data-action="goto" data-section="accounts">Add an account</button>`}</div>
      </div>` : ""}</div>
    </section>`;

    const weekCard = `<section class="card">
      <div class="card-head"><h2>Last 7 days</h2><button class="btn sm ghost" data-action="goto" data-section="usage">Open usage</button></div>
      <div class="card-body">${week ? (week.total.requests ? `<div class="chart">${stackedChart(week, "tokens", 214, "half", "account")}</div>` : `<p class="empty-inline">No usage in the last 7 days.</p>`) : loading("Reading usage")}</div>
    </section>`;
    const budgetsCard = `<section class="card">
      <div class="card-head"><h2>Budgets</h2><button class="btn sm ghost" data-action="goto" data-section="budgets">${status.budgets.length ? "Manage" : "Set a budget"}</button></div>
      ${status.budgets.length ? `<div class="list">${status.budgets.slice(0, 3).map(budgetRow).join("")}</div>` : `<p class="empty">No budgets yet. A budget warns you at 80% and 100%.</p>`}
    </section>`;
    const modelsCard = `<section class="card">
      <div class="card-head"><h2>Top models this week</h2></div>
      ${week && week.models.length ? `<div class="card-body">${rankedList("overview-models", week.models.slice().sort((a, b) => b.figures.tokens - a.figures.tokens).slice(0, 6),
        (m) => m.figures.tokens / (week.total.tokens || 1),
        (m) => `${mark(m.tool)}<span class="mono">${esc(m.model)}</span><span class="subtle ranked-value">${fmt.tokens(m.figures.tokens)}</span>`)}</div>` : `<p class="empty">No models used this week.</p>`}
    </section>`;

    return { body: `${notices}${stats}${inUse}<div class="split">${weekCard}${modelsCard}</div>${budgetsCard}` };
  }

  function busiestHour(usage) {
    let best = null;
    usage.buckets.forEach((bucket) => {
      const total = Object.values(bucket.values).reduce((sum, v) => sum + v.tokens, 0);
      if (total && (!best || total > best.total)) best = { total, start: bucket.start };
    });
    return best ? `Busiest at ${fmt.clock(best.start)}` : "";
  }

  /// Today as a dot matrix: one column per hour, lit from the bottom by its share of the busiest hour.
  function dotHours(usage) {
    const totals = usage.buckets.map((b) => Object.values(b.values).reduce((sum, v) => sum + v.tokens, 0));
    const peak = Math.max(1, ...totals);
    const hour = new Date().getHours();
    const rows = 7, step = Math.max(12, Math.min(24, Math.floor(chartWidth("half") / 24))), radius = step * 0.26;
    const width = 24 * step, height = rows * step + 18;
    let dots = "";
    totals.forEach((value, col) => {
      const lit = value ? Math.max(1, Math.round((value / peak) * rows)) : 0;
      for (let row = 0; row < rows; row++) {
        const on = rows - row <= lit;
        dots += `<circle cx="${col * step + step / 2}" cy="${row * step + step / 2}" r="${radius}" class="${on ? (col === hour ? "now" : "on") : ""}"><title>${String(col).padStart(2, "0")}:00 · ${fmt.tokens(value)} tokens</title></circle>`;
      }
    });
    const labels = [0, 6, 12, 18, 23].map((h) => `<text x="${h * step + step / 2}" y="${height - 3}" text-anchor="middle">${String(h).padStart(2, "0")}</text>`).join("");
    return `<svg class="dots" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" role="img" aria-label="Tokens by hour today">${dots}${labels}</svg>`;
  }

  function budgetRow(budget) {
    const share = budget.amount > 0 ? budget.spent / budget.amount : 0;
    const elapsed = periodProgress(budget.period).elapsed;
    return `<div class="row budget-row">
      <div class="budget-top"><b>${esc(budget.name)}</b><span class="mono">${fmt.usd(budget.spent)} <span class="subtle">/ ${fmt.usd(budget.amount)}</span></span></div>
      ${progress(share * 100, elapsed, share >= 1 ? "bad" : share >= .8 ? "warn" : "", `budget:${budget.scope}`)}
      <div class="subtle" style="font-size:12px">Per ${esc(budget.period)} · ${Math.round(share * 100)}% used · on pace for ${fmt.usd(budget.spent / elapsed)}</div>
    </div>`;
  }

  // MARK: Accounts

  function accountsPage(tools) {
    const body = tools.map((tool) => {
      const adding = data.state.adding.includes(tool.id);
      const rows = tool.accounts.map((account) => accountRow(account, tool)).join("");
      const waiting = adding ? `<div class="row waiting-row"><div class="waiting"><span class="pulse"><i></i><i></i><i></i></span><span>Waiting for a new ${esc(tool.name)} login ${waited(tool.id)}<br><small>${esc(tool.signInHint)} Keyhop saves it the moment it appears.</small></span></div>
        ${isStatic ? "" : `<button class="btn sm ghost" data-action="add-stop" data-tool="${esc(tool.id)}">Stop waiting</button>`}</div>` : "";
      const empty = !tool.accounts.length && !adding ? `<p class="empty">${esc(tool.signInHint)}</p>` : "";
      return `<section class="group">
        <div class="group-head">${mark(tool.id)}<h2>${esc(tool.name)}</h2><span class="count">${tool.accounts.length}</span>
          ${isStatic ? "" : `<button class="btn sm ghost" data-action="add" data-tool="${esc(tool.id)}" ${adding ? "disabled" : ""}>${icon("plus")}Add account</button>`}</div>
        <div class="card list">${waiting}${rows}${empty}</div>
      </section>`;
    }).join("");
    return { body: `<p class="lede">Every login Keyhop keeps. Switching saves the login in use first, so none is ever lost.</p>${body}` };
  }

  // One saved login: who it is, how much room its limits have, what it used today, and what can be
  // done with it. The login in use carries a mark that moves to the next one when you switch.
  function accountRow(account, tool) {
    const editing = ui.editing === account.id;
    const confirming = ui.confirming === account.id;
    const meta = [account.plan, account.label ? account.email : ""].filter(Boolean).map(esc).join(" · ");
    const name = editing
      ? `<form class="rename" data-form="rename" data-id="${esc(account.id)}"><input class="field" name="name" value="${esc(account.label || "")}" placeholder="${esc(account.email)}" maxlength="60" aria-label="Name"><button class="btn sm">Save</button><button type="button" class="btn sm ghost" data-action="cancel-edit">Cancel</button></form>`
      : `<div class="account-name"><b>${esc(account.name)}</b>${account.active ? `<span class="in-use" style="view-transition-name:in-use-${esc(tool.id)}">In use</span>` : ""}</div>
         ${meta ? `<div class="account-meta">${meta}</div>` : ""}`;
    let actions = "";
    if (!isStatic && !editing) {
      if (confirming) {
        actions = `<span class="subtle" style="font-size:12.5px">Delete this saved login?</span><button class="btn sm secondary danger" data-action="remove" data-id="${esc(account.id)}">Remove</button><button class="btn sm ghost" data-action="cancel-remove">Keep</button>`;
      } else {
        const open = ui.menu === account.id;
        const menu = open ? `<div class="row-menu" role="menu">
            <button type="button" role="menuitem" data-action="edit" data-id="${esc(account.id)}">Rename</button>
            ${account.active ? "" : `<button type="button" role="menuitem" class="danger" data-action="confirm-remove" data-id="${esc(account.id)}">Remove saved login</button>`}
          </div>` : "";
        actions = `${account.active ? "" : `<button class="btn sm secondary" data-action="switch" data-id="${esc(account.id)}">Switch</button>`}
          <span class="menu-anchor"><button type="button" class="btn sm ghost icon-only" data-action="account-menu" data-id="${esc(account.id)}" aria-haspopup="true" aria-expanded="${open}" aria-label="More for ${esc(account.name)}">${icon("more")}</button>${menu}</span>`;
      }
    }
    const today = account.today
      ? `<b data-count="${account.today.tokens}" data-count-key="acct:${esc(account.id)}" data-format="tokens">${fmt.tokens(account.today.tokens)}</b><span>tokens today · ${fmt.usd(account.today.cost)}</span>`
      : `<span>No usage today</span>`;
    return `<div class="row account-row${account.active ? " active" : ""}" style="view-transition-name:acct-${esc(account.id)}">
      <div class="account-id">${name}</div>
      <div>${limits(account, 2, tool.limitsNote)}</div>
      <div class="today">${today}</div>
      <div class="row-actions">${actions}</div>
    </div>`;
  }

  // MARK: Usage

  function usagePage(tools) {
    const toolbar = rangePicker(data.usage[`${ui.range}:${ui.tool}`])
      + tabs("metric", [["tokens", "Tokens"], ["cost", "API value"]], ui.metric)
      + `<select class="field" data-action="tool" aria-label="Tool" ${isStatic ? "disabled" : ""}>${[["all", "All tools"], ...tools.map((t) => [t.id, t.name])].map(([v, l]) => `<option value="${v}" ${v === ui.tool ? "selected" : ""}>${esc(l)}</option>`).join("")}</select>`;
    const usage = data.usage[`${ui.range}:${ui.tool}`] || (isStatic ? data.usage[`${ui.range}:all`] : null);
    if (!usage) return { toolbar, body: `<div class="card">${loading("Reading usage", "empty")}</div>` };
    const stale = data.usageErrors[`${ui.range}:${ui.tool}`]
      ? `<div class="notice">${icon("alert")}<div><b>Showing the last complete reading</b><p>${esc(data.usageErrors[`${ui.range}:${ui.tool}`])}</p></div></div>` : "";

    const t = usage.total;
    const top = `<div class="usage-top">${totalCard(usage)}${summaryCard(usage)}</div>`;
    if (!t.requests) {
      return { toolbar, body: `${stale}${top}<div class="card"><p class="empty">No usage in this range. Keyhop reads Claude Code, Codex, Gemini CLI, OpenCode and Pi records on this computer, and Cursor's usage export after a refresh.</p></div>${heatCard(usage)}` };
    }
    const grouped = chartGroup(usage);
    // The legend doubles as a filter: each entry hides or shows its part of every bar.
    const hidden = ui.hidden[ui.group] || [];
    const legend = `<ul class="legend">${grouped.series.map((s) => `<li><button type="button" class="legend-item" data-action="series" data-value="${esc(s.id)}" aria-pressed="${!hidden.includes(s.id)}" title="${hidden.includes(s.id) ? "Show" : "Hide"} ${esc(s.name)}"><span class="swatch" style="background:${s.color}"></span>${esc(s.name)}</button></li>`).join("")}</ul>`;
    const chart = `<section class="card">
      <div class="card-head"><h2>${ui.metric === "tokens" ? "Tokens" : "API value"} by ${usage.bucket}</h2>${tabs("group", [["account", "Accounts"], ["tool", "Tools"], ["model", "Models"]], ui.group)}</div>
      <div class="card-body chart-body">${legend}<div class="chart" style="view-transition-name:usage-chart">${stackedChart(usage, ui.metric, 260, "full", ui.group, hidden)}</div></div>
    </section>`;
    const mix = `<section class="card">
      <div class="card-head"><h2>Token mix</h2><span class="hint mono">${fmt.tokens(t.tokens)}</span></div>
      <div class="card-body">${mixBlock(t)}</div>
    </section>`;
    return { toolbar, body: `${stale}${top}${chart}<div class="split wide-left">${heatCard(usage)}${mix}</div>${breakdownCard(usage)}` };
  }

  // The range's total, exact, set large; what it was worth; and how it splits across tools, or
  // across one tool's models once the page is narrowed to that tool.
  function totalCard(usage) {
    const t = usage.total, p = usage.previous;
    const tokens = ui.metric === "tokens";
    const exact = tokens ? fmt.count(t.tokens) : "$" + (t.cost || 0).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    const change = usage.compared === false ? "" : tokens ? fmt.change(t.tokens, p.tokens) : fmt.change(t.cost, p.cost);
    const inputSide = t.input + t.cacheRead + t.cacheWrite + (t.cacheWrite1h || 0);
    const facts = [
      tokens ? `${fmt.usd(t.cost)} at API prices` : `${fmt.tokens(t.tokens)} tokens`,
      `${fmt.count(t.requests)} requests`,
      inputSide ? `${Math.round((t.cacheRead / inputSide) * 100)}% from cache` : "",
      usage.cacheSavings > 0 ? `${fmt.usd(usage.cacheSavings)} saved by prompt caching` : "",
      t.billed > 0 ? `${fmt.usd(t.billed)} billed on demand` : "",
    ].filter(Boolean);
    const before = usage.compared === false
      ? `Since ${esc(fmt.day(usage.since || usage.start, { month: "short", day: "numeric", year: "numeric" }))}`
      : `vs ${tokens ? fmt.tokens(p.tokens) : fmt.usd(p.cost)} the period before`;

    const narrowed = ui.tool !== "all";
    const value = (x) => (tokens ? x.figures.tokens : x.figures.cost);
    const parts = narrowed
      ? usage.models.map((m) => ({ id: m.model, name: m.model, color: m.color, figures: m.figures, mono: true }))
      : (usage.tools || []).map((tool) => ({ id: tool.id, name: tool.name, color: tool.color, figures: tool.figures, tool: tool.id,
          models: usage.models.filter((m) => m.tool === tool.id).length }));
    parts.sort((a, b) => value(b) - value(a));
    // One tool's models share its colour, so each steps a shade lighter by rank to stay apart.
    if (narrowed) parts.forEach((x, i) => { x.color = shade(x.color, Math.min(0.6, i * 0.2)); });
    const sum = parts.reduce((s, x) => s + value(x), 0) || 1;
    const share = (x) => (value(x) / sum) * 100;
    const pct = (x) => { const v = share(x); return v > 0 && v < 1 ? "<1%" : `${Math.round(v)}%`; };
    const show = (x) => (tokens ? fmt.tokens(x.figures.tokens) : fmt.usd(x.figures.cost));
    const tipFor = (x) => tipAttr(x.name, [["Share", pct(x)], [tokens ? "Tokens" : "API value", show(x)], ["Requests", fmt.count(x.figures.requests)]]);
    const scope = `${ui.tool}:${ui.metric}`;
    const bar = `<div class="share-bar" role="img" aria-label="Share of ${tokens ? "tokens" : "API value"}">${parts.filter((x) => share(x) >= 0.4)
      .map((x) => `<span style="flex-grow:${share(x).toFixed(3)};background:${x.color}" data-grow="share:${esc(scope)}:${esc(x.id)}" data-grow-prop="flexGrow"${tipFor(x)}></span>`).join("")}</div>`;
    // Each part's line across the range, from the same buckets the chart draws.
    const buckets = narrowed ? usage.modelBuckets || [] : usage.toolBuckets || [];
    const trend = (x) => sparkline(buckets.map((b) => { const v = b.values[narrowed ? `${ui.tool}:${x.id}` : x.id]; return v ? (tokens ? v.tokens : v.cost) : 0; }), x.color, usage.bucket === "day" && buckets.length >= 21 ? 7 : 0);
    const tiles = parts.map((x) => {
      const inner = `<span class="tile-name">${x.tool ? mark(x.tool) : ""}<span class="${x.mono ? "mono" : ""}">${esc(x.name)}</span></span>
        <span class="tile-mid"><span class="tile-share" data-count="${share(x).toFixed(2)}" data-count-key="tile:${esc(scope)}:${esc(x.id)}" data-format="pct">${pct(x)}</span>${trend(x)}</span>
        <span class="tile-foot"><span class="swatch" style="background:${x.color}"></span>${show(x)}${x.models ? ` · ${x.models} ${x.models === 1 ? "model" : "models"}` : ""}</span>`;
      return x.tool && !isStatic
        ? `<button type="button" class="tile" data-action="filter-tool" data-value="${esc(x.tool)}" aria-label="Show only ${esc(x.name)}"${tipFor(x)}>${inner}</button>`
        : `<div class="tile"${tipFor(x)}>${inner}</div>`;
    }).join("");
    const title = `${tokens ? "Tokens" : "API value"}, ${esc((usage.title || "").toLowerCase() === "today" ? "today" : usage.title)}${narrowed ? ` · ${esc(toolName(ui.tool))}` : ""}`;
    return `<section class="card total-card">
      <div class="total-head"><span>${title}</span>${narrowed && !isStatic ? `<button type="button" class="btn sm ghost" data-action="filter-tool" data-value="all">All tools</button>` : `<span class="total-change">${change}<span class="subtle">${before}</span></span>`}</div>
      <div class="total-figure" data-count="${tokens ? t.tokens : (t.cost || 0).toFixed(2)}" data-count-key="total:${esc(ui.metric)}" data-format="${tokens ? "count" : "usdExact"}" data-count-intro>${exact}</div>
      <p class="total-facts">${facts.map(esc).join(" · ")}</p>
      ${parts.length ? bar : ""}
      <div class="tiles">${tiles}</div>
    </section>`;
  }

  // A hex colour mixed toward white by `amount` (0 to 1).
  function shade(hex, amount) {
    const m = /^#?([0-9a-f]{6})$/i.exec(hex || "");
    if (!m || !amount) return hex;
    const n = parseInt(m[1], 16), mix = (c) => Math.round(c + (255 - c) * amount);
    return `rgb(${mix(n >> 16)}, ${mix((n >> 8) & 255)}, ${mix(n & 255)})`;
  }

  // Quick figures from the daily record, whatever range is shown, and the models that carried it.
  function summaryCard(usage) {
    const days = usage.heatmap || [];
    const today = localDay(new Date());
    const upto = days.filter((d) => d.day <= today);
    const lastN = (n) => upto.slice(-n).reduce((s, d) => s + (ui.metric === "tokens" ? d.tokens : d.cost), 0);
    const active = upto.filter((d) => d.tokens > 0);
    const perDay = active.length ? active.reduce((s, d) => s + (ui.metric === "tokens" ? d.tokens : d.cost), 0) / active.length : 0;
    const show = (v) => (ui.metric === "tokens" ? fmt.tokens(v) : fmt.usd(v));
    const chips = [["Today", lastN(1)], ["7 days", lastN(7)], ["30 days", lastN(30)], ["Per active day", perDay]]
      .map(([label, v]) => `<div class="chip"><b data-count="${v}" data-count-key="chip:${label}:${ui.tool}:${ui.metric}" data-format="${ui.metric === "tokens" ? "tokens" : "usd"}" data-count-intro>${show(v)}</b><span>${label}</span></div>`).join("");
    const value = (m) => (ui.metric === "tokens" ? m.figures.tokens : m.figures.cost);
    const models = usage.models.slice().sort((a, b) => value(b) - value(a));
    const sum = models.reduce((s, m) => s + value(m), 0) || 1;
    const s = usage.streak;
    return `<section class="card summary-card">
      <div class="chips">${chips}</div>
      ${models.length ? rankedList(`summary:${ui.tool}:${ui.metric}`, models.slice(0, 5), (m) => value(m) / sum, (m) => `${m.tool ? mark(m.tool) : ""}<span class="mono">${esc(m.model)}</span>`) : `<p class="empty-inline subtle">No models in this range.</p>`}
      <div class="summary-foot"><span>${fmt.count(s.activeDays)} active days in 26 weeks</span><span>${s.current ? `${s.current}-day streak` : "No streak running"}</span></div>
    </section>`;
  }

  // A ranked list: place, name, share, and a track filled to that share.
  function rankedList(key, items, shareOf, nameOf) {
    return `<ol class="ranked">${items.map((item, i) => {
      const share = Math.max(0, Math.min(1, shareOf(item)));
      const pct = share > 0 && share < 0.01 ? "<1%" : `${Math.round(share * 100)}%`;
      return `<li><span class="place">${i + 1}</span><span class="ranked-name">${nameOf(item)}</span><span class="ranked-share">${pct}</span>
        <span class="ranked-track"><span style="width:${(share * 100).toFixed(1)}%" data-grow="${esc(key)}:${i}"></span></span></li>`;
    }).join("")}</ol>`;
  }

  // Everything under the chart, one table at a time.
  function breakdownCard(usage) {
    const step = { hour: "Hours", day: "Days", week: "Weeks", month: "Months" }[usage.bucket] || "Days";
    const placed = (usage.projects || []).filter((p) => p.path);
    const views = [["periods", step], ["models", "Models"], ["makers", "Makers"], ["projects", "Projects"], ["accounts", "Accounts"], ["sessions", "Sessions"]]
      .filter(([id]) => id !== "projects" || placed.length)
      .filter(([id]) => id !== "sessions" || (usage.sessions || []).length)
      .filter(([id]) => id !== "makers" || (usage.makers || []).length);
    const view = views.some(([id]) => id === ui.breakdown) ? ui.breakdown : "periods";
    const body = view === "models" ? rankedModelTable(usage.models, ui.metric)
      : view === "makers" ? makerTable(usage.makers, ui.metric)
      : view === "projects" ? projectTable(usage.projects, ui.metric)
      : view === "accounts" ? accountTable(usage.accounts, ui.metric)
      : view === "sessions" ? sessionTable(usage.sessions, ui.metric)
      : periodTable(usage);
    return `<section class="card">
      <div class="card-head">${tabs("breakdown", views, view)}${isStatic ? "" : `<button class="btn sm ghost" data-action="export-csv">Download CSV</button>`}</div>
      <div class="table-wrap">${body}</div>
    </section>`;
  }

  // Each period with usage, newest first, in full: a number here is to be read, not glanced at.
  function periodTable(usage) {
    const rows = usage.periods || [];
    if (!rows.length) return `<p class="empty">Nothing in this range.</p>`;
    const shown = ui.allPeriods ? rows : rows.slice(0, 14);
    const when = (start) => usage.bucket === "hour" ? fmt.day(start, { weekday: "short", hour: "2-digit", minute: "2-digit" })
      : usage.bucket === "week" ? `Week of ${fmt.day(start, { month: "short", day: "numeric", year: "numeric" })}`
      : usage.bucket === "month" ? fmt.day(start, { month: "long", year: "numeric" })
      : fmt.day(start, { weekday: "short", month: "short", day: "numeric" });
    const n = (v) => `<td class="right mono">${fmt.count(v)}</td>`;
    const body = shown.map((r) => { const f = r.figures; return `<tr>
      <td class="nowrap">${esc(when(r.start))}</td>
      <td class="right mono strong">${fmt.count(f.tokens)}</td>${n(f.input)}${n(f.output)}${n(f.cacheRead)}${n(f.cacheWrite + (f.cacheWrite1h || 0))}${n(f.requests)}
      <td class="right mono">${fmt.usd(f.cost)}</td>
    </tr>`; }).join("");
    const more = rows.length > shown.length
      ? `<div class="table-more"><button type="button" class="btn sm ghost" data-action="all-periods">Show all ${rows.length}</button></div>` : "";
    return `<table class="table data"><thead><tr><th>${{ hour: "Hour", day: "Day", week: "Week", month: "Month" }[usage.bucket] || "Day"}</th><th class="right">Total</th><th class="right">Input</th><th class="right">Output</th><th class="right">Cache read</th><th class="right">Cache write</th><th class="right">Requests</th><th class="right">API value</th></tr></thead><tbody>${body}</tbody></table>${more}`;
  }

  // Every model in one ranking, whichever tool ran it.
  function rankedModelTable(models, metric) {
    const value = (m) => (metric === "tokens" ? m.figures.tokens : m.figures.cost);
    const sorted = models.slice().sort((a, b) => value(b) - value(a));
    const sum = sorted.reduce((s, m) => s + value(m), 0) || 1;
    const peak = Math.max(0.000001, ...sorted.map(value));
    const rows = sorted.map((m, i) => `<tr${isStatic ? "" : ` class="clickable" data-action="filter-tool" data-value="${esc(m.tool || "")}"`}>
      <td class="place-cell mono subtle">${i + 1}</td>
      <td><div class="cell-name">${mark(m.tool)}<span class="mono">${esc(m.model)}</span></div></td>
      <td class="bar-cell">${progress((value(m) / peak) * 100, null, "plain", `row:${ui.tool}:${metric}:${m.tool || ""}:${m.model || m.name}`)}</td>
      <td class="right mono">${metric === "tokens" ? fmt.tokens(m.figures.tokens) : fmt.usd(m.figures.cost)}</td>
      <td class="right mono subtle">${Math.round((value(m) / sum) * 100)}%</td>
    </tr>`).join("");
    return `<table class="table"><thead><tr><th></th><th>Model</th><th></th><th class="right">${metric === "tokens" ? "Tokens" : "API value"}</th><th class="right">Share</th></tr></thead><tbody>${rows}</tbody></table>`;
  }

  // One button for the range, opening the fixed ranges and a pair of dates. Tabs for seven ranges
  // plus dates would crowd everything else out of the toolbar.
  const RANGES = [["today", "Today"], ["week", "7 days"], ["month", "This month"], ["30d", "30 days"], ["90d", "90 days"], ["12m", "12 months"], ["all", "All time"]];
  const localDay = (date) => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
  function rangePicker(usage) {
    const preset = RANGES.find(([value]) => value === ui.range);
    const label = preset ? preset[1] : usage?.title || "Chosen dates";
    const today = localDay(new Date());
    const [from, to] = ui.range.includes("..") ? ui.range.split("..") : [usage ? localDay(new Date(usage.start)) : today, today];
    const offered = RANGES.filter(([value]) => !isStatic || data.usage[`${value}:all`]);
    const menu = ui.rangeOpen ? `<div class="range-menu">
      <div class="range-list" role="group" aria-label="Range">${offered.map(([value, name]) => `<button type="button" data-action="range" data-value="${value}" aria-checked="${value === ui.range}" role="menuitemradio">${esc(name)}</button>`).join("")}</div>
      ${isStatic ? "" : `<form class="range-dates" data-form="range">
        <label>From<input class="field" type="date" name="from" value="${esc(from)}" max="${today}" required></label>
        <label>To<input class="field" type="date" name="to" value="${esc(to)}" max="${today}" required></label>
        <button class="btn sm secondary">Show these days</button>
      </form>`}
    </div>` : "";
    return `<div class="range-pick"><button type="button" class="range-button" data-action="range-menu" aria-haspopup="true" aria-expanded="${ui.rangeOpen}">${esc(label)}<svg viewBox="0 0 10 10" aria-hidden="true"><path d="M2 3.6 5 6.6 8 3.6" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg></button>${menu}</div>`;
  }

  function niceCeiling(value) {
    if (value <= 0) return 1;
    const magnitude = Math.pow(10, Math.floor(Math.log10(value)));
    for (const step of [1, 2, 2.5, 5, 10]) if (step * magnitude >= value) return step * magnitude;
    return 10 * magnitude;
  }

  /// Drawn at the width it's shown at, so text stays its intended size.
  function chartWidth(size) {
    const page = Math.min(1320, ($("#main")?.clientWidth || 1200) - 48);
    const columns = matchMedia("(max-width: 1180px)").matches ? 1 : 2;
    const half = columns === 2 ? (page - 16) / 2 : page;
    const widths = { full: page, half, wide: columns === 2 ? (page - 16) * 0.608 : page, narrow: columns === 2 ? (page - 16) * 0.392 : page };
    // Card padding and borders, with a little room so rounding never adds a scrollbar.
    return Math.max(420, Math.floor((widths[size] || page) - 40));
  }

  function roundedTop(x, y, w, h) {
    const r = Math.min(3, h, w / 2);
    return `M${x},${y + h}V${y + r}Q${x},${y} ${x + r},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + h}Z`;
  }

  function stackedChart(usage, metric, height, size, group, hidden = []) {
    const grouped = chartGroup(usage, group);
    const series = grouped.series.filter((s) => !hidden.includes(s.id)), buckets = grouped.buckets;
    const W = chartWidth(size), H = height, L = 52, R = 4, T = 8, B = 26;
    const pw = W - L - R, ph = H - T - B;
    const pick = (v) => (v ? (metric === "tokens" ? v.tokens : v.cost) : 0);
    const columns = buckets.map((b) => series.map((s) => pick(b.values[s.id])));
    const ceiling = niceCeiling(Math.max(0, ...columns.map((c) => c.reduce((a, b) => a + b, 0))));
    const slot = pw / Math.max(1, buckets.length);
    const bw = Math.max(3, Math.min(slot * 0.58, 30));
    const label = (v) => (metric === "tokens" ? fmt.tokens(v) : v === 0 ? "$0" : v < 10 ? "$" + v.toFixed(2) : fmt.usd(v));
    // As many labels as fit at about 64px each, on a step that reads naturally for hours.
    const fits = Math.max(2, Math.floor(pw / 64));
    const every = Math.max(usage.bucket === "hour" ? 3 : 1, Math.ceil(buckets.length / fits));
    const spansYears = buckets.length > 1 && new Date(buckets[0].start).getFullYear() !== new Date(buckets[buckets.length - 1].start).getFullYear();
    const axisOptions = usage.bucket === "hour" ? { hour: "2-digit" }
      : usage.bucket === "month" ? (spansYears ? { month: "short", year: "2-digit" } : { month: "short" })
      : usage.bucket === "week" || buckets.length > 10 ? { month: "short", day: "numeric" }
      : { weekday: "short" };
    let grid = "", bars = "", hits = "";
    for (let i = 0; i <= 4; i++) {
      const value = (ceiling / 4) * i, y = (T + ph - (value / ceiling) * ph).toFixed(1);
      grid += `<line class="${i ? "grid" : "base"}" x1="${L}" x2="${W - R}" y1="${y}" y2="${y}"/><text class="axis" x="${L - 8}" y="${y}" text-anchor="end" dominant-baseline="central">${label(value)}</text>`;
    }
    buckets.forEach((bucket, i) => {
      const cx = L + slot * (i + 0.5), x = cx - bw / 2;
      const present = series.map((s, j) => ({ s, v: columns[i][j] })).filter((e) => e.v > 0);
      let base = 0;
      bars += `<g class="col" data-col="${i}">`;
      present.forEach((entry, k) => {
        const y0 = T + ph - (base / ceiling) * ph, y1 = T + ph - ((base + entry.v) / ceiling) * ph;
        base += entry.v;
        const gap = k ? Math.min(1.5, (y0 - y1) / 2) : 0;
        const h = y0 - gap - y1;
        if (h < 0.3) return;
        bars += k === present.length - 1
          ? `<path d="${roundedTop(+x.toFixed(1), +y1.toFixed(1), +bw.toFixed(1), +h.toFixed(1))}" fill="${entry.s.color}"/>`
          : `<rect x="${x.toFixed(1)}" y="${y1.toFixed(1)}" width="${bw.toFixed(1)}" height="${h.toFixed(1)}" fill="${entry.s.color}"/>`;
      });
      bars += `</g>`;
      if (i % every === 0) {
        grid += `<text class="axis" x="${cx.toFixed(1)}" y="${H - 7}" text-anchor="middle">${esc(fmt.day(bucket.start, axisOptions))}</text>`;
      }
      hits += `<rect class="hit" x="${(L + slot * i).toFixed(1)}" y="${T}" width="${slot.toFixed(1)}" height="${ph}" data-bucket="${i}" data-metric="${metric}" data-group="${group || "account"}" data-key="${usage.range}:${usage.tool}"/>`;
    });
    return `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="${metric === "tokens" ? "Tokens" : "API value"} by ${usage.bucket}">${grid}<g>${bars}</g>${hits}</svg>`;
  }

  function chartGroup(usage, group) {
    const which = group || ui.group || "account";
    if (which === "tool" && usage.toolSeries && usage.toolBuckets) return { series: usage.toolSeries, buckets: usage.toolBuckets };
    if (which === "model" && usage.modelSeries && usage.modelBuckets) return { series: usage.modelSeries, buckets: usage.modelBuckets };
    return { series: usage.series, buckets: usage.buckets };
  }

  function heatCard(usage) {
    const s = usage.streak;
    return `<section class="card">
      <div class="card-head"><h2>Activity</h2><span class="scale">Less <i style="background:hsl(0 0% 100% / .05)"></i><i style="background:hsl(0 0% 100% / .18)"></i><i style="background:hsl(0 0% 100% / .36)"></i><i style="background:hsl(0 0% 100% / .6)"></i><i style="background:hsl(0 0% 100% / .9)"></i> More</span></div>
      <div class="card-body chart">${heatmap(usage.heatmap)}</div>
      <div class="facts">
        <div><b>${s.current}</b><span>day streak</span></div>
        <div><b>${s.longest}</b><span>longest streak</span></div>
        <div><b>${s.activeDays}</b><span>active days, 26 weeks</span></div>
      </div>
    </section>`;
  }

  function heatmap(days) {
    if (!days.length) return "";
    const parse = (day) => new Date(day + "T00:00:00");
    const offset = (parse(days[0].day).getDay() + 6) % 7;
    const columns = Math.ceil((days.length + offset) / 7);
    const gap = 3, top = 18;
    const size = Math.max(9, Math.min(16, Math.floor((chartWidth("wide") - (columns - 1) * gap) / columns)));
    const active = days.map((d) => d.tokens).filter((v) => v > 0).sort((a, b) => a - b);
    const quartile = (q) => (active.length ? active[Math.min(active.length - 1, Math.floor(q * active.length))] : 0);
    const cuts = [quartile(0.25), quartile(0.5), quartile(0.75)];
    let cells = "", lastMonth = -1;
    const labels = [];
    days.forEach((day, i) => {
      const slot = i + offset, col = Math.floor(slot / 7), row = slot % 7;
      const level = !day.tokens ? 0 : day.tokens <= cuts[0] ? 1 : day.tokens <= cuts[1] ? 2 : day.tokens <= cuts[2] ? 3 : 4;
      const date = parse(day.day);
      if (row === 0 && date.getMonth() !== lastMonth && col < columns - 2) {
        labels.push({ col, text: fmt.day(date, { month: "short" }) });
        lastMonth = date.getMonth();
      }
      cells += `<rect class="l${level}" x="${col * (size + gap)}" y="${top + row * (size + gap)}" width="${size}" height="${size}" rx="2.5"${day.tokens && !isStatic && ui.section === "usage" ? ` data-action="day" data-value="${day.day}"` : ""}${tipAttr(fmt.day(date, { weekday: "short", month: "short", day: "numeric" }), day.tokens ? [["Tokens", fmt.tokens(day.tokens)], ["API value", fmt.usd(day.cost)], ["Requests", fmt.count(day.requests)]] : [["No usage", ""]])}/>`;
    });
    // A month that starts a column or two before the next one has no room for its name; the
    // next month's name wins rather than the two running into each other.
    const months = labels.filter((label, i) => !labels[i + 1] || labels[i + 1].col - label.col >= 3)
      .map((label) => `<text x="${label.col * (size + gap)}" y="11">${esc(label.text)}</text>`).join("");
    const width = columns * (size + gap) - gap, height = top + 7 * (size + gap) - gap;
    return `<svg class="heat" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" role="img" aria-label="Daily activity over 26 weeks">${months}${cells}</svg>`;
  }

  function mixBlock(t) {
    const parts = [
      ["Input", t.input, "m1"],
      ["Output", t.output, "m2"],
      ["Cache reads", t.cacheRead, "m3"],
      ["Cache writes", t.cacheWrite, "m4"],
      ["1h cache writes", t.cacheWrite1h || 0, "m5"],
    ];
    const sum = parts.reduce((s, p) => s + p[1], 0) || 1;
    const rows = parts.filter((p) => p[1] > 0 || p[0] !== "1h cache writes");
    const reasoning = t.reasoning
      ? `<p class="subtle" style="margin:10px 0 0;font-size:12px">Reasoning is ${fmt.tokens(t.reasoning)} of output, counted once.</p>`
      : "";
    return `<div class="mix-bar">${rows.filter((p) => p[1] > 0).map((p) => `<span class="${p[2]}" style="width:${((p[1] / sum) * 100).toFixed(2)}%" data-grow="mix:${esc(ui.tool)}:${p[2]}"${tipAttr(p[0], [["Tokens", fmt.tokens(p[1])], ["Share", `${Math.round((p[1] / sum) * 100)}%`]])}></span>`).join("")}</div>
      <table class="table" style="margin:0 -16px -16px;width:calc(100% + 32px)"><tbody>${rows.map((p) => `<tr><td><div class="cell-name"><span class="swatch ${p[2]}"></span><span>${p[0]}</span></div></td><td class="right mono">${fmt.tokens(p[1])}</td><td class="right mono subtle">${Math.round((p[1] / sum) * 100)}%</td></tr>`).join("")}</tbody></table>${reasoning}`;
  }


  // Whose models did the work, whichever tool ran them, with each maker's share of the range.
  function makerTable(makers, metric) {
    const value = (m) => (metric === "tokens" ? m.figures.tokens : m.figures.cost);
    const sum = makers.reduce((s, m) => s + value(m), 0) || 1;
    const peak = Math.max(0.000001, ...makers.map(value));
    const rows = makers.slice().sort((a, b) => value(b) - value(a)).map((m) => `<tr>
      <td><b>${esc(m.name)}</b><div class="subtle" style="font-size:11.5px" title="${esc(m.models.join(", "))}">${m.models.length} model${m.models.length === 1 ? "" : "s"}</div></td>
      <td class="bar-cell">${progress((value(m) / peak) * 100, null, "plain", `row:${ui.tool}:${metric}:${m.tool || ""}:${m.model || m.name}`)}</td>
      <td class="right mono">${metric === "tokens" ? fmt.tokens(m.figures.tokens) : fmt.usd(m.figures.cost)}</td>
      <td class="right mono subtle">${Math.round((value(m) / sum) * 100)}%</td>
    </tr>`).join("");
    return `<table class="table"><thead><tr><th>Maker</th><th></th><th class="right">${metric === "tokens" ? "Tokens" : "API value"}</th><th class="right">Share</th></tr></thead><tbody>${rows}</tbody></table>`;
  }

  // Each repository or folder, most used first. Usage no tool placed in a folder closes the list
  // and says so, rather than being left out and making the rows add up to less than the total.
  function projectTable(projects, metric) {
    const value = (p) => (metric === "tokens" ? p.figures.tokens : p.figures.cost);
    const peak = Math.max(0.000001, ...projects.map(value));
    const shown = projects.slice(0, 12);
    const rows = shown.map((p) => `<tr>
      <td>${p.path ? `<b>${esc(p.name)}</b><div class="subtle mono" style="font-size:11px">${esc(p.path)}</div>` : `<span class="subtle">${esc(p.name)}</span>`}</td>
      <td class="bar-cell">${progress((value(p) / peak) * 100, null, "plain", `project:${ui.tool}:${metric}:${p.path || ""}`)}</td>
      <td class="right mono">${metric === "tokens" ? fmt.tokens(p.figures.tokens) : fmt.usd(p.figures.cost)}</td>
    </tr>`).join("");
    const more = projects.length > shown.length ? `<p class="empty-inline" style="padding:10px 16px">and ${projects.length - shown.length} more</p>` : "";
    return `<table class="table"><thead><tr><th>Project</th><th></th><th class="right">${metric === "tokens" ? "Tokens" : "API value"}</th></tr></thead><tbody>${rows}</tbody></table>${more}`;
  }


  function sessionTable(sessions, metric) {
    const rows = sessions.map((s) => `<tr>
      <td><div class="cell-name">${mark(s.tool)}<span>${esc(toolName(s.tool))}</span></div><div class="subtle" style="font-size:12px;margin-left:26px">${esc(s.account)}</div></td>
      <td><span class="mono">${esc(s.model)}</span></td>
      <td class="subtle">${esc(fmt.clock(s.from))} to ${esc(fmt.clock(s.to))}</td>
      <td class="right mono">${metric === "tokens" ? fmt.tokens(s.figures.tokens) : fmt.usd(s.figures.cost)}</td>
    </tr>`).join("");
    return `<table class="table"><thead><tr><th>Session</th><th>Model</th><th>When</th><th class="right">${metric === "tokens" ? "Tokens" : "API value"}</th></tr></thead><tbody>${rows}</tbody></table>`;
  }

  function exportCSV(usage) {
    const cell = (v) => `"${String(v ?? "").replace(/"/g, '""')}"`;
    const lines = [["Kind", "Name", "Tool", "Tokens", "API value", "Requests", "Input", "Output", "Cache read", "Cache write"].map(cell).join(",")];
    (usage.periods || []).slice().reverse().forEach((r) => { const f = r.figures; lines.push([usage.bucket[0].toUpperCase() + usage.bucket.slice(1), new Date(r.start).toISOString(), usage.tool, f.tokens, f.cost.toFixed(4), f.requests, f.input, f.output, f.cacheRead, f.cacheWrite + (f.cacheWrite1h || 0)].map(cell).join(",")); });
    (usage.tools || []).forEach((t) => lines.push(["Tool", t.name, t.id, t.figures.tokens, t.figures.cost.toFixed(4), t.figures.requests].map(cell).join(",")));
    (usage.models || []).forEach((m) => lines.push(["Model", m.model, m.tool || "", m.figures.tokens, m.figures.cost.toFixed(4), m.figures.requests].map(cell).join(",")));
    (usage.accounts || []).forEach((a) => lines.push(["Account", a.name, a.tool, a.figures.tokens, a.figures.cost.toFixed(4), a.figures.requests].map(cell).join(",")));
    (usage.sessions || []).forEach((s) => lines.push(["Session", s.model, s.tool, s.figures.tokens, s.figures.cost.toFixed(4), s.figures.requests].map(cell).join(",")));
    const blob = new Blob([lines.join("\n")], { type: "text/csv" });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `keyhop-usage-${usage.range}.csv`;
    link.click();
    URL.revokeObjectURL(link.href);
    toast(`Saved keyhop-usage-${usage.range}.csv`);
  }

  function accountTable(accounts, metric) {
    const value = (a) => (metric === "tokens" ? a.figures.tokens : a.figures.cost);
    const sorted = accounts.slice().sort((a, b) => value(b) - value(a));
    const rows = sorted.map((a) => `<tr>
      <td><div class="cell-name"><span class="swatch" style="background:${a.color}"></span><span>${esc(a.name)}</span></div><div class="subtle" style="font-size:12px;margin-left:16px">${esc(toolName(a.tool))}${a.active ? " · in use" : ""}</div></td>
      <td class="right mono">${metric === "tokens" ? fmt.tokens(a.figures.tokens) : fmt.usd(a.figures.cost)}</td>
    </tr>`).join("");
    return `<table class="table"><thead><tr><th>Account</th><th class="right">${metric === "tokens" ? "Tokens" : "API value"}</th></tr></thead><tbody>${rows}</tbody></table>`;
  }

  // MARK: Budgets

  function periodProgress(period) {
    const now = new Date();
    let start, end;
    if (period === "day") { start = new Date(now.getFullYear(), now.getMonth(), now.getDate()); end = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1); }
    else if (period === "week") { start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - ((now.getDay() + 6) % 7)); end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 7); }
    else { start = new Date(now.getFullYear(), now.getMonth(), 1); end = new Date(now.getFullYear(), now.getMonth() + 1, 1); }
    return { start, end, elapsed: Math.min(1, Math.max(0.02, (now - start) / (end - start))) };
  }

  function budgetsPage(tools) {
    const status = data.state.status;
    const accounts = tools.flatMap((t) => t.accounts.map((a) => ({ ...a, toolName: t.name })));
    const editing = ui.budgetEdit ? status.budgets.find((b) => b.scope === ui.budgetEdit) : null;
    const scopeValue = editing ? (editing.scope === "all" ? "all" : editing.scope.replace("account:", "")) : "all";
    const list = status.budgets.length ? `<div class="list">${status.budgets.map((b) => `
      <div class="row budget-row">
        ${budgetRow(b).replace(/^<div class="row budget-row">|<\/div>\s*$/g, "")}
        ${isStatic ? "" : `<div class="row-actions" style="justify-content:flex-start;margin-left:-10px"><button class="btn sm ghost" data-action="edit-budget" data-scope="${esc(b.scope)}">Change</button><button class="btn sm ghost danger" data-action="delete-budget" data-scope="${esc(b.scope)}">Remove</button></div>`}
      </div>`).join("")}</div>` : `<p class="empty">No budgets yet. A budget counts what you are charged where a provider reports it, the tokens at API prices elsewhere, and warns you at 80% and 100%.</p>`;
    const form = isStatic ? "" : `<section class="card">
      <div class="card-head"><h2>${editing ? "Change budget" : "New budget"}</h2></div>
      <form class="form" data-form="budget">
        <label>Applies to<select class="field" name="scope"><option value="all" ${scopeValue === "all" ? "selected" : ""}>All accounts</option>${accounts.map((a) => `<option value="${esc(a.id)}" ${scopeValue === a.id ? "selected" : ""}>${esc(a.toolName)} · ${esc(a.name)}</option>`).join("")}</select></label>
        <div class="pair">
          <label>Amount (USD)<input class="field mono" name="amount" inputmode="decimal" placeholder="200" value="${editing ? esc(editing.amount) : ""}" required></label>
          <label>Period<select class="field" name="period">${[["day", "Daily"], ["week", "Weekly"], ["month", "Monthly"]].map(([v, l]) => `<option value="${v}" ${(editing ? editing.period : "month") === v ? "selected" : ""}>${l}</option>`).join("")}</select></label>
        </div>
        <div class="row-actions" style="justify-content:flex-start">${editing ? `<button type="button" class="btn sm ghost" data-action="cancel-budget">Cancel</button>` : ""}<button class="btn sm">Save budget</button></div>
      </form>
    </section>`;
    const month = data.usage["month:all"];
    const overall = status.budgets.find((b) => b.scope === "all" && b.period === "month");
    const byAccount = !month ? loading("Reading this month's usage", "empty") : month.total.requests ? accountTable(month.accounts, "cost") : `<p class="empty">No usage this month yet.</p>`;
    return { body: `
      <div class="split wide-left">
        <section class="card"><div class="card-head"><h2>Budgets</h2><span class="hint mono">${status.budgets.length}</span></div>${list}</section>
        ${form || "<div></div>"}
      </div>
      <div class="split wide-left">
        ${spendCard(month, overall)}
        <section class="card"><div class="card-head"><h2>Spend by account</h2><span class="hint">This month</span></div>${byAccount}</section>
      </div>` };
  }

  function spendCard(usage, budget) {
    if (!usage) return `<section class="card"><div class="card-head"><h2>This month</h2></div>${loading("Reading this month's usage", "empty")}</section>`;
    const now = Date.now();
    let running = 0;
    const points = [];
    usage.buckets.forEach((bucket, i) => {
      if (new Date(bucket.start).getTime() > now) return;
      running += Object.values(bucket.values).reduce((sum, v) => sum + v.cost, 0);
      points.push({ i, total: running });
    });
    const days = usage.buckets.length;
    // As tall as the spend list beside it (a row per account), so the two cards end together.
    const rows = (usage.accounts || []).length;
    const W = chartWidth("wide"), H = Math.max(220, Math.min(440, 59 * rows - 72)), L = 52, R = 8, T = 16, B = 26;
    const pw = W - L - R, ph = H - T - B;
    const ceiling = niceCeiling(Math.max(running, budget ? budget.amount : 0) * 1.08);
    const x = (i) => L + (days > 1 ? (i / (days - 1)) * pw : pw / 2);
    const y = (v) => T + ph - (v / ceiling) * ph;
    let grid = "";
    for (let step = 0; step <= 4; step++) {
      const value = (ceiling / 4) * step, yy = y(value).toFixed(1);
      grid += `<line class="${step ? "grid" : "base"}" x1="${L}" x2="${W - R}" y1="${yy}" y2="${yy}"/><text class="axis" x="${L - 8}" y="${yy}" text-anchor="end" dominant-baseline="central">${value === 0 ? "$0" : fmt.usd(value)}</text>`;
    }
    [0, Math.floor((days - 1) / 2), days - 1].forEach((i) => {
      grid += `<text class="axis" x="${x(i).toFixed(1)}" y="${H - 7}" text-anchor="${i === 0 ? "start" : i === days - 1 ? "end" : "middle"}">${esc(fmt.day(usage.buckets[i].start, { month: "short", day: "numeric" }))}</text>`;
    });
    let marks = "";
    if (budget) {
      const by = y(budget.amount).toFixed(1);
      marks += `<line x1="${L}" x2="${W - R}" y1="${by}" y2="${by}" stroke="hsl(0 0% 100% / .4)" stroke-dasharray="4 5"/><text class="axis" x="${W - R}" y="${(y(budget.amount) - 7).toFixed(1)}" text-anchor="end">budget ${fmt.usd(budget.amount)}</text>`;
      marks += `<line x1="${x(0).toFixed(1)}" y1="${y(0).toFixed(1)}" x2="${x(days - 1).toFixed(1)}" y2="${by}" stroke="hsl(0 0% 100% / .12)"/>`;
    }
    let line = "";
    if (points.length) {
      const path = points.map((p, k) => `${k ? "L" : "M"}${x(p.i).toFixed(1)},${y(p.total).toFixed(1)}`).join("");
      const last = points[points.length - 1];
      line = `<path d="${path}L${x(last.i).toFixed(1)},${y(0).toFixed(1)}L${x(points[0].i).toFixed(1)},${y(0).toFixed(1)}Z" fill="hsl(0 0% 100% / .05)"/><path d="${path}" fill="none" stroke="hsl(0 0% 92%)" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"/><circle cx="${x(last.i).toFixed(1)}" cy="${y(last.total).toFixed(1)}" r="3.5" fill="hsl(0 0% 92%)"/>`;
    }
    const elapsed = periodProgress("month").elapsed;
    return `<section class="card">
      <div class="card-head"><h2>This month</h2><span class="hint mono">${running > 0 ? `${fmt.usd(running)} · pace ${fmt.usd(running / elapsed)}` : "$0"}</span></div>
      <div class="card-body chart"><svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="Spend this month, added up by day">${grid}${marks}${line}</svg>
      ${budget ? "" : `<p class="empty-inline subtle" style="margin-top:8px">Add a monthly budget for all accounts to compare against it.</p>`}</div>
      <div class="facts">
        <div><b data-count="${running}" data-count-key="budget-spent" data-format="usd">${fmt.usd(running)}</b><span>spent so far</span></div>
        <div><b data-count="${running / elapsed}" data-count-key="budget-pace" data-format="usd">${fmt.usd(running / elapsed)}</b><span>on pace for the month</span></div>
        <div><b>${Math.max(0, Math.ceil((periodProgress("month").end - Date.now()) / 86400000))}</b><span>${budget ? `days left of ${fmt.usd(budget.amount)}` : "days left"}</span></div>
      </div>
    </section>`;
  }

  // MARK: Backdrop

  let backdrop = null;
  let backdropImage = null;
  let backdropImageLoading = false;

  async function applyBackdrop() {
    const host = $("#backdrop");
    if (!host || !window.KeyhopBackdrop) return;
    const look = data.state?.appearance || { scene: "leaves", opacity: 0.8, scope: "all", image: false, glass: 1 };
    applyGlass(look.glass ?? 1, look.blur ?? 24);
    let scene = look.scene;
    if (scene === "image") {
      if (!look.image || isStatic) scene = "leaves";
      else if (!backdropImage && !backdropImageLoading) {
        backdropImageLoading = true;
        try { backdropImage = (await api("/api/appearance/image")).dataUrl; } catch { scene = "leaves"; } finally { backdropImageLoading = false; }
      }
    }
    document.documentElement.classList.toggle("has-backdrop", scene !== "off");
    host.classList.toggle("scoped-out", look.scope === "overview" && ui.section !== "overview");
    const options = { scene, opacity: look.opacity, image: scene === "image" ? backdropImage : null };
    if (backdrop) backdrop.update(options);
    else backdrop = window.KeyhopBackdrop.mount(host, options);
  }

  // Below full window opacity, the Mac app's whole window is glass over the blurred desktop.
  let sentBlur = null;
  function applyGlass(glass, blur) {
    const root = document.documentElement;
    const mac = root.classList.contains("mac-window");
    root.classList.toggle("has-glass", mac && glass < 1);
    root.style.setProperty("--glass", String(glass));
    const radius = glass < 1 ? blur : 0;
    if (mac && radius !== sentBlur) {
      sentBlur = radius;
      window.webkit?.messageHandlers?.keyhopWindow?.postMessage("blur:" + radius);
    }
  }

  async function setAppearance(change) {
    try {
      const result = await api("/api/appearance", change);
      data.state.appearance = result.appearance;
      if (change.image !== undefined) backdropImage = change.image || null;
      if (change.image !== undefined) toast(result.message);
      render();
      applyBackdrop();
    } catch (error) {
      toast(error.message, true);
    }
  }

  // Pictures are shrunk here before upload, so a camera photo never reaches the size limit.
  function shrinkPicture(file) {
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file);
      const image = new Image();
      image.onload = () => {
        URL.revokeObjectURL(url);
        let size = 1600, quality = 0.84, result = "";
        do {
          const scale = Math.min(1, size / Math.max(image.width, image.height));
          const canvas = document.createElement("canvas");
          canvas.width = Math.max(1, Math.round(image.width * scale));
          canvas.height = Math.max(1, Math.round(image.height * scale));
          canvas.getContext("2d").drawImage(image, 0, 0, canvas.width, canvas.height);
          result = canvas.toDataURL("image/jpeg", quality);
          size = Math.round(size * 0.8);
          quality = Math.max(0.6, quality - 0.08);
        } while (result.length > 900000 && size > 200);
        resolve(result);
      };
      image.onerror = () => { URL.revokeObjectURL(url); reject(new Error("That file isn't a picture Keyhop can read.")); };
      image.src = url;
    });
  }

  function appearanceCard() {
    const look = data.state.appearance;
    const pick = (key, list, current) => `<div class="tabs">${list.map(([value, label]) => {
      const locked = key === "scene" && value === "image" && !look.image;
      return `<button data-action="appearance" data-key="${key}" data-value="${value}" aria-pressed="${value === current}"${locked ? ` disabled title="Choose a picture first"` : ""}>${label}</button>`;
    }).join("")}</div>`;
    const about = {
      leaves: "Dark leaves swaying on their stems, a few drifting down.",
      dunes: "A desert world's horizon, turning slowly under the stars.",
      orbit: "A ringed planet floating in the dark.",
      arcade: "Pixel runners racing along a ridge of pixel hills.",
      image: "Your picture, softly behind everything.",
      off: "A plain surface.",
    }[look.scene];
    return `<section class="card"><div class="card-head"><h2>Backdrop</h2><span class="hint">Window scene & material</span></div>
      <div class="list">
        <div class="row setting-row"><div><b>Scene</b><p>${about}</p></div>${pick("scene", [["leaves", "Leaves"], ["dunes", "Dunes"], ["orbit", "Orbit"], ["arcade", "Arcade"], ["image", "Picture"], ["off", "Off"]], look.scene)}</div>
        <div class="row setting-row"><div><b>Show on</b><p>${look.scope === "overview" ? "Only behind Overview." : "Behind every section."}</p></div>${pick("scope", [["all", "Everywhere"], ["overview", "Overview only"]], look.scope)}</div>
        <div class="row setting-row"><div><b>Opacity</b><p>How strongly the scene shows through.</p></div>
          <input class="range" type="range" min="10" max="100" step="5" value="${Math.round(look.opacity * 100)}" data-appearance="opacity" aria-label="Opacity"${look.scene === "off" ? " disabled" : ""}></div>
        ${document.documentElement.classList.contains("mac-window") ? `<div class="row setting-row"><div><b>Window opacity</b><p>${look.glass >= 1 ? "A solid window." : "The whole window is glass over your desktop."}</p></div>
          <input class="range" type="range" min="15" max="100" step="5" value="${Math.round(look.glass * 100)}" data-appearance="glass" aria-label="Window opacity"></div>
        <div class="row setting-row"><div><b>Blur</b><p>How softly the desktop shows through.</p></div>
          <input class="range" type="range" min="1" max="64" step="1" value="${look.blur}" data-appearance="blur" aria-label="Blur"${look.glass >= 1 ? " disabled" : ""}></div>` : ""}
        <div class="row setting-row"><div><b>Picture</b><p>${look.image ? "Saved in Keyhop's data folder." : "Any photo or artwork. It sits behind a soft veil, so text stays readable."}</p></div>
          <div class="row-actions"><label class="btn sm secondary">${look.image ? "Replace picture" : "Choose picture"}<input type="file" accept="image/*" data-appearance="image" hidden></label>
          ${look.image ? `<button class="btn sm ghost" data-action="appearance-clear">Remove</button>` : ""}</div></div>
      </div></section>`;
  }

  // MARK: Leaderboard

  function ago(iso) {
    const seconds = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
    if (seconds < 60) return "just now";
    if (seconds < 3600) return `${Math.floor(seconds / 60)} min ago`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)} h ago`;
    return `${Math.floor(seconds / 86400)} d ago`;
  }

  function workCard(work) {
    if (!work) return "";
    if (!work.gitAvailable) {
      return `<section class="card"><div class="card-head"><h2>What you shipped</h2></div>
        <div class="card-body"><p class="empty-inline">git isn't installed, so Keyhop can't count commits on this computer.</p></div></section>`;
    }
    const folders = work.roots.length
      ? `<div class="list">${work.roots.map((path) => `<div class="row setting-row"><div><b class="mono" style="font-size:12.5px">${esc(path)}</b></div>
          ${isStatic ? "" : `<button class="btn sm ghost" data-action="work-remove" data-path="${esc(path)}">Remove folder</button>`}</div>`).join("")}</div>`
      : `<p class="empty">No folders yet. Add one below, or Keyhop will offer the usual ones when you turn this on.</p>`;
    const index = work.index && work.index.total
      ? (work.index.complete
        ? `Indexed ${work.index.total} ${work.index.total === 1 ? "repository" : "repositories"}.`
        : `Indexing: ${work.index.done} of ${work.index.total} repositories, so figures are still filling in.`)
      : "";
    const synced = work.lastSync ? `Last sent ${esc(ago(work.lastSync))}.` : "Not sent yet.";
    const toggle = work.enabled
      ? `<button class="btn sm ghost" data-action="work-off">Stop counting</button>`
      : `<button class="btn sm" data-action="work-on">Count commits</button>`;
    const subjects = work.shareSubjects
      ? `<div class="card-body setting-row"><div><b>Subject lines are shared</b><p>The first line of each commit goes with the counts, so a day can be read as tasks. Turning this off deletes the ones already sent.</p></div>
          <button class="btn sm ghost" data-action="work-subjects-off">Keep subjects here</button></div>`
      : `<div class="card-body setting-row"><div><b>Keep subject lines here</b><p>Counts still go. The words you wrote stay on this computer until you share them.</p></div>
          <button class="btn sm secondary" data-action="work-subjects-on">Share subject lines</button></div>`;
    const add = isStatic ? "" : `<form class="form" data-form="work-folder" style="padding-top:0">
      <label>Folder to scan<input class="field" name="folder" placeholder="~/Projects" autocomplete="off"></label>
      <div class="row-actions" style="justify-content:flex-start"><button class="btn sm secondary">Add folder</button></div>
    </form>`;
    return `<section class="card"><div class="card-head"><h2>What you shipped</h2>${work.enabled ? `<span class="badge live">On</span>` : ""}</div>
      <div class="card-body setting-row"><div><b>Count the commits you author</b>
        <p>Token totals say what a day cost. This adds what came out of it, from the git repositories already on this computer. Paths and diffs never leave. ${index} ${synced}</p></div>
        ${toggle}</div>
      ${work.enabled ? `${subjects}${folders}${add}` : ""}
    </section>`;
  }

  function cloudCard(cloud) {
    if (cloud.linking) {
      return `<section class="card"><div class="card-head"><h2>Leaderboard</h2><span class="badge">Waiting</span></div>
        <div class="card-body setting-row"><div><b>Approve <span class="mono">${esc(cloud.linking.userCode)}</span> in your browser</b>
          <p>Sign in with GitHub, check that the code matches, and approve it. This page notices by itself.</p></div>
          <div class="row-actions"><a class="btn sm" href="${esc(cloud.linking.verifyUrl)}" target="_blank" rel="noopener">Open sign-in</a>
          <button class="btn sm ghost" data-action="cloud-unlink">Cancel</button></div></div></section>`;
    }
    if (!cloud.linked) {
      return `<section class="card"><div class="card-head"><h2>Leaderboard</h2></div>
        <div class="card-body setting-row"><div><b>Compare your usage with friends and teams</b>
          <p>Link with GitHub to join leaderboards and get a profile you can share. Keyhop sends tokens, API value and requests per tool per day. Never prompts, emails or account names.</p></div>
          <button class="btn sm" data-action="cloud-link">Link with GitHub</button></div></section>`;
    }
    const synced = cloud.lastSyncError ? `The last sync failed: ${esc(cloud.lastSyncError)}` : cloud.lastSync ? `Synced ${esc(ago(cloud.lastSync))}` : "Not synced yet";
    const limits = cloud.sharesLimits
      ? `<div class="card-body setting-row"><div><b>Your phone can see your limits</b>
          <p>How full each account is, when it comes back, and the name you gave it. No emails, and nothing about what you asked.</p></div>
          <button class="btn sm ghost danger" data-action="cloud-limits-off">Stop sharing</button></div>`
      : `<div class="card-body setting-row"><div><b>Let your phone see your limits</b>
          <p>The Keyhop app on your phone can then tell you when an account comes back. It sends how full each account is and the name you gave it, never an email.</p></div>
          <button class="btn sm secondary" data-action="cloud-limits-on">Share limits</button></div>`;
    return `<section class="card"><div class="card-head"><h2>Leaderboard</h2><span class="badge live">Linked</span></div>
      <div class="card-body setting-row"><div><b>@${esc(cloud.login)}${cloud.isPublic ? "" : " · private profile"}</b>
        <p>${synced}. Daily totals go out hourly, after a refresh.</p></div>
        <div class="row-actions"><a class="btn sm secondary" href="${esc(cloud.profile)}" target="_blank" rel="noopener">Open profile</a>
        <button class="btn sm secondary" data-action="cloud-sync">Sync now</button>
        <button class="btn sm ghost danger" data-action="cloud-unlink">Unlink</button></div></div>
      ${limits}</section>`;
  }

  // Six squares climbing to the right, lit as far as the tier has come.
  function tierMark(key) {
    const steps = { bronze: 1, silver: 2, gold: 3, platinum: 4, diamond: 5, master: 6 }[key] || 1;
    const cells = Array.from({ length: 6 }, (_, index) => {
      const height = 3 + index * 2.4;
      return `<rect x="${index * 4}" y="${(17 - height).toFixed(1)}" width="3" height="${height.toFixed(1)}" rx="1" fill-opacity="${index < steps ? 1 : 0.22}"/>`;
    }).join("");
    return `<svg viewBox="0 0 23 18" aria-hidden="true">${cells}</svg>`;
  }

  function tierTag(tier, size) {
    const roman = ["", "I", "II", "III"][tier.division || 0];
    return `<span class="tier tier-${esc(tier.key)}${size === "sm" ? " sm" : ""}">${tierMark(tier.key)}<span>${esc(tier.name)}${roman ? ` ${roman}` : ""}</span></span>`;
  }

  // This month's ranked season, above the board.
  function seasonRow(season, website) {
    if (!season) return "";
    const you = season.you;
    const left = season.over ? "Finished" : season.daysLeft === 1 ? "Ends today" : `${season.daysLeft} days left`;
    const note = !you || you.rank === null || you.rank === undefined
      ? "Sync some usage this month to take a place."
      : you.next
        ? `${fmt.tokens(you.next.tokens)} more tokens for ${esc(you.next.label)}.`
        : "You're at the top of the ladder.";
    const place = you && you.rank ? `#${you.rank} of ${season.players}. ` : "";
    return `<section class="card season-row">
      ${tierTag(you ? you.tier : { key: "bronze", name: "Bronze", division: 3 })}
      <div class="grow"><b>${esc(season.label)} · ${esc(left)}</b><p>${place}${note}</p></div>
      <a class="btn sm secondary" href="${esc(website)}/season" target="_blank" rel="noopener">Open season</a>
    </section>`;
  }

  // The same goals the website shows, so the window and the site never disagree.
  function questsCard(quests) {
    if (!quests || !quests.quests || quests.quests.length === 0) return "";
    const done = quests.quests.filter((goal) => goal.complete).length;
    const row = (goal) => `<div class="quest-row${goal.complete ? " done" : ""}">
      <div><b>${esc(goal.name)}</b><p>${esc(goal.note)}</p></div>
      <div><div class="quest-track"><span style="width:${Math.max(0, Math.min(100, Math.round((goal.done / goal.target) * 100)))}%"></span></div>
        <div class="quest-state">${goal.complete ? "Done" : goal.target <= 7 ? `${goal.done} of ${goal.target}` : `${Math.round((goal.done / goal.target) * 100)}%`}</div></div>
    </div>`;
    return `<section class="card"><div class="card-head"><h2>Quests</h2><span class="hint">${done} of ${quests.quests.length} done</span></div>
      ${quests.quests.map(row).join("")}</section>`;
  }

  function leaderboardPage() {
    const cloud = data.state.cloud;
    if (!cloud.linked || cloud.linking) return { body: cloudCard(cloud) };
    const choice = (action, options, current) => `<div class="tabs">${options.map(([value, label]) => `<button data-action="${action}" data-value="${value}" aria-pressed="${value === current}">${label}</button>`).join("")}</div>`;
    const teams = data.board?.teams || [];
    const toolbar = `${teams.length ? `<select class="field" data-action="board-team"><option value="">Everyone</option>${teams.map((team) => `<option value="${esc(team.slug)}"${team.slug === ui.boardTeam ? " selected" : ""}>${esc(team.name)}</option>`).join("")}</select>` : ""}
      ${choice("board-period", [["today", "Today"], ["week", "7 days"], ["month", "30 days"], ["all", "All time"]], ui.boardPeriod)}
      ${choice("board-metric", [["tokens", "Tokens"], ["cost", "API value"], ["requests", "Requests"]], ui.boardMetric)}`;
    if (data.boardError) return { toolbar, body: `<div class="notice">${icon("alert")}<div><p>${esc(data.boardError)}</p></div></div>` };
    if (!data.board) return { toolbar, body: busy("Reading the leaderboard", "lede") };

    const entries = data.board.board.entries;
    const site = data.board.website;
    const value = (e) => ui.boardMetric === "cost" ? fmt.usd(e.cost) : ui.boardMetric === "requests" ? Math.round(e.requests).toLocaleString() : fmt.tokens(e.tokens);
    const avatar = (e, size) => `<span class="avatar" style="width:${size}px;height:${size}px;font-size:${Math.round(size * 0.42)}px" aria-hidden="true">${esc(e.login.slice(0, 1).toUpperCase())}</span>`;
    const person = (e, size) => `<div class="who">${avatar(e, size)}<div><b>${esc(e.name || e.login)}</b><small>@${esc(e.login)}</small></div></div>`;
    const mix = (e) => {
      const parts = [["claude", "m1"], ["cursor", "m2"], ["codex", "m3"], ["gemini", "m4"]].filter(([tool]) => (e.tools[tool] || 0) > 0);
      const total = parts.reduce((sum, [tool]) => sum + e.tools[tool], 0);
      return `<div class="mix-bar">${parts.map(([tool, tone]) => `<span class="${tone}" style="width:${(e.tools[tool] / total * 100).toFixed(2)}%" title="${esc(toolName(tool))} ${fmt.tokens(e.tools[tool])}"></span>`).join("")}</div>`;
    };
    const me = entries.find((e) => e.isYou);
    const ahead = me && me.rank > 1 ? entries[me.rank - 2] : null;
    const scope = ui.boardTeam ? (teams.find((team) => team.slug === ui.boardTeam)?.name || "your team") : "the global board";
    const gap = ahead ? value({ tokens: ahead.tokens - me.tokens, cost: ahead.cost - me.cost, requests: ahead.requests - me.requests }) : null;

    const stats = `<div class="stats">
      <div class="card stat"><div class="label">Your rank</div><div class="value">${me ? `#${me.rank}` : "Unranked"}</div>
        <div class="foot">${me ? `of ${entries.length} on ${esc(scope)}` : cloud.isPublic || ui.boardTeam ? "Nothing synced for this period" : "Private profiles rank only on teams"}</div></div>
      <div class="card stat"><div class="label">You</div><div class="value">${me ? esc(value(me)) : "0"}</div>
        <div class="foot">${me ? `${me.activeDays} active ${me.activeDays === 1 ? "day" : "days"}` : "&nbsp;"}</div></div>
      <div class="card stat"><div class="label">${ahead ? `To catch @${esc(ahead.login)}` : "Ahead of you"}</div><div class="value">${gap ? esc(gap) : me ? "Nobody" : "&nbsp;"}</div>
        <div class="foot">${ahead ? `They're #${ahead.rank}` : me ? "You lead this board" : "&nbsp;"}</div></div>
      <div class="card stat"><div class="label">Profile</div><div class="value"><a class="plain-link" href="${esc(cloud.profile)}" target="_blank" rel="noopener">@${esc(cloud.login)}</a></div>
        <div class="foot">${cloud.lastSync ? `Synced ${esc(ago(cloud.lastSync))}` : "Not synced yet"}</div></div>
    </div>`;
    const podium = entries.length ? `<div class="podium">${entries.slice(0, 3).map((e) => `<div class="card podium-card${e.isYou ? " you" : ""}">
        <span class="place mono">#${e.rank}</span>${person(e, 36)}<div class="podium-value">${esc(value(e))}</div>${mix(e)}</div>`).join("")}</div>` : "";
    const heading = { tokens: "Tokens", cost: "API value", requests: "Requests" }[ui.boardMetric];
    const table = entries.length
      ? `<section class="card"><table class="table"><thead><tr><th style="width:52px">#</th><th>Person</th><th>Tools</th><th class="right">Active days</th><th class="right">${heading}</th></tr></thead>
          <tbody>${entries.map((e) => `<tr class="${e.isYou ? "me" : ""}"><td class="mono subtle">${e.rank}</td><td>${person(e, 26)}</td><td class="bar-cell">${mix(e)}</td>
          <td class="right mono subtle">${e.activeDays}</td><td class="right mono">${esc(value(e))}</td></tr>`).join("")}</tbody></table></section>`
      : `<section class="card"><p class="empty">No usage yet for this period. It fills in as the computers on your board refresh.</p></section>`;
    const note = `<p class="empty-inline subtle">Create teams and invite people on <a href="${esc(site)}/teams" target="_blank" rel="noopener">the website</a>.${cloud.isPublic ? "" : ` Your profile is private; make it public in the <a href="${esc(site)}/settings" target="_blank" rel="noopener">website's settings</a> to join the global board.`}</p>`;
    return { toolbar, body: seasonRow(data.board.season, site) + stats + questsCard(data.board.quests) + podium + table + note };
  }

  // MARK: Settings

  function settingsPage() {
    const state = data.state, doctor = data.doctor, update = data.update;
    let updateRow;
    if (isStatic) updateRow = `<div class="setting-row"><div><b>Version</b><p>Saved from Keyhop ${esc(state.version)}</p></div></div>`;
    else if (ui.checkingUpdate) updateRow = `<div class="setting-row"><div><b>Checking for updates…</b><p class="update-status" role="status"><span class="ring" aria-hidden="true"></span>Asking GitHub for the latest release</p></div></div>`;
    else if (data.updateError) updateRow = `<div class="setting-row"><div><b>Couldn’t check for updates</b><p>${esc(data.updateError)} Try again when you’re connected.</p></div><button class="btn sm secondary" data-action="check-update">Try Again</button></div>`;
    else if (update?.available) updateRow = `<div class="setting-row"><div><b>Keyhop ${esc(update.latest)} is available</b><p>You have ${esc(update.current)}. The download is checked against its SHA-256 before it installs.</p></div><button class="btn sm" data-action="install-update">Install Update</button></div>`;
    else if (update) updateRow = `<div class="setting-row"><div><b>Keyhop is up to date</b><p>Version ${esc(update.current)} is the latest release.</p></div><button class="btn sm secondary" data-action="check-update">Check Again</button></div>`;
    else updateRow = `<div class="setting-row"><div><b>Keyhop ${esc(state.version)}</b><p>Update checks run separately from limit and usage refreshes.</p></div><button class="btn sm secondary" data-action="check-update">Check for Updates</button></div>`;

    const tools = doctor ? `<div class="list">${doctor.tools.map((t) => `<div class="row">
        <div class="who">${mark(t.id)}<div><b>${esc(t.name)}</b><small>${t.signedInAs ? `Signed in as ${esc(t.signedInAs)}` : t.problem ? esc(t.problem) : t.installed ? "Signed out" : "Not found on this computer"}</small></div></div>
        <div class="mono subtle" style="margin:8px 0 0 30px;overflow-wrap:anywhere">${esc(t.loginLocation)}</div>
      </div>`).join("")}</div>` : (isStatic ? `<p class="empty">Not included in a saved page.</p>` : busy("Looking for tools on this computer", "empty"));

    const privacy = `<section class="card"><div class="card-head"><h2>Storage & Privacy</h2></div>
      <div class="list">
        <div class="row kv"><span>Data folder</span><span class="mono">${esc(doctor?.dataDirectory || state.dataDirectory)}</span></div>
        <div class="row kv"><span>Saved logins</span><span>${esc(doctor ? `${doctor.savedAccounts} in ${doctor.secretStore}` : state.status.secretStore)}</span></div>
        ${doctor?.prices ? `<div class="row kv"><span>Model prices</span><span>${fmt.count(doctor.prices.models)} models, ${doctor.prices.updated ? `from models.dev ${esc(ago(doctor.prices.updated))}` : "built into this release"}</span></div>` : ""}
        <div class="row kv"><span>Network</span><span>Provider usage and sign-in services, public status pages, models.dev for prices, GitHub for updates${state.cloud?.linked ? `, and Keyhop cloud for your daily totals${state.cloud.sharesLimits ? " and current limits" : ""}` : ""}. No analytics.</span></div>
        <div class="row kv"><span>This window</span><span>Served by Keyhop on 127.0.0.1 with a private session key.</span></div>
      </div></section>`;
    const panes = {
      general: `<div class="settings-intro"><h2>Window Appearance</h2><p>Choose how Keyhop sits alongside the rest of your Mac.</p></div>${isStatic ? "" : appearanceCard()}`,
      activity: `<div class="settings-intro"><h2>Activity</h2><p>Control what Keyhop reads locally and see where each tool is signed in.</p></div>${isStatic ? "" : workCard(state.work)}<section class="card"><div class="card-head"><h2>Tools on This Mac</h2></div>${tools}</section>`,
      cloud: `<div class="settings-intro"><h2>Keyhop Cloud</h2><p>Manage the optional leaderboard and the data shared with it.</p></div>${cloudCard(state.cloud)}`,
      app: `<div class="settings-intro"><h2>App & Privacy</h2><p>Version ${esc(state.version)} on ${esc(state.platform)}. Updates and limit refreshes stay independent.</p></div><section class="card"><div class="card-head"><h2>Updates</h2></div><div class="card-body">${updateRow}</div></section>${privacy}`,
    };
    if (ui.settingsPane === "cloud" && (isStatic || !state.cloud?.available)) ui.settingsPane = "general";
    const choices = [["general", "settings", "Appearance"], ["activity", "usage", "Activity"]];
    if (!isStatic && state.cloud?.available) choices.push(["cloud", "leaderboard", "Cloud"]);
    choices.push(["app", "update", "App & Privacy"]);
    const nav = choices.map(([value, glyph, label]) => `<button type="button" data-action="settings-pane" data-value="${value}" aria-current="${value === ui.settingsPane ? "page" : "false"}">${icon(glyph)}<span>${label}</span></button>`).join("");
    return { body: `<div class="settings-shell"><nav class="card settings-nav" aria-label="Settings categories">${nav}</nav><div class="settings-pane">${panes[ui.settingsPane]}</div></div>` };
  }

  // MARK: Overlays

  let toastTimer;
  function toast(message, error = false) {
    const node = $("#toast");
    node.textContent = message;
    node.classList.toggle("error", error);
    node.classList.remove("away");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => node.classList.add("away"), error ? 8000 : 5000);
  }

  function placeTip(tip, event) {
    tip.hidden = false;
    const box = tip.getBoundingClientRect();
    let x = event.clientX + 14, y = event.clientY + 14;
    if (x + box.width > innerWidth - 10) x = event.clientX - box.width - 14;
    if (y + box.height > innerHeight - 10) y = event.clientY - box.height - 14;
    tip.style.left = Math.max(10, x) + "px";
    tip.style.top = Math.max(10, y) + "px";
  }

  document.addEventListener("pointermove", (event) => {
    const tip = $("#tip");
    const card = event.target.closest && event.target.closest("[data-tip]");
    if (card) { tip.innerHTML = card.dataset.tip; placeTip(tip, event); return; }
    const hit = event.target.closest && event.target.closest(".hit");
    // The hovered day stays lit and the rest step back.
    for (const svg of document.querySelectorAll(".chart svg[data-hover]")) {
      if (!hit || hit.ownerSVGElement !== svg || svg.dataset.hover !== hit.dataset.bucket) {
        delete svg.dataset.hover;
        svg.querySelector(".col.on")?.classList.remove("on");
      }
    }
    if (hit && !hit.ownerSVGElement.dataset.hover) {
      hit.ownerSVGElement.dataset.hover = hit.dataset.bucket;
      hit.ownerSVGElement.querySelector(`.col[data-col="${hit.dataset.bucket}"]`)?.classList.add("on");
    }
    if (!hit) { tip.hidden = true; return; }
    const usage = data.usage[hit.dataset.key] || data.usage[hit.dataset.key.split(":")[0] + ":all"];
    const grouped = usage ? chartGroup(usage, hit.dataset.group) : null;
    const bucket = grouped?.buckets[+hit.dataset.bucket];
    if (!bucket) { tip.hidden = true; return; }
    const metric = hit.dataset.metric;
    const pick = (v) => (metric === "tokens" ? v.tokens : v.cost);
    const show = (v) => (metric === "tokens" ? fmt.tokens(v) : fmt.usd(v));
    const rows = grouped.series.map((s) => ({ s, v: bucket.values[s.id] })).filter((e) => e.v && pick(e.v) > 0).reverse();
    const total = rows.reduce((sum, e) => sum + pick(e.v), 0);
    const when = usage.bucket === "hour" ? fmt.day(bucket.start, { weekday: "short", hour: "2-digit", minute: "2-digit" })
      : usage.bucket === "week" ? `Week of ${fmt.day(bucket.start, { month: "short", day: "numeric", year: "numeric" })}`
      : usage.bucket === "month" ? fmt.day(bucket.start, { month: "long", year: "numeric" })
      : fmt.day(bucket.start, { weekday: "short", month: "short", day: "numeric" });
    tip.innerHTML = `<b>${esc(when)} · <span class="mono">${esc(show(total))}</span></b>${rows.length ? rows.map((e) => `<div><span class="swatch" style="background:${e.s.color}"></span><span>${esc(e.s.name)}</span><span class="mono">${esc(show(pick(e.v)))}</span></div>`).join("") : `<div><span></span><span>No usage</span><span></span></div>`}`;
    placeTip(tip, event);
  });

  // MARK: Actions

  const editing = () => ui.editing || ui.confirming || ui.rangeOpen || ui.menu || palette || ["INPUT", "SELECT"].includes(document.activeElement?.tagName);

  // `morph` cross-fades the page into its new state once the call is done, for changes that move
  // things around, like switching which login is in use.
  async function act(button, call, label, morph = false) {
    const key = button ? pendingKey(button) : null;
    if (key) { ui.pending.set(key, label || ""); applyPending(); }
    try {
      const running = call();
      watchActivity();
      const result = await running;
      if (result && result.message) toast(result.note ? `${result.message} ${result.note}` : result.message);
      await loadState();
      await loadSection();
    } catch (error) {
      toast(error.message, true);
      if (data.state) { data.state.refreshing = false; data.state.activity = null; }
    } finally {
      if (key) ui.pending.delete(key);
      if (morph) transition(render); else render();
      watchActivity();
    }
  }

  async function go(section) {
    ui.section = section;
    history.replaceState(null, "", "#" + section);
    transition(() => { render(); $("#main").scrollTop = 0; });
    await loadSection();
    render();
  }

  document.addEventListener("input", (event) => {
    if (!palette || !event.target.closest("#palette")) return;
    palette.query = event.target.value;
    palette.index = 0;
    drawPalette();
  });

  document.addEventListener("click", async (event) => {
    if (event.target.closest("[data-palette-close]")) { closePalette(); return; }
    const option = event.target.closest("[data-palette]");
    if (option) { runPalette(+option.dataset.palette); return; }
    const link = event.target.closest("#nav a");
    if (link) { event.preventDefault(); if (link.dataset.section !== ui.section) go(link.dataset.section); return; }
    // A click anywhere outside the open range menu closes it.
    if (ui.rangeOpen && !event.target.closest(".range-pick")) { ui.rangeOpen = false; render(); }
    if (ui.menu && !event.target.closest(".menu-anchor")) { ui.menu = null; render(); }
    const el = event.target.closest("[data-action]");
    if (!el || el.disabled || el.tagName === "SELECT") return;
    const id = el.dataset.id;
    switch (el.dataset.action) {
      case "palette": openPalette(); break;
      case "goto": go(el.dataset.section); break;
      case "skip-content": $("#main")?.focus(); break;
      case "settings-pane": ui.settingsPane = el.dataset.value; render(); break;
      case "refresh":
        if (data.state?.refreshing) break;
        act(null, () => { data.state.refreshing = true; renderActivity(); return api("/api/refresh", {}); });
        break;
      case "switch": act(el, () => api("/api/switch", { id }), "Switching", true); break;
      case "account-menu": ui.menu = ui.menu === id ? null : id; ui.confirming = null; render(); break;
      case "add": act(el, () => api("/api/add", { tool: el.dataset.tool }), "Signing out"); break;
      case "add-stop": act(el, () => api("/api/add/stop", { tool: el.dataset.tool }), "Stopping"); break;
      case "edit": ui.editing = id; ui.confirming = null; ui.menu = null; render(); $("form[data-form=rename] input")?.focus(); break;
      case "cancel-edit": ui.editing = null; render(); break;
      case "confirm-remove": ui.confirming = id; ui.editing = null; ui.menu = null; render(); break;
      case "cancel-remove": ui.confirming = null; render(); break;
      case "remove": act(el, () => api("/api/remove", { id }).finally(() => { ui.confirming = null; }), "Removing"); break;
      case "range-menu":
        ui.rangeOpen = !ui.rangeOpen;
        render();
        if (ui.rangeOpen) $(".range-list [aria-checked=true]")?.focus();
        break;
      case "all-periods": ui.allPeriods = true; render(); break;
      case "series": {
        const hidden = ui.hidden[ui.group] || (ui.hidden[ui.group] = []);
        const at = hidden.indexOf(el.dataset.value);
        const total = chartGroup(data.usage[`${ui.range}:${ui.tool}`] || {}, ui.group).series?.length || 0;
        if (at >= 0) hidden.splice(at, 1);
        else if (hidden.length < total - 1) hidden.push(el.dataset.value); // At least one part stays.
        transition(render);
        break;
      }
      case "day": showUsage({ range: `${el.dataset.value}..${el.dataset.value}` }); break;
      case "breakdown": ui.breakdown = el.dataset.value; ui.allPeriods = false; render(); break;
      case "range": case "metric": case "group":
        ui[el.dataset.action] = el.dataset.value;
        if (el.dataset.action === "range") ui.rangeOpen = false;
        if (el.dataset.action === "group") transition(render); else render();
        if (el.dataset.action === "range") { await loadSection(); render(); }
        break;
      case "filter-tool":
        if (!el.dataset.value || el.dataset.value === ui.tool) break;
        ui.tool = el.dataset.value;
        render();
        await loadSection();
        render();
        break;
      case "export-csv": {
        const usage = data.usage[`${ui.range}:${ui.tool}`];
        if (usage) exportCSV(usage);
        break;
      }
      case "work-on": act(el, () => api("/api/work", { enabled: true }), "Turning on"); break;
      case "work-off": act(el, () => api("/api/work", { enabled: false }), "Stopping"); break;
      case "work-subjects-on": act(el, () => api("/api/work", { shareSubjects: true }), "Sharing"); break;
      case "work-subjects-off": act(el, () => api("/api/work", { shareSubjects: false }), "Keeping here"); break;
      case "work-remove": act(el, () => api("/api/work", { remove: el.dataset.path }), "Removing"); break;
      case "edit-budget": ui.budgetEdit = el.dataset.scope; render(); $("form[data-form=budget] input[name=amount]")?.focus(); break;
      case "cancel-budget": ui.budgetEdit = null; render(); break;
      case "delete-budget": act(el, () => api("/api/budget", { scope: el.dataset.scope === "all" ? "all" : el.dataset.scope.replace("account:", ""), amount: null })); break;
      case "check-update": await loadUpdate(true); break;
      case "install-update": act(el, () => api("/api/update", {}), "Installing"); break;
      case "cloud-link": act(el, () => api("/api/cloud/link", {}), "Opening GitHub"); break;
      case "cloud-sync": act(el, () => api("/api/cloud/sync", {}), "Syncing"); break;
      case "cloud-unlink": data.board = null; act(el, () => api("/api/cloud/unlink", {}), "Unlinking"); break;
      case "cloud-limits-on": act(el, () => api("/api/cloud/limits", { on: true }), "Turning on"); break;
      case "cloud-limits-off": act(el, () => api("/api/cloud/limits", { on: false }), "Stopping"); break;
      case "appearance": setAppearance({ [el.dataset.key]: el.dataset.value }); break;
      case "appearance-clear": setAppearance({ image: "" }); break;
      case "board-period": case "board-metric":
        ui[el.dataset.action === "board-period" ? "boardPeriod" : "boardMetric"] = el.dataset.value;
        data.board = null;
        render();
        await loadSection();
        render();
        break;
    }
  });

  // Window opacity and blur follow their sliders while they move, and save when let go.
  document.addEventListener("input", (event) => {
    const slider = event.target.closest('[data-appearance="glass"], [data-appearance="blur"]');
    if (!slider) return;
    const look = data.state.appearance;
    if (slider.dataset.appearance === "glass") applyGlass(Number(slider.value) / 100, look.blur);
    else applyGlass(look.glass, Number(slider.value));
  });

  document.addEventListener("change", async (event) => {
    const look = event.target.closest("[data-appearance]");
    if (look) {
      if (look.dataset.appearance === "opacity") { setAppearance({ opacity: Number(look.value) / 100 }); return; }
      if (look.dataset.appearance === "glass") { setAppearance({ glass: Number(look.value) / 100 }); return; }
      if (look.dataset.appearance === "blur") { setAppearance({ blur: Number(look.value) }); return; }
      const file = look.files && look.files[0];
      look.value = "";
      if (!file) return;
      try { setAppearance({ image: await shrinkPicture(file) }); } catch (error) { toast(error.message, true); }
      return;
    }
    const team = event.target.closest("select[data-action=board-team]");
    if (team) {
      ui.boardTeam = team.value;
      team.blur();
      data.board = null;
      render();
      await loadSection();
      render();
      return;
    }
    const select = event.target.closest("select[data-action=tool]");
    if (!select) return;
    ui.tool = select.value;
    select.blur();
    render();
    await loadSection();
    render();
  });

  document.addEventListener("submit", (event) => {
    const form = event.target;
    event.preventDefault();
    const button = form.querySelector("button:not([type=button])");
    if (form.dataset.form === "rename") {
      const id = form.dataset.id, name = form.elements.name.value;
      ui.editing = null;
      act(button, () => api("/api/rename", { id, name }));
    }
    if (form.dataset.form === "budget") {
      const amount = parseFloat(String(form.elements.amount.value).replace(/[$,\s]/g, ""));
      if (!(amount > 0)) { toast("Type an amount in dollars, like 200.", true); return; }
      const scope = form.elements.scope.value, period = form.elements.period.value;
      ui.budgetEdit = null;
      act(button, () => api("/api/budget", { scope, amount, period }));
    }
    if (form.dataset.form === "range") {
      const from = form.elements.from.value, to = form.elements.to.value;
      if (!from || !to) { toast("Pick both days.", true); return; }
      ui.range = from <= to ? `${from}..${to}` : `${to}..${from}`;
      ui.rangeOpen = false;
      render();
      loadSection().then(render);
    }
    if (form.dataset.form === "work-folder") {
      const folder = String(form.elements.folder.value || "").trim();
      if (!folder) { toast("Type a folder to scan, like ~/Projects.", true); return; }
      act(button, () => api("/api/work", { add: folder }));
    }
  });

  document.addEventListener("keydown", (event) => {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
      event.preventDefault();
      if (palette) closePalette(); else openPalette();
      return;
    }
    if (palette) {
      const count = paletteMatches().length;
      if (event.key === "Escape") { event.preventDefault(); closePalette(); return; }
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        palette.index = (palette.index + (event.key === "ArrowDown" ? 1 : -1) + count) % Math.max(1, count);
        drawPalette();
        return;
      }
      if (event.key === "Enter") { event.preventDefault(); runPalette(palette.index); return; }
      return;
    }
    // Number keys jump between sections, unless someone is typing.
    const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement?.tagName || "");
    if (!typing && !event.metaKey && !event.ctrlKey && !event.altKey && /^[1-9]$/.test(event.key)) {
      const section = shownSections()[+event.key - 1];
      if (section && section !== ui.section) { event.preventDefault(); go(section); return; }
    }
    if (event.key === "Escape" && ui.menu) { ui.menu = null; render(); return; }
    if (event.key === "Escape" && ui.rangeOpen) { ui.rangeOpen = false; render(); $(".range-button")?.focus(); return; }
    if (event.key === "Escape" && (ui.editing || ui.confirming || ui.budgetEdit)) { ui.editing = ui.confirming = ui.budgetEdit = null; render(); }
  });
  const followVisibility = () => document.documentElement.toggleAttribute("data-away", document.hidden);
  async function resumeRefresh() {
    followVisibility();
    if (document.hidden || isStatic || !data.state) return;
    try {
      await loadState();
      if (ui.section === "overview" || ui.section === "usage") await loadSection();
      if (!editing()) render(); else renderSidebar();
    } catch (error) {
      ui.offline = error.message;
      if (!editing()) render();
    }
  }
  document.addEventListener("visibilitychange", resumeRefresh);
  followVisibility();
  addEventListener("hashchange", () => {
    const section = location.hash.slice(1);
    if (SECTIONS.includes(section) && section !== ui.section) go(section);
  });
  let resizeTimer;
  addEventListener("resize", () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(() => { if (!editing()) render(); }, 150); });

  // MARK: Start

  async function start() {
    if (isStatic) { render(); applyBackdrop(); return; }
    if (!token) {
      $("#main").innerHTML = `<div class="page"><div class="card"><p class="empty">This window isn't connected to Keyhop. Open it from the tray, or run keyhop dashboard.</p></div></div>`;
      return;
    }
    try {
      await loadState();
      render();
      watchActivity();
      await loadSection();
      render();
    } catch (error) {
      $("#main").innerHTML = `<div class="page"><div class="notice">${icon("alert")}<div><p>${esc(error.message)}</p></div></div></div>`;
      return;
    }
    setInterval(async () => {
      if (document.hidden) return;
      try {
        await loadState();
        if (ui.section === "overview" || ui.section === "usage") await loadSection();
        if (!editing()) render(); else renderSidebar();
        watchActivity();
      } catch (error) {
        ui.offline = error.message;
        if (!editing()) render();
      }
    }, 20000);
  }
  if (document.documentElement.classList.contains("mac-window")) {
    addEventListener("mousedown", (event) => {
      if (event.button !== 0 || !event.target.closest(".brand, .topbar")) return;
      if (event.target.closest("button, a, input, select, textarea, label")) return;
      window.webkit?.messageHandlers?.keyhopWindow?.postMessage(event.detail === 2 ? "zoom" : "drag");
    });
  }
  start();
})();
</script>
</body>
</html>
"""##
}
