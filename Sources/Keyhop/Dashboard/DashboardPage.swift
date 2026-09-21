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
  --subtle: hsl(0 0% 46%);
  --faint: hsl(0 0% 100% / .08);
  --primary: hsl(0 0% 95%);
  --on-primary: hsl(0 0% 9%);
  --focus: hsl(211 92% 62%);
  --good: #5CC98A;
  --warn: #E3A64F;
  --bad: #EE7A69;
  --sans: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI Variable Text", "Segoe UI", Roboto, Cantarell, "Noto Sans", sans-serif;
  --mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
  color-scheme: dark;
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
[hidden] { display: none !important; }
::-webkit-scrollbar { width: 8px; height: 8px; }
::-webkit-scrollbar-thumb { background: hsl(0 0% 100% / .12); border-radius: 99px; border: 2px solid transparent; background-clip: padding-box; }
::-webkit-scrollbar-track { background: transparent; }
.mono { font-family: var(--mono); font-size: 12px; }
.muted { color: var(--muted); }
.subtle { color: var(--subtle); }
.num { font-variant-numeric: tabular-nums; white-space: nowrap; }
.up { color: var(--good); }
.down { color: var(--bad); }

/* Shell */
.shell { display: grid; grid-template-columns: 236px minmax(0, 1fr); height: 100vh; }
.sidebar { display: flex; flex-direction: column; background: var(--sidebar); border-right: 1px solid var(--border); min-height: 0; }
.brand { display: flex; align-items: center; gap: 10px; height: 52px; padding: 0 18px; border-bottom: 1px solid var(--border); }
.brand svg { width: 17px; height: 17px; flex: none; }
.brand b { font-weight: 650; font-size: 14px; letter-spacing: .01em; }
.brand .badge { margin-left: auto; }
.nav { display: grid; gap: 2px; padding: 12px 10px; }
.nav a {
  display: flex; align-items: center; gap: 10px; height: 34px; padding: 0 10px; border-radius: 8px;
  color: var(--muted); text-decoration: none; font-weight: 520; transition: background .12s ease, color .12s ease;
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
.topbar { position: relative; z-index: 1; display: flex; align-items: center; justify-content: space-between; gap: 16px; height: 52px; padding: 0 24px; border-bottom: 1px solid var(--border); flex: none; }
/* Nothing scrolls under the top bar, so over the Field it simply gets out of the way. */
.has-backdrop .topbar { background: transparent; border-bottom-color: transparent; }
.topbar h1 { margin: 0; font-size: 15px; font-weight: 620; }
/* The whole window's progress, along the bottom edge of the top bar. */
.topbar .meter { position: absolute; left: 24px; right: 24px; bottom: -2px; height: 3px; background: transparent; opacity: 0; transition: opacity .25s ease; }
.topbar .meter.on { opacity: 1; }
.toolbar { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; justify-content: flex-end; }
.main { position: relative; z-index: 1; flex: 1; overflow: auto; padding: 22px 24px 40px; }
.page { max-width: 1320px; margin: 0 auto; display: grid; gap: 16px; }
.lede { margin: 0 0 4px; color: var(--muted); }

/* Components */
.card { background: var(--panel); border: 1px solid var(--border); border-radius: 10px; min-width: 0; }
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
.hero { position: relative; container-type: inline-size; padding: 52px 4px 40px; display: grid; gap: 10px; }
/* While a refresh runs, a pixel runner hops along the bottom of the hero. */
.hero-run { position: absolute; left: 0; right: 0; bottom: 12px; height: 24px; opacity: 0; transition: opacity .3s ease; pointer-events: none; }
.hero-run.on { opacity: 1; }
.hero-figure { display: flex; align-items: baseline; gap: 14px; flex-wrap: wrap; margin: 0; font-weight: 400; }
.hero-figure .num { font-size: 60px; font-weight: 640; letter-spacing: -.005em; line-height: 1; font-variant-numeric: tabular-nums; }
.hero-figure .unit { font-size: 19px; color: var(--muted); font-weight: 520; }
.hero-line { margin: 0; color: var(--muted); font-size: 14px; }
/* A soft shadow right behind the words keeps them clear of bright dots, without a band behind them. */
.has-backdrop .hero-figure, .has-backdrop .hero-line { text-shadow: 0 1px 20px hsl(0 0% 9% / .95), 0 0 2px hsl(0 0% 9% / .8); }
.card-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 14px 16px; border-bottom: 1px solid var(--border); min-height: 50px; }
.card-head h2 { margin: 0; font-size: 13.5px; font-weight: 600; display: flex; align-items: center; gap: 8px; }
.card-head .hint { color: var(--subtle); font-size: 12.5px; }
.card-body { padding: 16px; }
.split { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
.split.wide-left { grid-template-columns: minmax(0, 1.55fr) minmax(0, 1fr); }
.stats { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 16px; }
.stat { padding: 14px 16px 16px; }
.stat .label { color: var(--muted); font-size: 12.5px; display: flex; justify-content: space-between; gap: 8px; }
.stat .value { margin-top: 6px; font-size: 24px; font-weight: 620; letter-spacing: -.01em; font-variant-numeric: tabular-nums; line-height: 1.2; }
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
a.btn { text-decoration: none; }
.main p a:not(.btn) { color: var(--text); text-underline-offset: 3px; }
:focus-visible { outline: 2px solid var(--focus); outline-offset: 2px; }

.badge {
  display: inline-flex; align-items: center; gap: 5px; height: 20px; padding: 0 7px; border-radius: 6px;
  background: hsl(0 0% 100% / .07); color: var(--muted); font-size: 10.5px; font-weight: 650; letter-spacing: .03em; text-transform: uppercase; white-space: nowrap;
}
.badge.live::before { content: ""; width: 6px; height: 6px; border-radius: 50%; background: var(--good); }
.badge.sample { color: var(--warn); background: hsl(36 72% 60% / .1); }

.tabs { display: inline-flex; padding: 3px; gap: 2px; border-radius: 8px; background: var(--raised); border: 1px solid var(--border); }
.tabs button { height: 26px; padding: 0 10px; border: 0; border-radius: 5px; background: transparent; color: var(--muted); cursor: pointer; font-size: 12.5px; font-weight: 540; }
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
.group-head h2 { margin: 0; font-size: 14px; font-weight: 620; }
.group-head .count { color: var(--subtle); font-family: var(--mono); font-size: 12px; }
.group-head .btn { margin-left: auto; }
/* Fixed outer columns, so every row's limits and figures line up whatever its buttons are. */
.account-row { display: grid; grid-template-columns: minmax(200px, 1.1fr) minmax(260px, 1.5fr) 130px 250px; gap: 20px; align-items: center; }
.account-row .row-actions { flex-wrap: nowrap; }
.account-name { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.account-name b { font-weight: 600; font-size: 14px; }
.account-email { color: var(--subtle); margin-top: 2px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
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
.legend li { display: flex; align-items: center; gap: 6px; }
.swatch { width: 8px; height: 8px; border-radius: 2px; flex: none; }
.chart { overflow-x: auto; }
.chart svg { display: block; }
.chart .grid { stroke: hsl(0 0% 100% / .06); }
.chart .base { stroke: hsl(0 0% 100% / .16); }
.chart .axis { fill: var(--subtle); font: 11px var(--mono); }
.chart .hit { fill: transparent; }
.chart .hit:hover { fill: hsl(0 0% 100% / .035); }
.heat rect.l0 { fill: hsl(0 0% 100% / .05); }
.heat rect.l1 { fill: hsl(0 0% 100% / .18); }
.heat rect.l2 { fill: hsl(0 0% 100% / .36); }
.heat rect.l3 { fill: hsl(0 0% 100% / .6); }
.heat rect.l4 { fill: hsl(0 0% 100% / .9); }
.heat text { fill: var(--subtle); font: 10.5px var(--mono); }
.scale { display: inline-flex; align-items: center; gap: 3px; font-size: 11.5px; color: var(--subtle); }
.scale i { width: 10px; height: 10px; border-radius: 2px; }
.facts { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); border-top: 1px solid var(--border); }
.facts div { padding: 12px 16px; }
.facts div + div { border-left: 1px solid var(--border); }
.facts b { display: block; font-size: 18px; font-weight: 620; font-variant-numeric: tabular-nums; }
.facts span { color: var(--subtle); font-size: 12px; }
.mix-bar { display: flex; gap: 2px; height: 8px; border-radius: 99px; overflow: hidden; margin-bottom: 16px; }
.mix-bar span { min-width: 2px; }
.m1 { background: hsl(0 0% 100% / .9); } .m2 { background: hsl(0 0% 100% / .55); } .m3 { background: hsl(0 0% 100% / .3); } .m4 { background: hsl(0 0% 100% / .18); }
.m5 { background: hsl(0 0% 100% / .1); }
.table { width: 100%; border-collapse: collapse; }
.table th { text-align: left; font-weight: 500; color: var(--subtle); font-size: 12px; padding: 10px 16px; border-bottom: 1px solid var(--border); }
.table td { padding: 10px 16px; border-bottom: 1px solid var(--border); vertical-align: middle; }
.table tr:last-child td { border-bottom: 0; }
.table tbody tr:hover td { background: hsl(0 0% 100% / .02); }
.table tbody tr.clickable { cursor: pointer; }
.table .right { text-align: right; }
.table .bar-cell { width: 34%; }
.cell-name { display: flex; align-items: center; gap: 8px; min-width: 0; }
.cell-name span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.model-group + .model-group { border-top: 1px solid var(--border); }
.model-group .group-head { padding: 12px 16px 4px; }
.model-group .table { margin-top: 0; }

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
.podium-value { font-size: 24px; font-weight: 620; font-variant-numeric: tabular-nums; line-height: 1.15; }
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
  .kv { grid-template-columns: 1fr; gap: 2px; }
}
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { animation: none !important; transition: none !important; }
  /* A bar that can't travel would read as stuck part-way, so the words carry it alone. */
  .meter.unknown > span { display: none; }
}
</style>
</head>
<body>
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
      <button class="foot-row" data-action="goto" data-section="settings"><svg class="icon"><use href="#i-update"/></svg><span><b id="update-title">Check for updates</b><small id="version"></small></span></button>
    </div>
  </aside>
  <div class="content">
    <div class="backdrop" id="backdrop" aria-hidden="true"></div>
    <header class="topbar"><h1 id="title">Overview</h1><div class="toolbar" id="toolbar"></div><div class="meter" id="top-meter" role="progressbar" aria-label="Keyhop is reading" aria-hidden="true"><span></span></div></header>
    <main class="main" id="main"><div class="page"><p class="lede busy" role="status"><span class="pulse" aria-hidden="true"><i></i><i></i><i></i></span>Reading your accounts</p></div></main>
  </div>
