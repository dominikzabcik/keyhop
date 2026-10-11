import Foundation

/// The window's markup: sidebar, content, status bar and overlays, with the script elements that load it.
extension DashboardPage {
    static let shell = ##"""
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
      <svg viewBox="0 0 24 24" aria-hidden="true"><g fill="currentColor"><rect x="2.5" y="2.5" width="6" height="19.5" rx="1.5"/><rect x="9.6" y="9.2" width="6" height="6" rx="1.5"/><rect x="16" y="1" width="6" height="6" rx="1.5"/><rect x="16" y="17" width="6" height="6" rx="1.5"/></g></svg>
      <b>Keyhop</b>
    </div>
    <button class="hop hop-side" type="button" data-action="palette" aria-keyshortcuts="Meta+K Control+K" aria-haspopup="dialog" aria-controls="palette"><svg class="icon" aria-hidden="true"><use href="#i-hop"/></svg><span>Hop</span><kbd id="hop-key" aria-hidden="true">⌘K</kbd></button>
    <nav class="nav" id="nav" aria-label="Sections">
      <a href="#overview" data-section="overview"><svg><use href="#i-overview"/></svg>Overview</a>
      <a href="#limits" data-section="limits"><svg><use href="#i-limits"/></svg>Limits<span class="nav-count" id="limits-count" hidden></span></a>
      <a href="#accounts" data-section="accounts"><svg><use href="#i-accounts"/></svg>Accounts</a>
      <a href="#usage" data-section="usage"><svg><use href="#i-usage"/></svg>Usage</a>
      <a href="#budgets" data-section="budgets"><svg><use href="#i-budgets"/></svg>Budgets</a>
      <a href="#plans" data-section="plans"><svg><use href="#i-plans"/></svg>Plans</a>
      <span class="nav-label" id="cloud-label" hidden>Cloud</span>
      <a href="#leaderboard" data-section="leaderboard" hidden><svg><use href="#i-leaderboard"/></svg>Leaderboard</a>
      <a href="#season" data-section="season" hidden><svg><use href="#i-season"/></svg>Season</a>
      <a href="#teams" data-section="teams" hidden><svg><use href="#i-teams"/></svg>Teams</a>
      <a href="#profile" data-section="profile" hidden><svg><use href="#i-profile"/></svg>Profile</a>
    </nav>
    <div class="side-label">Accounts</div>
    <div class="acct-tree" id="tree"></div>
    <div class="side-foot">
      <div class="pet-foot" id="pet-foot" hidden></div>
      <a class="foot-link" href="#settings" data-section="settings"><svg class="icon" aria-hidden="true"><use href="#i-settings"/></svg><span>Settings</span></a>
    </div>
  </aside>
  <div class="content" id="content">
    <div class="backdrop" id="backdrop" aria-hidden="true"></div>
    <canvas id="field" hidden aria-hidden="true"></canvas>
    <div id="veil" hidden aria-hidden="true"></div>
    <header class="topbar"><h1 id="title">Overview</h1><div class="top-actions"><div class="toolbar" id="toolbar"></div></div><div class="meter" id="top-meter" role="progressbar" aria-label="Keyhop is reading" aria-hidden="true"><span></span></div></header>
    <main class="main" id="main" tabindex="-1" aria-busy="true"><div class="page"><p class="lede busy" role="status"><span class="pulse" aria-hidden="true"><i></i><i></i><i></i></span>Reading your accounts…</p></div></main>
  </div>
  <footer class="statusbar">
    <span id="mode" hidden></span>
    <button type="button" id="status-needs" data-action="goto" data-section="limits" hidden></button>
    <span id="status-clear" hidden>Limits clear</span>
    <a id="status-outage" href="#" target="_blank" rel="noopener" hidden></a>
    <span class="status-grow"></span>
    <button type="button" id="status-today" data-action="goto" data-section="usage"></button>
    <button type="button" id="status-streak" data-action="goto" data-section="usage" hidden></button>
    <button type="button" id="status-theme" data-action="theme-toggle" title="Switch the field between night and day">Night</button>
    <button type="button" class="status-btn" id="refresh" data-action="refresh"><svg class="icon" aria-hidden="true"><use href="#i-refresh"/></svg><span id="read">Limits not read yet</span></button>
    <span class="meter" id="foot-meter" hidden><span></span></span>
  </footer>
</div>
<div class="tip" id="tip" hidden></div>
<div id="palette" hidden></div>
<div class="toast away" id="toast" role="status" aria-live="polite"></div>
<script>{{backdrop}}</script>
<script id="boot" type="application/json">{{boot}}</script>
<script>
"""##
}
