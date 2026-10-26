import Foundation

/// The demoted views (Usage, Insights, Community) in the 2.0 language: ink on warm charcoal,
/// hairline splits, color only where it means a state.
extension DashboardPage {
    static let stylesPages = ##"""
/* Chrome extras: the outage chip in the titlebar, and the boot skeleton's spacing. */
.top-chip { display: inline-flex; align-items: center; gap: 6px; height: 24px; padding: 0 9px; border-radius: 5px; font-size: 12px; text-decoration: none; white-space: nowrap; min-width: 0; overflow: hidden; text-overflow: ellipsis; }
.top-chip .mark { width: 12px; height: 12px; }
.top-chip.warn { color: var(--low); background: var(--low-wash); }
.top-chip.warn:hover { background: color-mix(in srgb, var(--low) 14%, transparent); }
.boot-skel .skel-card { display: grid; gap: 12px; padding: 20px 24px 24px; }

/* Page furniture shared by the demoted views. */
.page { max-width: 1480px; gap: 14px; }
.filter-row { display: flex; flex-wrap: wrap; gap: 8px; }
.chart-body { display: grid; gap: 14px; }
.table-wrap { overflow-x: auto; }
.card-body > .table { margin: 0 -16px -14px; width: calc(100% + 32px); }
.card-head .tabs { margin-left: auto; }
.table tr.me td { background: hsl(var(--on) / .035); }
.table tr.me td:first-child { box-shadow: inset 2px 0 0 var(--fg); }
.cell-name .mark { width: 15px; height: 15px; }
.grow { flex: 1; min-width: 0; }

/* The activity heatmap: one neutral ramp, never a hue. */
.heat rect.l0 { fill: hsl(var(--on) / .05); }
.heat rect.l1 { fill: hsl(var(--on) / .18); }
.heat rect.l2 { fill: hsl(var(--on) / .36); }
.heat rect.l3 { fill: hsl(var(--on) / .6); }
.heat rect.l4 { fill: hsl(var(--on) / .9); }
.heat text { fill: var(--fg3); font: 10.5px var(--mono); }
svg.heat { display: block; }
.scale .hcell { width: 10px; height: 10px; border-radius: 2px; display: inline-block; }
.hcell.l0 { background: hsl(var(--on) / .05); }
.hcell.l1 { background: hsl(var(--on) / .18); }
.hcell.l2 { background: hsl(var(--on) / .36); }
.hcell.l3 { background: hsl(var(--on) / .6); }
.hcell.l4 { background: hsl(var(--on) / .9); }

/* Usage: the total card leads, tools as tiles, the summary beside the chart. */
.usage-board { display: grid; grid-template-columns: minmax(280px, 34%) minmax(0, 1fr); gap: 14px; align-items: start; }
.usage-side, .usage-main { display: grid; gap: 14px; align-content: start; }
.usage-side svg.heat { max-width: 100%; height: auto; }
.total-card { padding: 20px 22px 22px; display: grid; gap: 14px; align-content: start; }
.total-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; min-height: 28px; color: var(--fg2); font-size: 13px; }
.total-title { display: grid; gap: 6px; }
.total-title h2 { margin: 0; font-size: 20px; line-height: 26px; font-weight: 600; letter-spacing: -.02em; color: var(--fg); }
.total-change { display: inline-flex; align-items: baseline; gap: 8px; font-size: 12.5px; }
.total-figure { font: 600 clamp(32px, 4vw, 44px)/1.05 var(--mono); letter-spacing: -.02em; overflow-wrap: anywhere; font-variant-numeric: tabular-nums; }
.total-facts { margin: -4px 0 0; color: var(--fg2); font-size: 13px; }
.share-bar { display: flex; gap: 3px; height: 8px; margin-top: 4px; }
.share-bar span { min-width: 4px; border-radius: 99px; flex-basis: 0; transition: flex-grow .7s cubic-bezier(.2, .8, .2, 1); }
.progress > span, .ranked-track span, .mix-bar span { transition: width .7s cubic-bezier(.2, .8, .2, 1); }
.tile-mid { display: flex; align-items: flex-end; justify-content: space-between; gap: 10px; min-width: 0; }
.tiles { display: grid; grid-template-columns: repeat(auto-fill, minmax(148px, 1fr)); gap: 8px; }
.tile { display: grid; gap: 6px; align-content: start; padding: 11px 12px 12px; border-radius: 5px; border: 1px solid var(--line); background: hsl(var(--on) / .02); color: var(--fg); text-align: left; font: inherit; min-width: 0; }
button.tile { cursor: pointer; transition: background .15s ease-out; }
button.tile:hover { background: hsl(var(--on) / .045); }
.tile-name { display: flex; align-items: center; gap: 8px; min-width: 0; font-size: 12.5px; color: var(--fg2); }
.tile-name > span:last-child { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.tile-name .mark { width: 14px; height: 14px; fill: var(--fg); }
.tile-share { font: 600 17px/1.2 var(--mono); font-variant-numeric: tabular-nums; }
.tile-foot { display: flex; align-items: center; gap: 6px; color: var(--fg3); font-size: 11.5px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.tile-foot .swatch { width: 6px; height: 6px; border-radius: 50%; }
.summary-card { padding: 16px; display: grid; gap: 16px; align-content: start; }
.chips { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; }
.chip { display: grid; gap: 2px; padding: 10px 12px; border-radius: 5px; background: hsl(var(--on) / .03); }
.chip b { font: 600 16px/1.3 var(--mono); font-variant-numeric: tabular-nums; }
.chip span { color: var(--fg3); font-size: 11.5px; }
.ranked { list-style: none; margin: 0; padding: 0; display: grid; gap: 12px; }
.ranked li { display: grid; grid-template-columns: 18px minmax(0, 1fr) auto; column-gap: 8px; row-gap: 6px; align-items: center; }
.ranked .place { color: var(--fg3); font: 11.5px var(--mono); text-align: center; }
.ranked-name { display: flex; align-items: center; gap: 8px; min-width: 0; }
.ranked-name .mark { width: 14px; height: 14px; fill: var(--fg2); }
.ranked-name .mono { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.ranked-share { font: 12px var(--mono); color: var(--fg); }
.ranked-value { margin-left: auto; font: 11.5px var(--mono); }
.ranked-track { grid-column: 2 / -1; height: 3px; border-radius: 99px; background: var(--g3); overflow: hidden; }
.ranked-track span { display: block; height: 100%; border-radius: inherit; background: hsl(var(--on) / .55); }
.ranked li:first-child .ranked-track span { background: hsl(var(--on) / .9); }
.summary-foot { display: flex; justify-content: space-between; gap: 12px; margin-top: auto; padding-top: 12px; border-top: 1px solid var(--line); color: var(--fg3); font-size: 12px; }

/* Coach: each finding is a row with its mark; state color only on the glyph. */
.coach-findings { display: grid; padding: 4px 16px 10px; }
.coach-finding { display: flex; align-items: flex-start; gap: 12px; margin: 0; padding: 12px 4px; font-size: 13px; }
.coach-finding.fine, .coach-finding.quiet { color: var(--fg2); }
.coach-finding + .coach-finding { border-top: 1px solid var(--line); }
.coach-finding p { margin: 3px 0 0; flex: 1; min-width: 0; }
.arow-glyph { flex: none; width: 26px; height: 26px; border-radius: 5px; display: grid; place-items: center; background: hsl(var(--on) / .06); color: var(--fg2); }
.arow-glyph .icon { width: 13px; height: 13px; }
.coach-finding.cache .arow-glyph, .coach-finding.premium .arow-glyph, .coach-finding.session .arow-glyph { background: var(--low-wash); color: var(--low); }
.coach-finding.fine .arow-glyph, .coach-finding.quiet .arow-glyph { color: var(--ok); background: var(--ok-wash); }
.coach-deltas { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 0; }
.coach-deltas.card-body { padding: 6px 0 4px; }
.coach-delta { display: grid; gap: 4px; padding: 14px 20px 16px; font-size: 12px; }
.coach-delta + .coach-delta { border-left: 1px solid var(--line); }
.coach-delta b { font: 600 19px/1.2 var(--mono); font-variant-numeric: tabular-nums; }
.coach-delta .subtle { color: var(--fg2); }

/* Plans: the month's figures lead; money reads as a figure, not a color. */
.plans-head { display: flex; flex-wrap: wrap; gap: 12px 44px; padding: 20px 22px; margin-bottom: 14px; }
.plans-fig { display: grid; gap: 2px; }
.plans-fig b { font: 600 22px/26px var(--mono); font-variant-numeric: tabular-nums; }
.plans-fig span { font-size: 12.5px; color: var(--fg2); }
.plans-table td { vertical-align: middle; }
.plans-table th { white-space: nowrap; }
.plan-peak { display: grid; grid-template-columns: minmax(60px, 120px) auto; gap: 10px; align-items: center; }
.plan-peak .progress { height: 4px; }

/* Budgets. */
.budget-row .progress { height: 6px; }
.budget-row .progress:not(.bad):not(.warn) > span { background: var(--fg); }
.budget-top b { font-size: 14px; }
.budget-top .mono { font: 600 13px var(--mono); }
.form label { color: var(--fg2); font-size: 12px; font-weight: 500; }
.form > .btn, .form .row-actions { justify-self: start; }
.form .btn:not(.sm) { width: auto; }

/* Community: podium, board, season, team day. */
.stat-strip { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); }
.stat-strip .stat + .stat { border-left: 1px solid var(--line); }
.podium { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 14px; }
.podium-card { padding: 16px; display: grid; gap: 12px; }
.podium-card .place { color: var(--fg3); font-size: 12px; }
.podium-card.you { border-color: var(--line-strong); }
.podium-value { font: 600 21px/1.2 var(--mono); font-variant-numeric: tabular-nums; }
.podium .mix-bar, .table .mix-bar { margin: 0; height: 4px; border-radius: 2px; }
.who .avatar { background: hsl(var(--on) / .08); color: var(--fg); border-radius: 5px; }
.tier { display: inline-flex; align-items: center; gap: 8px; font-weight: 600; color: var(--tier); white-space: nowrap; }
.tier svg { width: 23px; height: 18px; fill: currentColor; flex: none; }
.tier.sm { gap: 6px; font-size: 12.5px; }
.tier.sm svg { width: 15px; height: 12px; }
.tier-bronze { --tier: hsl(26 20% 58%); }
.tier-silver { --tier: hsl(0 0% 68%); }
.tier-gold { --tier: hsl(42 26% 66%); }
.tier-platinum { --tier: hsl(190 12% 72%); }
.tier-diamond { --tier: hsl(205 20% 80%); }
.tier-master { --tier: var(--fg); }
.season-row { display: flex; align-items: center; gap: 16px; padding: 16px 18px; flex-wrap: wrap; }
.season-row h2 { margin: 0; font-size: 18px; line-height: 24px; font-weight: 600; letter-spacing: -.02em; }
.season-row p { margin: 3px 0 0; color: var(--fg2); }
.season-row .grow { min-width: 200px; }
.season-row .tabs { justify-self: start; }
.season-tier .tier { font-size: 18px; gap: 12px; }
.season-tier .tier svg { width: 36px; height: 29px; }
.quest-row { display: grid; grid-template-columns: minmax(0, 1fr) 128px; gap: 4px 18px; align-items: center; padding: 12px 16px; }
.quest-row + .quest-row { border-top: 1px solid var(--line); }
.quest-row p { margin: 2px 0 0; color: var(--fg2); font-size: 12.5px; }
.quest-track { height: 4px; border-radius: 99px; background: var(--g3); overflow: hidden; }
.quest-track span { display: block; height: 100%; border-radius: inherit; background: var(--fg); }
.quest-row.done .quest-track span { background: var(--ok); }
.quest-state { margin-top: 5px; font-size: 12px; color: var(--fg3); }
.quest-row.done .quest-state { color: var(--ok); }
.card-body .btn.claim-kick { width: auto; }
.day-sum { display: flex; flex-wrap: wrap; gap: 8px 18px; margin: 0 0 14px; color: var(--fg2); font-size: 13px; }
.day-sum b { color: var(--fg); font-variant-numeric: tabular-nums; font-weight: 600; }
.day-figures { display: flex; gap: 16px; }
.day-figures div { text-align: right; }
.day-figures b { display: block; font-variant-numeric: tabular-nums; font-weight: 600; }
/* The lines figure stacks over its label like the other two, instead of riding beside it. */
.day-figures .diff { display: block; font-variant-numeric: tabular-nums; font-weight: 600; }
.day-figures small, .task-meta, .day-note { color: var(--fg3); font-size: 12px; }
.day-person .card-head { padding-bottom: 12px; }
.task { padding: 12px 16px; border-top: 1px solid var(--line); }
.task h3 { margin: 0; font-size: 13.5px; font-weight: 600; }
.task-meta { display: flex; flex-wrap: wrap; gap: 4px 12px; margin-top: 4px; }
.tasks { list-style: none; margin: 0; padding: 0; }
.commits { list-style: none; margin: 8px 0 0; padding: 0; display: grid; gap: 4px; }
.commit { display: flex; gap: 8px; align-items: baseline; color: var(--fg2); font-size: 12.5px; }
.sha { font-family: var(--mono); font-size: 11.5px; color: var(--fg3); }
.day-nav { display: flex; align-items: center; gap: 6px; }
.day-nav .now { padding: 0 8px; font-weight: 600; }
.team-digest { margin: 14px 0; padding-top: 14px; border-top: 1px solid var(--line); display: grid; gap: 6px; }
.team-digest b { font-weight: 600; }
.team-forms { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 4px 24px; border-top: 1px solid var(--line); padding-top: 16px; }
.team-forms .form { padding: 0; align-content: start; }
.team-forms > p { grid-column: 1 / -1; margin-top: 6px; }

@media (max-width: 1180px) {
  .usage-board { grid-template-columns: 1fr; }
  .coach-delta + .coach-delta { border-left: 0; border-top: 1px solid var(--line); }
}
@media (max-width: 900px) {
  .podium, .team-forms { grid-template-columns: 1fr; }
  .stat-strip { grid-template-columns: 1fr; }
  .stat-strip .stat + .stat { border-left: 0; border-top: 1px solid var(--line); }
}
"""##
}