</div>
<div class="tip" id="tip" hidden></div>
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
    range: "week", metric: "tokens", tool: "all", group: "account",
    boardPeriod: "week", boardMetric: "tokens", boardTeam: "",
    editing: null, confirming: null, budgetEdit: null, offline: null,
    pending: new Map(), loadingUsage: 0,
  };
  history.replaceState(null, "", "#" + ui.section);
  const data = { state: boot?.state || null, usage: {}, doctor: null, update: null, updateError: null };
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
      if (s < 60) return "just now";
      if (s < 3600) return Math.floor(s / 60) + " min ago";
      if (s < 86400) return Math.floor(s / 3600) + " h ago";
      return Math.floor(s / 86400) + " d ago";
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
    const init = { method: body === undefined ? "GET" : "POST", headers: { Authorization: "Bearer " + token } };
    if (body !== undefined) { init.headers["Content-Type"] = "application/json"; init.body = JSON.stringify(body); }
    let response;
    try { response = await fetch(path, init); } catch { throw new Error("Keyhop isn't running anymore. Open it again from the tray or with keyhop dashboard."); }
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
        data.doctor = await api("/api/doctor");
        try { data.update = await api("/api/update"); data.updateError = null; } catch (error) { data.updateError = error.message; }
      }
    } catch (error) {
      ui.offline = error.message;
    }
    applyBackdrop();
  }

  // MARK: Shell

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
    applyPending();
    renderActivity();
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
    for (const meter of [$("#foot-meter"), $("#top-meter")]) {
      if (!meter) continue;
      const known = step?.fraction != null;
      meter.classList.toggle("unknown", busyNow && !known);
      meter.firstElementChild.style.width = known ? `${(step.fraction * 100).toFixed(1)}%` : "";
      if (meter.id === "foot-meter") meter.hidden = !busyNow; else meter.classList.toggle("on", busyNow);
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
    $("#update-title").textContent = data.update?.available ? `Update to ${data.update.latest}` : "Check for updates";
    $("#version").textContent = state ? `v${state.version} · ${state.platform}` : "";
  }

  function tabs(name, options, current, disabled = false) {
    return `<div class="tabs" role="group">${options.map(([value, label]) =>
      `<button type="button" data-action="${name}" data-value="${value}" aria-pressed="${value === current}" ${disabled ? "disabled" : ""}>${esc(label)}</button>`).join("")}</div>`;
  }

  function progress(percent, pace, tone) {
    const width = Math.min(100, Math.max(0, percent));
    // "plain" is for rankings, where a full bar means the largest, not a limit running out.
    const state = tone === "plain" ? "" : tone || (width >= 90 ? "bad" : pace != null && width > pace * 100 + 6 ? "warn" : "");
    return `<div class="progress ${state}"><span style="width:${width.toFixed(1)}%"></span>${pace != null ? `<i style="left:${Math.min(100, pace * 100).toFixed(1)}%" title="Time passed"></i>` : ""}</div>`;
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
        ${progress(limit.usedPercent, limit.pace)}
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
      <div class="notice">${icon("alert")}<div><b>${esc(alert.title)}</b><p>${esc(alert.body)}</p></div>
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
      return `<div class="notice">${icon("alert")}<div><b>${esc(toolName(s.tool))}: ${levelWords[s.level]}</b><p>${detail}${advice}</p></div>
        <a class="btn sm secondary" href="${esc(incident?.link || s.page)}" target="_blank" rel="noopener">Status page</a></div>`;
    }).join("");
    const serviceHint = services.length && !troubled.length && services.some((s) => s.level === "operational") ? " · Services operational" : "";

    const streak = (week || today)?.streak;
    const hero = `<section class="hero">
      <h2 class="hero-figure"><span class="num">${fmt.tokens(status.today.tokens)}</span><span class="unit">tokens today</span></h2>
      <p class="hero-line">${today ? `${fmt.change(today.total.tokens, today.previous.tokens)} on yesterday · ` : ""}${fmt.count(status.today.requests)} requests${today && today.total.requests ? ` · ${esc(busiestHour(today))}` : ""}</p>
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

    const hourCard = `<section class="card">
      <div class="card-head"><h2>Today by hour</h2><span class="hint">${today ? esc(busiestHour(today)) : ""}</span></div>
      <div class="card-body">${today ? dotHours(today) : loading("Reading usage")}</div>
    </section>`;
    const weekCard = `<section class="card">
      <div class="card-head"><h2>Last 7 days</h2><button class="btn sm ghost" data-action="goto" data-section="usage">Open usage</button></div>
      <div class="card-body">${week ? (week.total.requests ? `<div class="chart">${stackedChart(week, "tokens", 180, "half", "account")}</div>` : `<p class="empty-inline">No usage in the last 7 days.</p>`) : loading("Reading usage")}</div>
    </section>`;
    const budgetsCard = `<section class="card">
      <div class="card-head"><h2>Budgets</h2><button class="btn sm ghost" data-action="goto" data-section="budgets">${status.budgets.length ? "Manage" : "Set a budget"}</button></div>
      ${status.budgets.length ? `<div class="list">${status.budgets.slice(0, 3).map(budgetRow).join("")}</div>` : `<p class="empty">No budgets yet. A budget warns you at 80% and 100%.</p>`}
    </section>`;
    const modelsCard = `<section class="card">
      <div class="card-head"><h2>Top models this week</h2></div>
      ${week && week.models.length ? modelTable(week.models.slice(0, 6), "tokens", false) : `<p class="empty">No models used this week.</p>`}
    </section>`;

    return { body: `${alerts}${outages}${stats}${inUse}<div class="split">${hourCard}${weekCard}</div><div class="split">${budgetsCard}${modelsCard}</div>` };
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
      ${progress(share * 100, elapsed, share >= 1 ? "bad" : share >= .8 ? "warn" : "")}
      <div class="subtle" style="font-size:12px">Per ${esc(budget.period)} · ${Math.round(share * 100)}% used · on pace for ${fmt.usd(budget.spent / elapsed)}</div>
    </div>`;
  }

  // MARK: Accounts

  function accountsPage(tools) {
    const body = tools.map((tool) => {
      const adding = data.state.adding.includes(tool.id);
      const rows = tool.accounts.map((account) => accountRow(account, tool.limitsNote)).join("");
      const waiting = adding ? `<div class="row waiting-row"><div class="waiting"><span class="pulse"><i></i><i></i><i></i></span><span>Waiting for a new ${esc(tool.name)} login ${waited(tool.id)}<br><small>${esc(tool.signInHint)} Keyhop saves it the moment it appears.</small></span></div>
        ${isStatic ? "" : `<button class="btn sm ghost" data-action="add-stop" data-tool="${esc(tool.id)}">Stop waiting</button>`}</div>` : "";
      const empty = !tool.accounts.length && !adding ? `<p class="empty">${esc(tool.signInHint)}</p>` : "";
      return `<section class="group">
        <div class="group-head">${mark(tool.id)}<h2>${esc(tool.name)}</h2><span class="count">${tool.accounts.length}</span>
          ${isStatic ? "" : `<button class="btn sm secondary" data-action="add" data-tool="${esc(tool.id)}" ${adding ? "disabled" : ""}>${icon("plus")}Add account</button>`}</div>
        <div class="card list">${waiting}${rows}${empty}</div>
      </section>`;
    }).join("");
    return { body: `<p class="lede">Every login Keyhop keeps. Switching saves the login in use first, so none is ever lost.</p>${body}` };
  }

  function accountRow(account, limitsNote) {
    const editing = ui.editing === account.id;
    const confirming = ui.confirming === account.id;
    const name = editing
      ? `<form class="rename" data-form="rename" data-id="${esc(account.id)}"><input class="field" name="name" value="${esc(account.label || "")}" placeholder="${esc(account.email)}" maxlength="60" aria-label="Name"><button class="btn sm">Save</button><button type="button" class="btn sm ghost" data-action="cancel-edit">Cancel</button></form>`
      : `<div class="account-name"><b>${esc(account.name)}</b>${account.plan ? `<span class="badge">${esc(account.plan)}</span>` : ""}${account.active ? `<span class="badge live">In use</span>` : ""}</div>
         <div class="account-email mono">${esc(account.label ? account.email : "")}</div>`;
    let actions = "";
    if (!isStatic && !editing) {
      actions = confirming
        ? `<span class="subtle" style="font-size:12.5px">Delete saved login?</span><button class="btn sm secondary danger" data-action="remove" data-id="${esc(account.id)}">Remove</button><button class="btn sm ghost" data-action="cancel-remove">Keep</button>`
        : `${account.active ? "" : `<button class="btn sm secondary" data-action="switch" data-id="${esc(account.id)}">Switch</button>`}<button class="btn sm ghost" data-action="edit" data-id="${esc(account.id)}">Rename</button>${account.active ? "" : `<button class="btn sm ghost danger" data-action="confirm-remove" data-id="${esc(account.id)}">Remove</button>`}`;
    }
    const today = account.today ? `${fmt.tokens(account.today.tokens)} tokens<br>${fmt.usd(account.today.cost)} today` : `<span class="subtle">No usage today</span>`;
    return `<div class="row account-row">
      <div>${name}</div>
      <div>${limits(account, 2, limitsNote)}</div>
      <div class="today">${today}</div>
      <div class="row-actions">${actions}</div>
    </div>`;
  }

  // MARK: Usage

  function usagePage(tools) {
    const toolbar = tabs("range", [["today", "Today"], ["week", "7 days"], ["month", "Month"], ["30d", "30 days"]], ui.range)
      + tabs("metric", [["tokens", "Tokens"], ["cost", "API value"]], ui.metric)
      + tabs("group", [["account", "By account"], ["tool", "By tool"], ["model", "By model"]], ui.group)
      + `<select class="field" data-action="tool" aria-label="Tool" ${isStatic ? "disabled" : ""}>${[["all", "All tools"], ...tools.map((t) => [t.id, t.name])].map(([v, l]) => `<option value="${v}" ${v === ui.tool ? "selected" : ""}>${esc(l)}</option>`).join("")}</select>`
      + (isStatic ? "" : `<button class="btn sm ghost" data-action="export-csv">Download CSV</button>`);
    const usage = data.usage[`${ui.range}:${ui.tool}`] || (isStatic ? data.usage[`${ui.range}:all`] : null);
    if (!usage) return { toolbar, body: `<div class="card">${loading("Reading usage", "empty")}</div>` };

    const t = usage.total, p = usage.previous;
    const inputSide = t.input + t.cacheRead + t.cacheWrite + (t.cacheWrite1h || 0);
    const stats = `<div class="stats">
      <div class="card stat"><div class="label">Tokens ${fmt.change(t.tokens, p.tokens)}</div><div class="value">${fmt.tokens(t.tokens)}</div><div class="foot">vs ${fmt.tokens(p.tokens)} the period before</div></div>
      <div class="card stat"><div class="label">API value ${fmt.change(t.cost, p.cost)}</div><div class="value">${fmt.usd(t.cost)}</div><div class="foot">${t.billed > 0 ? `${fmt.usd(t.billed)} billed on demand` : "At standard API prices"}</div></div>
      <div class="card stat"><div class="label">Requests</div><div class="value">${fmt.count(t.requests)}</div><div class="foot">${t.requests ? `${fmt.tokens(t.tokens / t.requests)} tokens per request` : "None yet"}</div></div>
      <div class="card stat"><div class="label">From cache</div><div class="value">${inputSide ? Math.round((t.cacheRead / inputSide) * 100) : 0}%</div><div class="foot">of input was cached context</div></div>
    </div>`;
    const heat = heatCard(usage);
    if (!t.requests) {
      return { toolbar, body: `${stats}<div class="card"><p class="empty">No usage in this range. Keyhop reads Claude Code, Codex, Gemini CLI, OpenCode and Pi records on this computer, and Cursor's usage export after a refresh.</p></div>${heat}` };
    }
    const grouped = chartGroup(usage);
    const legend = `<ul class="legend">${grouped.series.map((s) => `<li><span class="swatch" style="background:${s.color}"></span>${esc(s.name)}</li>`).join("")}</ul>`;
    const chart = `<section class="card">
      <div class="card-head"><h2>${ui.metric === "tokens" ? "Tokens" : "API value"} by ${usage.bucket}, stacked ${ui.group === "tool" ? "by tool" : ui.group === "model" ? "by model" : "by account"}</h2>${legend}</div>
      <div class="card-body chart">${stackedChart(usage, ui.metric, 280, "full", ui.group)}</div>
    </section>`;
    const mix = `<section class="card">
      <div class="card-head"><h2>Token mix</h2><span class="hint mono">${fmt.tokens(t.tokens)}</span></div>
      <div class="card-body">${mixBlock(t)}</div>
    </section>`;
    const toolsCard = `<section class="card"><div class="card-head"><h2>Tools</h2><span class="hint mono">${(usage.tools || []).length}</span></div>${toolTable(usage.tools || [], ui.metric)}</section>`;
    const models = `<section class="card"><div class="card-head"><h2>Models</h2><span class="hint mono">${usage.models.length}</span></div>${modelTable(usage.models, ui.metric, true)}</section>`;
    const accounts = `<section class="card"><div class="card-head"><h2>Accounts</h2><span class="hint mono">${usage.accounts.length}</span></div>${accountTable(usage.accounts, ui.metric)}</section>`;
    const placed = (usage.projects || []).filter((p) => p.path);
    const projects = placed.length
      ? `<section class="card"><div class="card-head"><h2>Projects</h2><span class="hint mono">${placed.length}</span></div>${projectTable(usage.projects, ui.metric)}</section>`
      : "";
    const makerList = usage.makers || [];
    const makers = makerList.length
      ? `<section class="card"><div class="card-head"><h2>Makers</h2><span class="hint mono">${makerList.length}</span></div>${makerTable(makerList, ui.metric)}</section>`
      : "";
    const sessions = (usage.sessions && usage.sessions.length)
      ? `<section class="card"><div class="card-head"><h2>Sessions</h2><span class="hint mono">${usage.sessions.length}</span></div>${sessionTable(usage.sessions, ui.metric)}</section>`
      : "";
    return { toolbar, body: `${stats}${chart}<div class="split wide-left">${heat}${mix}</div><div class="split">${toolsCard}${models}</div>${makers && projects ? `<div class="split">${makers}${projects}</div>` : makers + projects}${accounts}${sessions}` };
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

  function stackedChart(usage, metric, height, size, group) {
    const grouped = chartGroup(usage, group);
    const series = grouped.series, buckets = grouped.buckets;
    const W = chartWidth(size), H = height, L = 52, R = 4, T = 8, B = 26;
    const pw = W - L - R, ph = H - T - B;
    const pick = (v) => (v ? (metric === "tokens" ? v.tokens : v.cost) : 0);
    const columns = buckets.map((b) => series.map((s) => pick(b.values[s.id])));
    const ceiling = niceCeiling(Math.max(0, ...columns.map((c) => c.reduce((a, b) => a + b, 0))));
    const slot = pw / Math.max(1, buckets.length);
    const bw = Math.max(3, Math.min(slot * 0.58, 30));
    const label = (v) => (metric === "tokens" ? fmt.tokens(v) : v === 0 ? "$0" : v < 10 ? "$" + v.toFixed(2) : fmt.usd(v));
    const every = usage.bucket === "hour" ? 3 : buckets.length > 10 ? 5 : 1;
    let grid = "", bars = "", hits = "";
    for (let i = 0; i <= 4; i++) {
      const value = (ceiling / 4) * i, y = (T + ph - (value / ceiling) * ph).toFixed(1);
      grid += `<line class="${i ? "grid" : "base"}" x1="${L}" x2="${W - R}" y1="${y}" y2="${y}"/><text class="axis" x="${L - 8}" y="${y}" text-anchor="end" dominant-baseline="central">${label(value)}</text>`;
    }
    buckets.forEach((bucket, i) => {
      const cx = L + slot * (i + 0.5), x = cx - bw / 2;
      const present = series.map((s, j) => ({ s, v: columns[i][j] })).filter((e) => e.v > 0);
      let base = 0;
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
      if (i % every === 0) {
        const options = usage.bucket === "hour" ? { hour: "2-digit" } : buckets.length > 10 ? { month: "short", day: "numeric" } : { weekday: "short" };
        grid += `<text class="axis" x="${cx.toFixed(1)}" y="${H - 7}" text-anchor="middle">${esc(fmt.day(bucket.start, options))}</text>`;
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
    let cells = "", months = "", lastMonth = -1;
    days.forEach((day, i) => {
      const slot = i + offset, col = Math.floor(slot / 7), row = slot % 7;
      const level = !day.tokens ? 0 : day.tokens <= cuts[0] ? 1 : day.tokens <= cuts[1] ? 2 : day.tokens <= cuts[2] ? 3 : 4;
      const date = parse(day.day);
      if (row === 0 && date.getMonth() !== lastMonth && col < columns - 2) {
        months += `<text x="${col * (size + gap)}" y="11">${esc(fmt.day(date, { month: "short" }))}</text>`;
        lastMonth = date.getMonth();
      }
      cells += `<rect class="l${level}" x="${col * (size + gap)}" y="${top + row * (size + gap)}" width="${size}" height="${size}" rx="2.5"><title>${esc(fmt.day(date, { weekday: "short", month: "short", day: "numeric" }))} · ${day.tokens ? `${fmt.tokens(day.tokens)} tokens, ${fmt.usd(day.cost)}` : "no usage"}</title></rect>`;
    });
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
    return `<div class="mix-bar">${rows.filter((p) => p[1] > 0).map((p) => `<span class="${p[2]}" style="width:${((p[1] / sum) * 100).toFixed(2)}%" title="${p[0]}"></span>`).join("")}</div>
      <table class="table" style="margin:0 -16px -16px;width:calc(100% + 32px)"><tbody>${rows.map((p) => `<tr><td><div class="cell-name"><span class="swatch ${p[2]}"></span><span>${p[0]}</span></div></td><td class="right mono">${fmt.tokens(p[1])}</td><td class="right mono subtle">${Math.round((p[1] / sum) * 100)}%</td></tr>`).join("")}</tbody></table>${reasoning}`;
  }

  function modelTable(models, metric, showBars) {
    const value = (m) => (metric === "tokens" ? m.figures.tokens : m.figures.cost);
    const groups = [];
    const seen = new Map();
    models.forEach((m) => {
      const tool = m.tool || "unknown";
      if (!seen.has(tool)) { seen.set(tool, groups.length); groups.push({ tool, rows: [] }); }
      groups[seen.get(tool)].rows.push(m);
    });
    const peak = Math.max(0.000001, ...models.map(value));
    return groups.map((group) => {
      const sorted = group.rows.slice().sort((a, b) => value(b) - value(a));
      const rows = sorted.map((m) => `<tr class="clickable" data-action="filter-tool" data-value="${esc(m.tool || "")}">
      <td><span class="mono">${esc(m.model)}</span></td>
      ${showBars ? `<td class="bar-cell">${progress((value(m) / peak) * 100, null, "plain")}</td>` : ""}
      <td class="right mono">${metric === "tokens" ? fmt.tokens(m.figures.tokens) : fmt.usd(m.figures.cost)}</td>
    </tr>`).join("");
      return `<div class="model-group">
        <div class="group-head">${mark(group.tool)}<h2>${esc(toolName(group.tool))}</h2><span class="count">${sorted.length}</span></div>
        <table class="table"><thead><tr><th>Model</th>${showBars ? "<th></th>" : ""}<th class="right">${metric === "tokens" ? "Tokens" : "API value"}</th></tr></thead><tbody>${rows}</tbody></table>
      </div>`;
    }).join("");
  }

  // Whose models did the work, whichever tool ran them, with each maker's share of the range.
  function makerTable(makers, metric) {
    const value = (m) => (metric === "tokens" ? m.figures.tokens : m.figures.cost);
    const sum = makers.reduce((s, m) => s + value(m), 0) || 1;
    const peak = Math.max(0.000001, ...makers.map(value));
    const rows = makers.slice().sort((a, b) => value(b) - value(a)).map((m) => `<tr>
      <td><b>${esc(m.name)}</b><div class="subtle" style="font-size:11.5px" title="${esc(m.models.join(", "))}">${m.models.length} model${m.models.length === 1 ? "" : "s"}</div></td>
      <td class="bar-cell">${progress((value(m) / peak) * 100, null, "plain")}</td>
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
      <td class="bar-cell">${progress((value(p) / peak) * 100, null, "plain")}</td>
      <td class="right mono">${metric === "tokens" ? fmt.tokens(p.figures.tokens) : fmt.usd(p.figures.cost)}</td>
    </tr>`).join("");
    const more = projects.length > shown.length ? `<p class="empty-inline" style="padding:10px 16px">and ${projects.length - shown.length} more</p>` : "";
    return `<table class="table"><thead><tr><th>Project</th><th></th><th class="right">${metric === "tokens" ? "Tokens" : "API value"}</th></tr></thead><tbody>${rows}</tbody></table>${more}`;
  }

  function toolTable(tools, metric) {
    if (!tools.length) return `<p class="empty">No tools in this range.</p>`;
    const value = (t) => (metric === "tokens" ? t.figures.tokens : t.figures.cost);
    const sorted = tools.slice().sort((a, b) => value(b) - value(a));
    const rows = sorted.map((t) => `<tr class="clickable" data-action="filter-tool" data-value="${esc(t.id)}">
      <td><div class="cell-name">${mark(t.id)}<span>${esc(t.name)}</span></div></td>
      <td class="right mono">${metric === "tokens" ? fmt.tokens(t.figures.tokens) : fmt.usd(t.figures.cost)}</td>
      <td class="right mono subtle">${fmt.count(t.figures.requests)}</td>
    </tr>`).join("");
    return `<table class="table"><thead><tr><th>Tool</th><th class="right">${metric === "tokens" ? "Tokens" : "API value"}</th><th class="right">Requests</th></tr></thead><tbody>${rows}</tbody></table>`;
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
    const lines = [["Kind", "Name", "Tool", "Tokens", "API value", "Requests"].map(cell).join(",")];
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
    const W = chartWidth("wide"), H = 220, L = 52, R = 8, T = 16, B = 26;
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
    return `<section class="card"><div class="card-head"><h2>Appearance</h2><span class="hint">The scene behind this window</span></div>
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
    else if (data.updateError) updateRow = `<div class="setting-row"><div><b>Updates</b><p>${esc(data.updateError)}</p></div><button class="btn sm secondary" data-action="check-update">Try again</button></div>`;
    else if (!update) updateRow = `<div class="setting-row"><div><b>Checking for a new version</b>${busy("Asking GitHub for the latest release", "busy-note")}</div></div>`;
    else if (update.available) updateRow = `<div class="setting-row"><div><b>Keyhop ${esc(update.latest)} is available</b><p>You have ${esc(update.current)}. The download is checked against its SHA-256 before it installs.</p></div><button class="btn sm" data-action="install-update">Install update</button></div>`;
    else updateRow = `<div class="setting-row"><div><b>Up to date</b><p>Keyhop ${esc(update.current)} is the latest version.</p></div><button class="btn sm secondary" data-action="check-update">Check again</button></div>`;

    const tools = doctor ? `<div class="list">${doctor.tools.map((t) => `<div class="row">
        <div class="who">${mark(t.id)}<div><b>${esc(t.name)}</b><small>${t.signedInAs ? `Signed in as ${esc(t.signedInAs)}` : t.problem ? esc(t.problem) : t.installed ? "Signed out" : "Not found on this computer"}</small></div></div>
        <div class="mono subtle" style="margin:8px 0 0 30px;overflow-wrap:anywhere">${esc(t.loginLocation)}</div>
      </div>`).join("")}</div>` : (isStatic ? `<p class="empty">Not included in a saved page.</p>` : busy("Looking for tools on this computer", "empty"));

    return { body: `
      ${!isStatic && state.cloud?.available ? cloudCard(state.cloud) : ""}
      ${isStatic ? "" : workCard(state.work)}
      ${isStatic ? "" : appearanceCard()}
      <section class="card"><div class="card-head"><h2>Updates</h2></div><div class="card-body">${updateRow}</div></section>
      <div class="split">
        <section class="card"><div class="card-head"><h2>Tools on this computer</h2></div>${tools}</section>
        <section class="card"><div class="card-head"><h2>Storage and privacy</h2></div>
          <div class="list">
            <div class="row kv"><span>Data folder</span><span class="mono">${esc(doctor?.dataDirectory || state.dataDirectory)}</span></div>
            <div class="row kv"><span>Saved logins</span><span>${esc(doctor ? `${doctor.savedAccounts} in ${doctor.secretStore}` : state.status.secretStore)}</span></div>
            <div class="row kv"><span>Network</span><span>The providers' own usage and sign-in services, GitHub for updates${state.cloud?.linked ? `, and Keyhop cloud for your daily totals${state.cloud.sharesLimits ? " and current limits" : ""}` : ""}. No analytics.</span></div>
            <div class="row kv"><span>This window</span><span>Served by keyhop on 127.0.0.1 only, with a private session key.</span></div>
          </div>
        </section>
      </div>` };
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

  document.addEventListener("pointermove", (event) => {
    const tip = $("#tip");
    const hit = event.target.closest && event.target.closest(".hit");
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
    const when = usage.bucket === "hour" ? fmt.day(bucket.start, { weekday: "short", hour: "2-digit", minute: "2-digit" }) : fmt.day(bucket.start, { weekday: "short", month: "short", day: "numeric" });
    tip.innerHTML = `<b>${esc(when)} · <span class="mono">${esc(show(total))}</span></b>${rows.length ? rows.map((e) => `<div><span class="swatch" style="background:${e.s.color}"></span><span>${esc(e.s.name)}</span><span class="mono">${esc(show(pick(e.v)))}</span></div>`).join("") : `<div><span></span><span>No usage</span><span></span></div>`}`;
    tip.hidden = false;
    const box = tip.getBoundingClientRect();
    let x = event.clientX + 14, y = event.clientY + 14;
    if (x + box.width > innerWidth - 10) x = event.clientX - box.width - 14;
    if (y + box.height > innerHeight - 10) y = event.clientY - box.height - 14;
    tip.style.left = Math.max(10, x) + "px";
    tip.style.top = Math.max(10, y) + "px";
  });

  // MARK: Actions

  const editing = () => ui.editing || ui.confirming || ["INPUT", "SELECT"].includes(document.activeElement?.tagName);

  async function act(button, call, label) {
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
      render();
      watchActivity();
    }
  }

  async function go(section) {
    ui.section = section;
    history.replaceState(null, "", "#" + section);
    render();
    $("#main").scrollTop = 0;
    await loadSection();
    render();
  }

  document.addEventListener("click", async (event) => {
    const link = event.target.closest("#nav a");
    if (link) { event.preventDefault(); if (link.dataset.section !== ui.section) go(link.dataset.section); return; }
    const el = event.target.closest("[data-action]");
    if (!el || el.disabled || el.tagName === "SELECT") return;
    const id = el.dataset.id;
    switch (el.dataset.action) {
      case "goto": go(el.dataset.section); break;
      case "refresh":
        if (data.state?.refreshing) break;
        act(null, () => { data.state.refreshing = true; renderActivity(); return api("/api/refresh", {}); });
        break;
      case "switch": act(el, () => api("/api/switch", { id }), "Switching"); break;
      case "add": act(el, () => api("/api/add", { tool: el.dataset.tool }), "Signing out"); break;
      case "add-stop": act(el, () => api("/api/add/stop", { tool: el.dataset.tool }), "Stopping"); break;
      case "edit": ui.editing = id; ui.confirming = null; render(); $("form[data-form=rename] input")?.focus(); break;
      case "cancel-edit": ui.editing = null; render(); break;
      case "confirm-remove": ui.confirming = id; ui.editing = null; render(); break;
      case "cancel-remove": ui.confirming = null; render(); break;
      case "remove": act(el, () => api("/api/remove", { id }).finally(() => { ui.confirming = null; }), "Removing"); break;
      case "range": case "metric": case "group":
        ui[el.dataset.action] = el.dataset.value;
        render();
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
      case "check-update": data.update = null; data.updateError = null; render(); await loadSection(); render(); break;
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
    if (form.dataset.form === "work-folder") {
      const folder = String(form.elements.folder.value || "").trim();
      if (!folder) { toast("Type a folder to scan, like ~/Projects.", true); return; }
      act(button, () => api("/api/work", { add: folder }));
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && (ui.editing || ui.confirming || ui.budgetEdit)) { ui.editing = ui.confirming = ui.budgetEdit = null; render(); }
  });
  const followVisibility = () => document.documentElement.toggleAttribute("data-away", document.hidden);
  document.addEventListener("visibilitychange", followVisibility);
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
