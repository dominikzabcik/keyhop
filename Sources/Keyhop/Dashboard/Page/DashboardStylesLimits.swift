import Foundation

/// Limits after KB-Limits: the pooled figure and its forecast, then each tool's logins.
extension DashboardPage {
    static let stylesLimits = ##"""
/* Limits after KB-Limits: the pooled figure beside its forecast, then each tool's logins as hairline rows. */
.main:has(.lim-page) { padding: 24px 28px 32px; }
.lim-page { width: 100%; max-width: 1480px; margin: 0 auto; display: grid; grid-template-columns: minmax(0, 1fr); gap: 32px; }
/* Many tools make a long filter: it keeps one line and scrolls sideways rather than wrapping. */
.top-title:has(.lim-tabs) { flex: 1 1 auto; }
.top-title .toolbar:has(.lim-tabs) { min-width: 0; flex-wrap: nowrap; }
.lim-tabs { max-width: 100%; overflow-x: auto; scrollbar-width: none; }
.lim-tabs::-webkit-scrollbar { display: none; }
.lim-tabs button { flex: none; display: inline-flex; align-items: center; gap: 7px; padding: 0 12px; white-space: nowrap; }
.lim-tabs .mark { width: 13px; height: 13px; color: hsl(var(--on) / .8); }
.lim-tabs .n { color: var(--subtle); font-weight: 500; font-variant-numeric: tabular-nums; }
.lim-top { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1.3fr); gap: 18px; }

.lim-total { display: flex; flex-direction: column; gap: 20px; padding: 24px 26px 26px; }
.lim-total-title { display: grid; gap: 6px; }
.lim-total h2 { margin: 0; font-size: 26px; line-height: 30px; font-weight: 500; letter-spacing: -.02em; }
.lim-big { display: flex; align-items: baseline; gap: 12px; flex-wrap: wrap; }
.lim-big b { font-size: clamp(40px, 4.4vw, 60px); line-height: .95; font-weight: 500; letter-spacing: -.04em; font-variant-numeric: tabular-nums; }
.lim-big > span { color: var(--muted); }
.lim-big.warn b { color: var(--warn-ink); }
.lim-big.bad b { color: var(--bad); }
.lim-note { margin: 0; max-width: 46ch; color: var(--muted); line-height: 20px; }
.lim-figs { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); margin-top: auto; padding-top: 18px; border-top: 1px solid hsl(var(--on) / .08); }
.lim-fig { display: grid; gap: 6px; align-content: start; min-width: 0; padding: 0 16px; border-left: 1px solid hsl(var(--on) / .08); }
.lim-fig:first-child { padding-left: 0; border-left: 0; }
.lim-fig-name { font-size: 12px; font-weight: 500; color: var(--muted); }
.lim-fig b { font-size: 20px; line-height: 24px; font-weight: 500; font-variant-numeric: tabular-nums; }
.lim-fig b.up { color: var(--good); }
.lim-fig b.warn { color: var(--warn-ink); }
.lim-fig b.bad { color: var(--bad); }
.lim-fig-sub { font-size: 11px; color: var(--subtle); overflow: hidden; text-overflow: ellipsis; }

