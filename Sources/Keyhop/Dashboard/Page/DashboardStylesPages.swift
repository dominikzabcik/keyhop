import Foundation

/// Usage, Insights, Community and Settings in the Coss Blue card language.
extension DashboardPage {
    static let stylesPages = ##"""
/* Pages: the same cards as Home. Figures are big and sans, splits are hairlines, and a page's
   leading bar is the one blue. */
.page { max-width: 1480px; gap: 18px; }
.main:has(.page) { padding: 20px 24px 28px; }
.page .lab { display: block; }
.filter-row { display: flex; flex-wrap: wrap; gap: 8px; }

/* Tables: mono uppercase headers, hairlines, tabular figures. */
.table th { padding: 12px 24px; font: 500 10.5px var(--mono); letter-spacing: .12em; text-transform: uppercase; color: var(--subtle); border-bottom: 1px solid hsl(var(--on) / .08); }
.table td { padding: 12px 24px; border-bottom: 1px solid hsl(var(--on) / .06); }
.table.data th, .table.data td { padding-left: 16px; padding-right: 16px; }
.table td.mono { font-size: 12px; color: var(--text); }
.table td.mono.subtle { color: var(--subtle); }
.table tbody tr:hover td { background: hsl(var(--on) / .025); }
.table tr.me td { background: color-mix(in srgb, var(--primary) 7%, transparent); }
.table tr.me td:first-child { box-shadow: inset 2px 0 0 var(--primary); }
.card > .table:first-child thead th { padding-top: 18px; }
.cell-name .mark { width: 15px; height: 15px; }
.table-more { border-top-color: hsl(var(--on) / .06); }

/* Stat strips: figures side by side, split by hairlines, no box inside the card. */
.stat-strip { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); }
.stat-strip .stat { padding: 22px 24px 22px; }
.stat-strip .stat + .stat { border-left: 1px solid hsl(var(--on) / .08); }
.stat .label { font: 500 11px var(--mono); letter-spacing: .14em; text-transform: uppercase; color: var(--muted); }
.stat .value { margin-top: 10px; font-size: 30px; font-weight: 500; letter-spacing: -.03em; line-height: 1.1; }
.stat .foot { margin-top: 6px; color: var(--muted); }
.facts { border-top: 1px solid hsl(var(--on) / .08); }
.facts div { padding: 16px 24px 18px; }
.facts div + div { border-left-color: hsl(var(--on) / .08); }
.facts b { font-size: 22px; font-weight: 500; letter-spacing: -.02em; }
.facts span { color: var(--muted); }

