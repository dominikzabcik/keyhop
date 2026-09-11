import Foundation

/// The dashboard app: one page of HTML, CSS and JavaScript with no outside resources. Served live by
/// `switchr dashboard`, or saved with its data inside by `switchr insights --output`.
enum DashboardPage {
    static func render(boot: String?) -> String {
        var page = template
        for provider in Provider.allCases {
            page = page.replacingOccurrences(of: "{{mark-\(provider.rawValue)}}", with: ProviderMarks.path(for: provider))
        }
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
<title>Switchr</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='7' fill='%23171717'/%3E%3Cg fill='%23EBEBEB'%3E%3Crect x='6' y='10' width='4' height='4' rx='1'/%3E%3Crect x='11' y='10' width='4' height='4' rx='1'/%3E%3Crect x='16' y='10' width='4' height='4' rx='1'/%3E%3Crect x='6' y='18' width='4' height='4' rx='1'/%3E%3C/g%3E%3Cg fill='%23EBEBEB' fill-opacity='.25'%3E%3Crect x='21' y='10' width='4' height='4' rx='1'/%3E%3Crect x='11' y='18' width='4' height='4' rx='1'/%3E%3Crect x='16' y='18' width='4' height='4' rx='1'/%3E%3Crect x='21' y='18' width='4' height='4' rx='1'/%3E%3C/g%3E%3C/svg%3E">
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
.brand svg { width: 22px; height: 12px; flex: none; }
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

.content { display: flex; flex-direction: column; min-width: 0; min-height: 0; }
.topbar { display: flex; align-items: center; justify-content: space-between; gap: 16px; height: 52px; padding: 0 24px; border-bottom: 1px solid var(--border); flex: none; }
.topbar h1 { margin: 0; font-size: 15px; font-weight: 620; }
.toolbar { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; justify-content: flex-end; }
.main { flex: 1; overflow: auto; padding: 22px 24px 40px; }
.page { max-width: 1320px; margin: 0 auto; display: grid; gap: 16px; }
.lede { margin: 0 0 4px; color: var(--muted); }

/* Components */
.card { background: var(--panel); border: 1px solid var(--border); border-radius: 10px; min-width: 0; }
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
.btn.working { opacity: .6; cursor: progress; }
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
.pulse { display: inline-flex; gap: 3px; }
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
.m1 { background: hsl(0 0% 100% / .9); } .m2 { background: hsl(0 0% 100% / .55); } .m3 { background: hsl(0 0% 100% / .3); } .m4 { background: hsl(0 0% 100% / .14); }
.table { width: 100%; border-collapse: collapse; }
.table th { text-align: left; font-weight: 500; color: var(--subtle); font-size: 12px; padding: 10px 16px; border-bottom: 1px solid var(--border); }
.table td { padding: 10px 16px; border-bottom: 1px solid var(--border); vertical-align: middle; }
.table tr:last-child td { border-bottom: 0; }
.table tbody tr:hover td { background: hsl(0 0% 100% / .02); }
.table .right { text-align: right; }
.table .bar-cell { width: 34%; }
.cell-name { display: flex; align-items: center; gap: 8px; min-width: 0; }
.cell-name span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

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
@media (prefers-reduced-motion: reduce) { *, *::before, *::after { animation: none !important; transition: none !important; } }
</style>
</head>
<body>
<svg width="0" height="0" style="position:absolute" aria-hidden="true">
  <symbol id="mark-claude" viewBox="0 0 24 24"><path d="{{mark-claude}}"/></symbol>
  <symbol id="mark-cursor" viewBox="0 0 24 24"><path d="{{mark-cursor}}"/></symbol>
  <symbol id="mark-codex" viewBox="0 0 24 24"><path d="{{mark-codex}}"/></symbol>
  <symbol id="i-overview" viewBox="0 0 16 16"><rect x="2" y="2" width="5" height="5" rx="1.2"/><rect x="9" y="2" width="5" height="5" rx="1.2"/><rect x="2" y="9" width="5" height="5" rx="1.2"/><rect x="9" y="9" width="5" height="5" rx="1.2"/></symbol>
  <symbol id="i-accounts" viewBox="0 0 16 16"><circle cx="6" cy="5.5" r="2.5"/><path d="M1.8 13.5c.5-2.3 2.2-3.5 4.2-3.5s3.7 1.2 4.2 3.5"/><path d="M10.5 3.2a2.4 2.4 0 0 1 0 4.6"/><path d="M12.2 10.3c1.1.5 1.8 1.6 2 3.2"/></symbol>
  <symbol id="i-usage" viewBox="0 0 16 16"><path d="M2 13.5h12"/><path d="M4 11V7"/><path d="M8 11V3.5"/><path d="M12 11V5.5"/></symbol>
  <symbol id="i-budgets" viewBox="0 0 16 16"><rect x="1.8" y="3.5" width="12.4" height="9" rx="1.8"/><path d="M1.8 6.5h12.4"/><path d="M10.5 9.8h1.5"/></symbol>
  <symbol id="i-settings" viewBox="0 0 16 16"><path d="M2 4.5h6"/><path d="M11 4.5h3"/><circle cx="9.5" cy="4.5" r="1.5"/><path d="M2 11.5h2"/><path d="M7 11.5h7"/><circle cx="5.5" cy="11.5" r="1.5"/></symbol>
  <symbol id="i-refresh" viewBox="0 0 16 16"><path d="M13.5 8a5.5 5.5 0 0 1-9.6 3.6"/><path d="M2.5 8a5.5 5.5 0 0 1 9.6-3.6"/><path d="M12.3 1.8v2.8H9.5"/><path d="M3.7 14.2v-2.8h2.8"/></symbol>
  <symbol id="i-update" viewBox="0 0 16 16"><path d="M8 2.5v7.5"/><path d="M5 7l3 3 3-3"/><path d="M3 13.5h10"/></symbol>
  <symbol id="i-alert" viewBox="0 0 16 16"><path d="M8 2.2 14.3 13H1.7z"/><path d="M8 6.5v3"/><path d="M8 11.4v.1"/></symbol>
  <symbol id="i-plus" viewBox="0 0 16 16"><path d="M8 3.5v9M3.5 8h9"/></symbol>
</svg>

<div class="shell">
  <aside class="sidebar">
    <div class="brand">
      <svg viewBox="0 0 22 12" aria-hidden="true"><g fill="#EBEBEB"><rect x="0" y="0" width="4" height="4" rx="1"/><rect x="6" y="0" width="4" height="4" rx="1"/><rect x="12" y="0" width="4" height="4" rx="1"/><rect x="0" y="8" width="4" height="4" rx="1"/></g><g fill="#EBEBEB" fill-opacity=".22"><rect x="18" y="0" width="4" height="4" rx="1"/><rect x="6" y="8" width="4" height="4" rx="1"/><rect x="12" y="8" width="4" height="4" rx="1"/><rect x="18" y="8" width="4" height="4" rx="1"/></g></svg>
      <b>Switchr</b>
      <span id="mode"></span>
    </div>
    <nav class="nav" id="nav" aria-label="Sections">
      <a href="#overview" data-section="overview"><svg><use href="#i-overview"/></svg>Overview</a>
      <a href="#accounts" data-section="accounts"><svg><use href="#i-accounts"/></svg>Accounts</a>
      <a href="#usage" data-section="usage"><svg><use href="#i-usage"/></svg>Usage</a>
      <a href="#budgets" data-section="budgets"><svg><use href="#i-budgets"/></svg>Budgets</a>
      <a href="#settings" data-section="settings"><svg><use href="#i-settings"/></svg>Settings</a>
    </nav>
    <div class="sidebar-foot">
      <button class="foot-row" id="refresh" data-action="refresh"><svg class="icon"><use href="#i-refresh"/></svg><span><b>Refresh</b><small id="read">Limits not read yet</small></span></button>
      <button class="foot-row" data-action="goto" data-section="settings"><svg class="icon"><use href="#i-update"/></svg><span><b id="update-title">Check for updates</b><small id="version"></small></span></button>
    </div>
  </aside>
  <div class="content">
    <header class="topbar"><h1 id="title">Overview</h1><div class="toolbar" id="toolbar"></div></header>
    <main class="main" id="main"><div class="page"><p class="lede">Reading your accounts…</p></div></main>
  </div>
</div>
<div class="tip" id="tip" hidden></div>
<div class="toast away" id="toast" role="status" aria-live="polite"></div>
<script id="boot" type="application/json">{{boot}}</script>
<script>
(() => {
  "use strict";
  const SECTIONS = ["overview", "accounts", "usage", "budgets", "settings"];
  const TITLES = { overview: "Overview", accounts: "Accounts", usage: "Usage", budgets: "Budgets", settings: "Settings" };
  const $ = (selector, root = document) => root.querySelector(selector);
  const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  const store = {
    get(key) { try { return sessionStorage.getItem(key); } catch { return null; } },
    set(key, value) { try { sessionStorage.setItem(key, value); } catch {} },
  };

  const boot = JSON.parse($("#boot").textContent || "null");
  const isStatic = !!boot;
  const params = new URLSearchParams(location.hash.slice(1));
  let token = params.get("k") || store.get("switchr-token");
  if (params.get("k")) store.set("switchr-token", token);
  const wanted = params.get("s") || location.hash.slice(1);
  const ui = {
    section: SECTIONS.includes(wanted) ? wanted : (boot?.section || "overview"),
    range: "week", metric: "tokens", tool: "all",
    editing: null, confirming: null, budgetEdit: null, offline: null,
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
  const icon = (name) => `<svg class="icon" aria-hidden="true"><use href="#i-${name}"/></svg>`;
  const maxUsed = (account) => Math.max(0, ...(account.limits || []).map((l) => l.usedPercent));
  const toolName = (id) => (data.state?.status.tools.find((t) => t.id === id) || {}).name || id;

  // MARK: Data

  async function api(path, body) {
    const init = { method: body === undefined ? "GET" : "POST", headers: { Authorization: "Bearer " + token } };
    if (body !== undefined) { init.headers["Content-Type"] = "application/json"; init.body = JSON.stringify(body); }
    let response;
    try { response = await fetch(path, init); } catch { throw new Error("Switchr isn't running anymore. Open it again from the tray or with switchr dashboard."); }
    let payload = {};
    try { payload = await response.json(); } catch {}
    if (!response.ok) throw new Error(payload.error || `Switchr answered ${response.status}.`);
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
    data.usage[key] = await api(`/api/usage?range=${encodeURIComponent(range)}&tool=${encodeURIComponent(tool)}`);
    return data.usage[key];
  }

  async function loadSection() {
    try {
      if (ui.section === "overview") await Promise.all([loadUsage("today"), loadUsage("week")]);
      if (ui.section === "usage") await loadUsage(ui.range, ui.tool);
      if (ui.section === "budgets") await loadUsage("month");
      if (ui.section === "settings" && !isStatic) {
        data.doctor = await api("/api/doctor");
        try { data.update = await api("/api/update"); data.updateError = null; } catch (error) { data.updateError = error.message; }
      }
    } catch (error) {
      ui.offline = error.message;
    }
  }

  // MARK: Shell

  function render() {
    renderSidebar();
    if (!data.state) return;
    const tools = data.state.status.tools;
    const page = { overview: overviewPage, accounts: accountsPage, usage: usagePage, budgets: budgetsPage, settings: settingsPage }[ui.section](tools);
    $("#title").textContent = TITLES[ui.section];
    $("#toolbar").innerHTML = page.toolbar || "";
    const offline = ui.offline ? `<div class="notice">${icon("alert")}<div><p>${esc(ui.offline)}</p></div></div>` : "";
    $("#main").innerHTML = `<div class="page">${offline}${page.body}</div>`;
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
    $("#read").textContent = state?.refreshing ? "Reading limits…" : read ? `Limits read ${fmt.relative(read)}` : "Limits not read yet";
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

  function limits(account, count = 2) {
    if (!account.limits?.length) {
      return account.error ? `<p class="problem">${esc(account.error)}</p>` : `<p class="empty-inline subtle">Limits not read yet</p>`;
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

    const stats = `<div class="stats">
      <div class="card stat"><div class="label">Tokens today ${today ? fmt.change(today.total.tokens, today.previous.tokens) : ""}</div><div class="value">${fmt.tokens(status.today.tokens)}</div><div class="foot">${fmt.count(status.today.requests)} requests</div></div>
      <div class="card stat"><div class="label">API value today</div><div class="value">${fmt.usd(status.today.cost)}</div><div class="foot">At standard API prices</div></div>
      <div class="card stat"><div class="label">This week ${week ? fmt.change(week.total.tokens, week.previous.tokens) : ""}</div><div class="value">${week ? fmt.tokens(week.total.tokens) : "…"}</div><div class="foot">${week ? `${fmt.usd(week.total.cost)} API value` : ""}</div></div>
      <div class="card stat"><div class="label">Closest to a limit</div><div class="value">${near ? `${Math.round(near.limit.usedPercent)}%` : "None"}</div><div class="foot">${near ? `${esc(near.tool.name)} · ${esc(windowName(near.limit.label))}` : "No limits read yet"}</div></div>
    </div>`;

    const inUse = `<section class="card">
      <div class="card-head"><h2>In use</h2><span class="hint">Each tool's current account and its limits</span></div>
      <div class="list">${tools.map((tool) => {
        const account = tool.accounts.find((a) => a.active);
        const other = alternative(tool, account);
        const adding = data.state.adding.includes(tool.id);
        const identity = account
          ? `<div class="who">${mark(tool.id)}<div><b>${esc(tool.name)}</b><small>${esc(account.name)}${account.plan ? ` · ${esc(account.plan)}` : ""}</small></div></div>`
          : `<div class="who">${mark(tool.id)}<div><b>${esc(tool.name)}</b><small>${tool.accounts.length ? "Signed out" : "No saved accounts"}</small></div></div>`;
        const middle = adding ? `<div class="waiting"><span class="pulse"><i></i><i></i><i></i></span>Waiting for the new login</div>`
          : account ? limits(account) : `<p class="empty-inline subtle">${esc(tool.signInHint)}</p>`;
        const actions = isStatic ? "" : other
          ? `<button class="btn sm secondary" data-action="switch" data-id="${esc(other.id)}">Switch to ${esc(other.name)}</button>`
          : `<button class="btn sm ghost" data-action="goto" data-section="accounts">Accounts</button>`;
        return `<div class="row tool-row">${identity}${middle}<div class="row-actions">${actions}</div></div>`;
      }).join("")}</div>
    </section>`;

    const hourCard = `<section class="card">
      <div class="card-head"><h2>Today by hour</h2><span class="hint">${today ? esc(busiestHour(today)) : ""}</span></div>
      <div class="card-body">${today ? dotHours(today) : `<p class="empty-inline">Reading usage…</p>`}</div>
    </section>`;
    const weekCard = `<section class="card">
      <div class="card-head"><h2>Last 7 days</h2><button class="btn sm ghost" data-action="goto" data-section="usage">Open usage</button></div>
      <div class="card-body">${week ? (week.total.requests ? `<div class="chart">${stackedChart(week, "tokens", 180, "half")}</div>` : `<p class="empty-inline">No usage in the last 7 days.</p>`) : `<p class="empty-inline">Reading usage…</p>`}</div>
    </section>`;
    const budgetsCard = `<section class="card">
      <div class="card-head"><h2>Budgets</h2><button class="btn sm ghost" data-action="goto" data-section="budgets">${status.budgets.length ? "Manage" : "Set a budget"}</button></div>
      ${status.budgets.length ? `<div class="list">${status.budgets.slice(0, 3).map(budgetRow).join("")}</div>` : `<p class="empty">No budgets yet. A budget warns you at 80% and 100%.</p>`}
    </section>`;
    const modelsCard = `<section class="card">
      <div class="card-head"><h2>Top models this week</h2></div>
      ${week && week.models.length ? modelTable(week.models.slice(0, 4), "tokens", false) : `<p class="empty">No models used this week.</p>`}
    </section>`;

    return { body: `${alerts}${stats}${inUse}<div class="split">${hourCard}${weekCard}</div><div class="split">${budgetsCard}${modelsCard}</div>` };
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
      const rows = tool.accounts.map((account) => accountRow(account)).join("");
      const waiting = adding ? `<div class="row"><div class="waiting"><span class="pulse"><i></i><i></i><i></i></span><span>Waiting for a new ${esc(tool.name)} login. ${esc(tool.signInHint)}</span></div></div>` : "";
      const empty = !tool.accounts.length && !adding ? `<p class="empty">${esc(tool.signInHint)}</p>` : "";
      return `<section class="group">
        <div class="group-head">${mark(tool.id)}<h2>${esc(tool.name)}</h2><span class="count">${tool.accounts.length}</span>
          ${isStatic ? "" : `<button class="btn sm secondary" data-action="add" data-tool="${esc(tool.id)}" ${adding ? "disabled" : ""}>${icon("plus")}Add account</button>`}</div>
        <div class="card list">${waiting}${rows}${empty}</div>
      </section>`;
    }).join("");
    return { body: `<p class="lede">Every login Switchr keeps. Switching saves the login in use first, so none is ever lost.</p>${body}` };
  }

  function accountRow(account) {
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
      <div>${limits(account)}</div>
      <div class="today">${today}</div>
      <div class="row-actions">${actions}</div>
    </div>`;
  }

  // MARK: Usage

  function usagePage(tools) {
    const toolbar = tabs("range", [["today", "Today"], ["week", "7 days"], ["month", "Month"], ["30d", "30 days"]], ui.range)
      + tabs("metric", [["tokens", "Tokens"], ["cost", "API value"]], ui.metric)
      + `<select class="field" data-action="tool" aria-label="Tool" ${isStatic ? "disabled" : ""}>${[["all", "All tools"], ...tools.map((t) => [t.id, t.name])].map(([v, l]) => `<option value="${v}" ${v === ui.tool ? "selected" : ""}>${esc(l)}</option>`).join("")}</select>`;
    const usage = data.usage[`${ui.range}:${ui.tool}`] || (isStatic ? data.usage[`${ui.range}:all`] : null);
    if (!usage) return { toolbar, body: `<div class="card"><p class="empty">Reading usage…</p></div>` };

    const t = usage.total, p = usage.previous;
    const inputSide = t.input + t.cacheRead + t.cacheWrite;
    const stats = `<div class="stats">
      <div class="card stat"><div class="label">Tokens ${fmt.change(t.tokens, p.tokens)}</div><div class="value">${fmt.tokens(t.tokens)}</div><div class="foot">vs ${fmt.tokens(p.tokens)} the period before</div></div>
      <div class="card stat"><div class="label">API value ${fmt.change(t.cost, p.cost)}</div><div class="value">${fmt.usd(t.cost)}</div><div class="foot">${t.billed > 0 ? `${fmt.usd(t.billed)} billed on demand` : "At standard API prices"}</div></div>
      <div class="card stat"><div class="label">Requests</div><div class="value">${fmt.count(t.requests)}</div><div class="foot">${t.requests ? `${fmt.tokens(t.tokens / t.requests)} tokens per request` : "None yet"}</div></div>
      <div class="card stat"><div class="label">From cache</div><div class="value">${inputSide ? Math.round((t.cacheRead / inputSide) * 100) : 0}%</div><div class="foot">of input was cached context</div></div>
    </div>`;
    const heat = heatCard(usage);
    if (!t.requests) {
      return { toolbar, body: `${stats}<div class="card"><p class="empty">No usage in this range. Switchr reads Claude Code and Codex logs on this computer, and Cursor's usage export after a refresh.</p></div>${heat}` };
    }
    const legend = `<ul class="legend">${usage.series.map((s) => `<li><span class="swatch" style="background:${s.color}"></span>${esc(s.name)}</li>`).join("")}</ul>`;
    const chart = `<section class="card">
      <div class="card-head"><h2>${ui.metric === "tokens" ? "Tokens" : "API value"} by ${usage.bucket}</h2>${legend}</div>
      <div class="card-body chart">${stackedChart(usage, ui.metric, 280, "full")}</div>
    </section>`;
    const mix = `<section class="card">
      <div class="card-head"><h2>Token mix</h2><span class="hint mono">${fmt.tokens(t.tokens)}</span></div>
      <div class="card-body">${mixBlock(t)}</div>
    </section>`;
    const models = `<section class="card"><div class="card-head"><h2>Models</h2><span class="hint mono">${usage.models.length}</span></div>${modelTable(usage.models, ui.metric, true)}</section>`;
    const accounts = `<section class="card"><div class="card-head"><h2>Accounts</h2><span class="hint mono">${usage.accounts.length}</span></div>${accountTable(usage.accounts, ui.metric)}</section>`;
    return { toolbar, body: `${stats}${chart}<div class="split wide-left">${heat}${mix}</div><div class="split">${models}${accounts}</div>` };
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

  function stackedChart(usage, metric, height, size) {
    const W = chartWidth(size), H = height, L = 52, R = 4, T = 8, B = 26;
    const pw = W - L - R, ph = H - T - B;
    const pick = (v) => (v ? (metric === "tokens" ? v.tokens : v.cost) : 0);
    const columns = usage.buckets.map((b) => usage.series.map((s) => pick(b.values[s.id])));
    const ceiling = niceCeiling(Math.max(0, ...columns.map((c) => c.reduce((a, b) => a + b, 0))));
    const slot = pw / Math.max(1, usage.buckets.length);
    const bw = Math.max(3, Math.min(slot * 0.58, 30));
    const label = (v) => (metric === "tokens" ? fmt.tokens(v) : v === 0 ? "$0" : v < 10 ? "$" + v.toFixed(2) : fmt.usd(v));
    const every = usage.bucket === "hour" ? 3 : usage.buckets.length > 10 ? 5 : 1;
    let grid = "", bars = "", hits = "";
    for (let i = 0; i <= 4; i++) {
      const value = (ceiling / 4) * i, y = (T + ph - (value / ceiling) * ph).toFixed(1);
      grid += `<line class="${i ? "grid" : "base"}" x1="${L}" x2="${W - R}" y1="${y}" y2="${y}"/><text class="axis" x="${L - 8}" y="${y}" text-anchor="end" dominant-baseline="central">${label(value)}</text>`;
    }
    usage.buckets.forEach((bucket, i) => {
      const cx = L + slot * (i + 0.5), x = cx - bw / 2;
      const present = usage.series.map((s, j) => ({ s, v: columns[i][j] })).filter((e) => e.v > 0);
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
        const options = usage.bucket === "hour" ? { hour: "2-digit" } : usage.buckets.length > 10 ? { month: "short", day: "numeric" } : { weekday: "short" };
        grid += `<text class="axis" x="${cx.toFixed(1)}" y="${H - 7}" text-anchor="middle">${esc(fmt.day(bucket.start, options))}</text>`;
      }
      hits += `<rect class="hit" x="${(L + slot * i).toFixed(1)}" y="${T}" width="${slot.toFixed(1)}" height="${ph}" data-bucket="${i}" data-metric="${metric}" data-key="${usage.range}:${usage.tool}"/>`;
    });
    return `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="${metric === "tokens" ? "Tokens" : "API value"} by ${usage.bucket}">${grid}<g>${bars}</g>${hits}</svg>`;
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
    const parts = [["Input", t.input, "m1"], ["Output", t.output, "m2"], ["Cache reads", t.cacheRead, "m3"], ["Cache writes", t.cacheWrite, "m4"]];
    const sum = parts.reduce((s, p) => s + p[1], 0) || 1;
    return `<div class="mix-bar">${parts.filter((p) => p[1] > 0).map((p) => `<span class="${p[2]}" style="width:${((p[1] / sum) * 100).toFixed(2)}%" title="${p[0]}"></span>`).join("")}</div>
      <table class="table" style="margin:0 -16px -16px;width:calc(100% + 32px)"><tbody>${parts.map((p) => `<tr><td><div class="cell-name"><span class="swatch ${p[2]}"></span><span>${p[0]}</span></div></td><td class="right mono">${fmt.tokens(p[1])}</td><td class="right mono subtle">${Math.round((p[1] / sum) * 100)}%</td></tr>`).join("")}</tbody></table>`;
  }

  function modelTable(models, metric, showBars) {
    const value = (m) => (metric === "tokens" ? m.figures.tokens : m.figures.cost);
    const sorted = models.slice().sort((a, b) => value(b) - value(a));
    const peak = Math.max(0.000001, ...sorted.map(value));
    const rows = sorted.slice(0, 10).map((m) => `<tr>
      <td><span class="mono">${esc(m.model)}</span></td>
      ${showBars ? `<td class="bar-cell">${progress((value(m) / peak) * 100, null, "plain")}</td>` : ""}
      <td class="right mono">${metric === "tokens" ? fmt.tokens(m.figures.tokens) : fmt.usd(m.figures.cost)}</td>
    </tr>`).join("");
    return `<table class="table"><thead><tr><th>Model</th>${showBars ? "<th></th>" : ""}<th class="right">${metric === "tokens" ? "Tokens" : "API value"}</th></tr></thead><tbody>${rows}</tbody></table>`;
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
      </div>`).join("")}</div>` : `<p class="empty">No budgets yet. Budgets count usage at API prices and warn you at 80% and 100%.</p>`;
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
    const byAccount = !month ? `<p class="empty">Reading this month's usage…</p>` : month.total.requests ? accountTable(month.accounts, "cost") : `<p class="empty">No usage this month yet.</p>`;
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
    if (!usage) return `<section class="card"><div class="card-head"><h2>This month</h2></div><p class="empty">Reading this month's usage…</p></section>`;
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

  // MARK: Settings

  function settingsPage() {
    const state = data.state, doctor = data.doctor, update = data.update;
    let updateRow;
    if (isStatic) updateRow = `<div class="setting-row"><div><b>Version</b><p>Saved from Switchr ${esc(state.version)}</p></div></div>`;
    else if (data.updateError) updateRow = `<div class="setting-row"><div><b>Updates</b><p>${esc(data.updateError)}</p></div><button class="btn sm secondary" data-action="check-update">Try again</button></div>`;
    else if (!update) updateRow = `<div class="setting-row"><div><b>Updates</b><p>Checking GitHub…</p></div></div>`;
    else if (update.available) updateRow = `<div class="setting-row"><div><b>Switchr ${esc(update.latest)} is available</b><p>You have ${esc(update.current)}. The download is checked against its SHA-256 before it installs.</p></div><button class="btn sm" data-action="install-update">Install update</button></div>`;
    else updateRow = `<div class="setting-row"><div><b>Up to date</b><p>Switchr ${esc(update.current)} is the latest version.</p></div><button class="btn sm secondary" data-action="check-update">Check again</button></div>`;

    const tools = doctor ? `<div class="list">${doctor.tools.map((t) => `<div class="row">
        <div class="who">${mark(t.id)}<div><b>${esc(t.name)}</b><small>${t.signedInAs ? `Signed in as ${esc(t.signedInAs)}` : t.problem ? esc(t.problem) : t.installed ? "Signed out" : "Not found on this computer"}</small></div></div>
        <div class="mono subtle" style="margin:8px 0 0 30px;overflow-wrap:anywhere">${esc(t.loginLocation)}</div>
      </div>`).join("")}</div>` : `<p class="empty">${isStatic ? "Not included in a saved page." : "Looking at this computer…"}</p>`;

    return { body: `
      <section class="card"><div class="card-head"><h2>Updates</h2></div><div class="card-body">${updateRow}</div></section>
      <div class="split">
        <section class="card"><div class="card-head"><h2>Tools on this computer</h2></div>${tools}</section>
        <section class="card"><div class="card-head"><h2>Storage and privacy</h2></div>
          <div class="list">
            <div class="row kv"><span>Data folder</span><span class="mono">${esc(doctor?.dataDirectory || state.dataDirectory)}</span></div>
            <div class="row kv"><span>Saved logins</span><span>${esc(doctor ? `${doctor.savedAccounts} in ${doctor.secretStore}` : state.status.secretStore)}</span></div>
            <div class="row kv"><span>Network</span><span>The providers' own usage and sign-in services, and GitHub for updates. No analytics.</span></div>
            <div class="row kv"><span>This window</span><span>Served by switchr on 127.0.0.1 only, with a private session key.</span></div>
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
    const bucket = usage?.buckets[+hit.dataset.bucket];
    if (!bucket) { tip.hidden = true; return; }
    const metric = hit.dataset.metric;
    const pick = (v) => (metric === "tokens" ? v.tokens : v.cost);
    const show = (v) => (metric === "tokens" ? fmt.tokens(v) : fmt.usd(v));
    const rows = usage.series.map((s) => ({ s, v: bucket.values[s.id] })).filter((e) => e.v && pick(e.v) > 0).reverse();
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

  async function act(button, call) {
    if (button) { button.disabled = true; button.classList.add("working"); }
    try {
      const result = await call();
      if (result && result.message) toast(result.note ? `${result.message} ${result.note}` : result.message);
      await loadState();
      await loadSection();
    } catch (error) {
      toast(error.message, true);
    } finally {
      render();
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
      case "refresh": act(null, () => { data.state.refreshing = true; renderSidebar(); return api("/api/refresh", {}); }); break;
      case "switch": act(el, () => api("/api/switch", { id })); break;
      case "add": act(el, () => api("/api/add", { tool: el.dataset.tool })); break;
      case "edit": ui.editing = id; ui.confirming = null; render(); $("form[data-form=rename] input")?.focus(); break;
      case "cancel-edit": ui.editing = null; render(); break;
      case "confirm-remove": ui.confirming = id; ui.editing = null; render(); break;
      case "cancel-remove": ui.confirming = null; render(); break;
      case "remove": ui.confirming = null; act(el, () => api("/api/remove", { id })); break;
      case "range": case "metric":
        ui[el.dataset.action] = el.dataset.value;
        render();
        if (el.dataset.action === "range") { await loadSection(); render(); }
        break;
      case "edit-budget": ui.budgetEdit = el.dataset.scope; render(); $("form[data-form=budget] input[name=amount]")?.focus(); break;
      case "cancel-budget": ui.budgetEdit = null; render(); break;
      case "delete-budget": act(el, () => api("/api/budget", { scope: el.dataset.scope === "all" ? "all" : el.dataset.scope.replace("account:", ""), amount: null })); break;
      case "check-update": data.update = null; data.updateError = null; render(); await loadSection(); render(); break;
      case "install-update": act(el, () => api("/api/update", {})); break;
    }
  });

  document.addEventListener("change", async (event) => {
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
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && (ui.editing || ui.confirming || ui.budgetEdit)) { ui.editing = ui.confirming = ui.budgetEdit = null; render(); }
  });
  addEventListener("hashchange", () => {
    const section = location.hash.slice(1);
    if (SECTIONS.includes(section) && section !== ui.section) go(section);
  });
  let resizeTimer;
  addEventListener("resize", () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(() => { if (!editing()) render(); }, 150); });

  // MARK: Start

  async function start() {
    if (isStatic) { render(); return; }
    if (!token) {
      $("#main").innerHTML = `<div class="page"><div class="card"><p class="empty">This window isn't connected to Switchr. Open it from the tray, or run switchr dashboard.</p></div></div>`;
      return;
    }
    try {
      await loadState();
      render();
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
      } catch (error) {
        ui.offline = error.message;
        if (!editing()) render();
      }
    }, 20000);
  }
  start();
})();
</script>
</body>
</html>
"""##
}