.qcard { display: flex; flex-direction: column; gap: 14px; padding: 24px 26px 20px; overflow: hidden; }
.qcard > .empty { padding: 0; }
.lim-fore-head { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; flex-wrap: wrap; }
.lim-fore-head h2 { margin: 0; font-size: 13px; font-weight: 600; letter-spacing: -.01em; color: var(--fg); }
.lim-fore-tools { display: flex; align-items: center; justify-content: space-between; gap: 10px; flex-wrap: wrap; }
.qlegend { display: inline-flex; align-items: center; gap: 14px; font-size: 12px; color: var(--muted); }
.qlegend span { display: inline-flex; align-items: center; gap: 6px; }
.qlegend i { display: inline-block; width: 12px; height: 0; border-top: 2px solid var(--text); }
.qlegend i.dash { border-top: 2px dashed var(--fg2); }
.qlegend i.reset { width: 2px; height: 10px; border: 0; background: var(--good); }
.qlegend i.bar { width: 8px; height: 8px; border: 0; border-radius: 2px; background: hsl(var(--on) / .55); }
.qchart { flex: 1; min-height: 0; }
.qchart svg { display: block; width: 100%; height: auto; overflow: visible; }
.qchart .grid { stroke: hsl(var(--on) / .05); }
.qchart .base { stroke: hsl(var(--on) / .08); }
.qchart .axis { fill: var(--subtle); font: 11px var(--sans); }
.qchart .qline { fill: none; stroke: var(--text); stroke-width: 2; stroke-linejoin: round; }
.qchart .qline.ahead { stroke: var(--fg2); stroke-dasharray: 5 5; }
.qchart .qarea { fill: hsl(var(--on) / .05); }
.qchart .qarea.ahead { fill: hsl(var(--on) / .015); }
.qchart .qnow { stroke: hsl(var(--on) / .18); stroke-dasharray: 3 4; }
.qchart .qnow-label { fill: var(--text); font: 500 11px var(--sans); }
.qchart .qreset { stroke: var(--good); stroke-width: 2; }
.qchart .qgain { fill: var(--good); font: 600 10.5px var(--sans); }
.qchart .grid.day { stroke: hsl(var(--on) / .035); }
.qchart .qbar { fill: hsl(var(--on) / .55); }
.qchart .qbar:hover { fill: var(--text); }
.qchart .hit { fill: transparent; }