/* Usage: the total reads like Home's, the rail's figures sit in a strip, and the heatmap is blue. */
.usage-board { grid-template-columns: minmax(300px, 34%) minmax(0, 1fr); gap: 18px; }
.usage-side, .usage-main { gap: 18px; }
.total-card { padding: 24px 26px 26px; gap: 18px; }
.total-head { align-items: baseline; color: var(--muted); }
.total-title { display: grid; gap: 6px; }
.total-title h2 { margin: 0; font-size: 26px; line-height: 30px; font-weight: 500; letter-spacing: -.02em; color: var(--text); }
.total-change { font-size: 12px; }
.total-figure { font-size: clamp(40px, 4.6vw, 60px); line-height: .95; font-weight: 500; letter-spacing: -.04em; }
.total-facts { margin: 0; font-size: 12px; }
.share-bar { gap: 2px; height: 8px; border-radius: 4px; overflow: hidden; margin-top: 0; }
.share-bar span { border-radius: 0; min-width: 2px; }
.tiles { grid-template-columns: repeat(auto-fit, minmax(118px, 1fr)); gap: 0; padding-top: 18px; border-top: 1px solid hsl(var(--on) / .08); row-gap: 18px; }
.tile { padding: 0 14px; border: 0; border-left: 1px solid hsl(var(--on) / .08); border-radius: 0; background: transparent; gap: 6px; }
.tile:first-child { padding-left: 0; border-left: 0; }
button.tile:hover { background: transparent; border-color: hsl(var(--on) / .08); }
button.tile:hover .tile-name { color: var(--text); }
.tile-name { font-size: 12px; font-weight: 500; }
.tile-name .mark { width: 13px; height: 13px; fill: currentColor; }
.tile-share { font-size: 18px; line-height: 22px; font-weight: 500; letter-spacing: -.01em; }
.tile-foot { font-size: 11px; line-height: 14px; white-space: normal; align-items: baseline; }
.tile-foot .swatch { transform: translateY(-1px); }
.spark { width: 56px; height: 20px; }
.summary-card { padding: 0; gap: 0; }
.summary-card .chips { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 0; border-bottom: 1px solid hsl(var(--on) / .08); }
.summary-card .chip { padding: 18px 24px 16px; border-radius: 0; background: transparent; gap: 4px; }
.summary-card .chip:nth-child(even) { border-left: 1px solid hsl(var(--on) / .08); }
.summary-card .chip:nth-child(n + 3) { border-top: 1px solid hsl(var(--on) / .08); }
.summary-card .chip b { font-size: 22px; font-weight: 500; letter-spacing: -.02em; }
.summary-card .chip span { color: var(--muted); font-size: 12px; }
.summary-card .ranked { padding: 18px 24px 4px; gap: 14px; }
.summary-card .summary-foot { margin: 14px 0 0; padding: 14px 24px 18px; border-top-color: hsl(var(--on) / .08); color: var(--muted); }
.ranked-share { font: 600 12px var(--sans); }
.ranked-track { height: 4px; }
.ranked li:first-child .ranked-track span { background: var(--primary); }
.ranked-name .mark { fill: currentColor; color: hsl(var(--on) / .8); }
.ranked-name .mono { font: 450 13px var(--sans); }
.heat rect.l0 { fill: hsl(var(--on) / .06); }
.heat rect.l1 { fill: #1e3a5f; }
.heat rect.l2 { fill: #2e5c99; }
.heat rect.l3 { fill: #4d84c8; }
.heat rect.l4 { fill: #93c5fd; }
:root[data-theme="day"] .heat rect.l1 { fill: #dbeafe; }
:root[data-theme="day"] .heat rect.l2 { fill: #93c5fd; }
:root[data-theme="day"] .heat rect.l3 { fill: #3b82f6; }
:root[data-theme="day"] .heat rect.l4 { fill: #1d4ed8; }
.scale { gap: 4px; font-size: 11px; font-family: var(--sans); letter-spacing: 0; text-transform: none; }
.scale .hcell { width: 10px; height: 10px; border-radius: 2px; display: inline-block; }
.chart-body { padding-top: 10px; }
.mix-bar { height: 8px; border-radius: 4px; }
.card-body > .table { margin: 0 -24px -20px !important; width: calc(100% + 48px) !important; }
.card-head .tabs { margin-left: auto; }

/* Coach: each finding is a row with its mark, the figures behind them a strip. */
.coach-findings { display: grid; padding: 4px 20px 12px; }
.coach-finding { display: flex; align-items: flex-start; gap: 12px; margin: 0; padding: 12px 4px; font-size: 13px; }
.coach-finding.fine, .coach-finding.quiet { color: var(--muted); }
.coach-finding + .coach-finding { border-top: 1px solid hsl(var(--on) / .07); }
.coach-finding p { margin: 3px 0 0; flex: 1; min-width: 0; }
.coach-finding.cache .arow-glyph, .coach-finding.premium .arow-glyph, .coach-finding.session .arow-glyph { background: color-mix(in srgb, var(--warn) 16%, transparent); color: var(--warn-ink); }
.coach-finding.fine .arow-glyph, .coach-finding.quiet .arow-glyph { color: var(--good); background: color-mix(in srgb, var(--good) 14%, transparent); }
.coach-deltas { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 0; }
.coach-deltas.card-body { padding: 6px 0 4px; }
.coach-delta { display: grid; gap: 4px; padding: 14px 24px 16px; font-size: 12px; }
.coach-delta + .coach-delta { border-left: 1px solid hsl(var(--on) / .08); }
.coach-delta b { font-size: 24px; font-weight: 500; letter-spacing: -.025em; }
.coach-delta .subtle { color: var(--muted); }

/* Plans: the price against the month, money in green and the value bar in blue. */

/* Budgets: the spend line is the one blue; the budget rows are hairline rows. */
.split, .split.wide-left { gap: 18px; }
.budget-row .progress { height: 6px; }
.budget-row .progress:not(.bad):not(.warn) > span { background: var(--primary); }
.budget-top b { font-size: 14px; }
.budget-top .mono { font: 600 13px var(--sans); }
.budget-top .mono .subtle { font-weight: 450; }
.form { padding: 10px 24px 22px; gap: 16px; }
.form label { color: var(--muted); font-size: 12px; font-weight: 500; }
.form > .btn, .form .row-actions { justify-self: start; }
.form .btn:not(.sm) { width: auto; }

.team-forms { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 4px 24px; border-top: 1px solid hsl(var(--on) / .07); padding-top: 18px; }
.team-forms .form { padding: 0; align-content: start; }
.team-forms > p { grid-column: 1 / -1; margin-top: 6px; }
.tiles { grid-template-columns: none; grid-auto-flow: column; grid-auto-columns: minmax(0, 1fr); }

/* Community: a stat strip, three podium cards, then the board; the season leads with its tier. */
.podium { gap: 18px; }
.podium-card { padding: 20px 24px 22px; gap: 14px; }
.podium-card.you { border-color: color-mix(in srgb, var(--primary) 45%, transparent); }
.podium-card .place { font: 500 11px var(--mono); letter-spacing: .14em; color: var(--muted); }
.podium-value { font-size: 28px; font-weight: 500; letter-spacing: -.03em; }
.podium .mix-bar, .table .mix-bar { height: 4px; border-radius: 2px; }
.who .avatar { background: hsl(var(--on) / .08); color: var(--text); border-radius: 7px; }
.season-row { display: grid; grid-template-columns: minmax(0, 1fr) auto; align-items: center; gap: 14px 24px; padding: 24px 26px; }
.season-row .grow { display: grid; gap: 6px; min-width: 0; }
.season-row h2 { margin: 0; font-size: 26px; line-height: 30px; font-weight: 500; letter-spacing: -.02em; }
.season-row p { margin: 0; color: var(--muted); }
.season-row .tabs { justify-self: start; margin-top: 8px; }
.season-tier .tier { font-size: 20px; gap: 12px; }
.season-tier .tier svg { width: 40px; height: 32px; }
.quest-row { padding: 14px 24px; gap: 4px 24px; grid-template-columns: minmax(0, 1fr) 160px; }
.quest-row + .quest-row { border-top-color: hsl(var(--on) / .07); }
.quest-track { height: 4px; }
.quest-track span { background: var(--primary); }
.quest-row.done .quest-track span { background: var(--good); }
.quest-state { color: var(--muted); }
.card-body .btn.claim-kick { width: auto; }
.btn.claim-kick { height: 36px; padding: 0 16px; border-radius: 8px; font-size: 13px; font-weight: 600; }
.pet-card { padding: 16px 24px 16px 14px; gap: 8px 24px; }
.pet-card .pet { width: 104px; }
.pet-card h2 { font-size: 22px; font-weight: 500; letter-spacing: -.02em; }
.pet-card p { font-size: 13px; }
.day-sum { margin: 0; gap: 8px 22px; font-size: 13px; }
.day-sum b { font-size: 15px; font-weight: 600; }
.day-person .card-head { padding-bottom: 12px; }
.day-person .card-head h2 { font: 600 14px var(--sans); letter-spacing: -.01em; text-transform: none; color: var(--text); }
.day-figures b { font-size: 16px; font-weight: 500; }
.task { padding: 12px 24px; border-top-color: hsl(var(--on) / .07); }
.tasks { list-style: none; margin: 0; padding: 0; }

/* Settings: the panes as a quiet list beside the content. */
.settings-shell { grid-template-columns: 196px minmax(0, 1fr); gap: 18px; }
.settings-nav { padding: 6px; }
.settings-nav button { height: 34px; font-size: 13px; }
.settings-nav button[aria-current="page"] { color: var(--text); font-weight: 560; background: hsl(var(--on) / .07); }
.settings-intro { padding: 4px 2px 0; }
.settings-intro h2 { font-size: 22px; line-height: 28px; font-weight: 500; letter-spacing: -.02em; }
.settings-intro p { font-size: 13px; }
.setting-row b { font-weight: 600; }
.setting-row p { font-size: 12.5px; }
.kv { grid-template-columns: 170px minmax(0, 1fr); }
.kv > span:first-child { font: 500 11px var(--mono); letter-spacing: .12em; text-transform: uppercase; }
.outbound { border-top-color: hsl(var(--on) / .07); }

@media (max-width: 1180px) {
  .stat-strip { grid-template-columns: 1fr; }
  .stat-strip .stat + .stat { border-left: 0; border-top: 1px solid hsl(var(--on) / .08); }
  .coach-delta + .coach-delta { border-left: 0; }
}
"""##
}