.lim-group, .lim-singles { display: grid; gap: 12px; min-width: 0; }
.lim-group-head { display: flex; align-items: center; gap: 12px; padding: 0 2px; min-width: 0; }
.lim-group-head .tile-mark { width: 30px; height: 30px; }
.lim-group-head .tile-mark .mark { width: 16px; height: 16px; }
.lim-group-head h2 { margin: 0; font-size: 18px; line-height: 24px; font-weight: 500; letter-spacing: -.01em; white-space: nowrap; }
.lim-sum { font-size: 12px; color: var(--muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.lim-sum.bad { color: var(--bad); }
.lim-group-head .btn { margin-left: auto; flex: none; }
.lim-list { overflow: visible; }
.lim-row { display: grid; grid-template-columns: minmax(170px, 240px) minmax(0, 1fr) 132px; gap: 24px; align-items: center; min-height: 76px; padding: 16px 22px; }
.lim-row + .lim-row { border-top: 1px solid hsl(var(--on) / .07); }
.lim-row:first-child { border-radius: 8px 8px 0 0; }
.lim-row:last-child { border-radius: 0 0 8px 8px; }
.lim-row:only-child { border-radius: 8px; }
.lim-row.wall { background: color-mix(in srgb, var(--red, #fb414a) 6%, transparent); }
.lim-list:has(.lim-row.wall:only-child) { border-color: color-mix(in srgb, var(--red, #fb414a) 22%, transparent); }
.lim-who { display: grid; gap: 4px; min-width: 0; }
.lim-name { display: flex; align-items: center; gap: 8px; min-width: 0; }
.lim-name b { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.lim-dot { flex: none; width: 6px; height: 6px; border-radius: 3px; background: var(--good); }
.lim-dot.warn { background: var(--warn); }
.lim-dot.bad { background: var(--red, #fb414a); }
.lim-pill { flex: none; display: inline-flex; align-items: center; height: 20px; padding: 0 7px; border-radius: 6px; font-size: 11px; font-weight: 600; }
.lim-pill.in-use { background: hsl(var(--on) / .09); color: var(--fg); }
.lim-pill.good { background: color-mix(in srgb, var(--good, #22c55e) 14%, transparent); color: var(--good); }
.lim-pill.bad { background: color-mix(in srgb, var(--red, #fb414a) 16%, transparent); color: var(--bad); }
.lim-meta { padding-left: 14px; font-size: 12px; color: var(--subtle); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.lim-who .rename { display: flex; gap: 6px; align-items: center; }
.lim-who .rename .field { height: 28px; }
.lwins { display: grid; gap: 10px; min-width: 0; }
.lwin { display: grid; grid-template-columns: 58px minmax(60px, 1fr) 68px 104px; gap: 14px; align-items: center; font-size: 12px; }
.lwin-name { color: var(--muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.lwin .progress { height: 4px; }
.lwin .progress > span { background: hsl(var(--on) / .78); }
.lwin .progress.warn > span { background: var(--warn); }
.lwin .progress.bad > span { background: var(--red, #fb414a); }
.lwin-pct { white-space: nowrap; text-align: right; font-size: 13px; font-weight: 500; color: var(--text); font-variant-numeric: tabular-nums; }
.lwin-pct.bad { color: var(--bad); font-weight: 600; }
.lwin-foot { color: var(--subtle); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; font-variant-numeric: tabular-nums; }
.lnote { margin: 0; color: var(--muted); font-size: 13px; }
.lim-side { display: flex; flex-direction: column; align-items: flex-end; gap: 8px; text-align: right; min-width: 0; }
.lim-side .row-actions { flex-wrap: nowrap; align-items: center; }
.loutlook { font-size: 12px; color: var(--subtle); font-variant-numeric: tabular-nums; }
.loutlook:empty { display: none; }
.loutlook.warn { color: var(--warn-ink); }
.loutlook.bad { color: var(--bad); }
.loutlook.good { color: var(--good); }
.lim-row .btn.sm { height: 30px; padding: 0 14px; font-size: 12px; font-weight: 600; border-radius: 8px; }
.lim-row .btn.icon-only { width: 30px; padding: 0; }
.lim-row.waiting-row { grid-template-columns: minmax(0, 1fr) auto; }

.lim-singles .lim-group-head { align-items: baseline; }
.lim-tiles { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 12px; }
.lim-tile { display: grid; gap: 12px; padding: 18px 20px; overflow: visible; }
.lim-tile-head { display: flex; align-items: center; gap: 8px; min-height: 28px; }
.lim-tile-name { flex: 1; min-width: 0; display: flex; align-items: center; gap: 8px; }
.lim-tile-name .mark { width: 15px; height: 15px; color: hsl(var(--on) / .9); }
.lim-tile-name b { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.lim-tile-left { font-size: 12px; color: var(--muted); white-space: nowrap; }
.lim-tile .menu-anchor { position: relative; margin: -4px -8px -4px 0; }
.lim-tile .progress { height: 4px; }
.lim-tile .progress > span { background: hsl(var(--on) / .78); }
.lim-tile .progress.warn > span { background: var(--warn); }
.lim-tile .progress.bad > span { background: var(--red, #fb414a); }
.lim-tile-sub { font-size: 12px; color: var(--subtle); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.lim-tile .rename { display: flex; gap: 6px; flex: 1; }
.lim-tile .rename .field { height: 28px; }
.lim-foot { margin: 4px 2px 0; font-size: 12px; color: var(--subtle); }

@media (max-width: 1180px) {
  .lim-top { grid-template-columns: minmax(0, 1fr); }
  .lim-row { grid-template-columns: minmax(0, 1fr) auto; gap: 12px 18px; }
  .lim-row .lwins { grid-column: 1 / -1; grid-row: 2; }
  .lim-row .lim-side { grid-column: 2; grid-row: 1; }
}
@media (max-width: 820px) {
  .main:has(.lim-page) { padding: 16px; }
  .lim-figs { grid-template-columns: minmax(0, 1fr); gap: 12px; }
  .lim-fig { padding: 0; border-left: 0; }
  /* The reset time is a real figure, so it wraps under the bar instead of disappearing. */
  .lwin { grid-template-columns: 56px minmax(0, 1fr) 64px; gap: 2px 14px; }
  .lwin-foot { grid-column: 2 / -1; text-align: right; }
  .lim-group-head { flex-wrap: wrap; }
}
"""##
}
