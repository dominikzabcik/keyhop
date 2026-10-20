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
      <span class="brand-tile" aria-hidden="true"><svg viewBox="0 0 14 14" shape-rendering="crispEdges"><rect x="2" y="2" width="3" height="10" fill="currentColor"/><rect x="6" y="5" width="3" height="3" fill="currentColor"/><rect x="9" y="2" width="3" height="3" fill="currentColor"/><rect x="9" y="9" width="3" height="3" fill="currentColor"/></svg></span>
      <span class="brand-copy"><b>Keyhop</b><small id="brand-line">Reading your logins</small></span>
      <span class="badge channel-badge" id="channel-badge" hidden>Beta</span>
    </div>
    <button class="hop hop-side" type="button" data-action="palette" aria-keyshortcuts="Meta+K Control+K" aria-haspopup="dialog" aria-controls="palette"><svg class="icon" aria-hidden="true"><use href="#i-search"/></svg><span>Hop to a login…</span><kbd id="hop-key" aria-hidden="true">⌘K</kbd></button>
    <div class="side-scroll">
      <div class="nav-label">Platform</div>
      <nav class="nav" id="nav" aria-label="Sections">
        <a href="#overview" data-section="overview" data-group="home"><svg><use href="#i-home"/></svg><span class="nav-name">Home</span></a>
        <a href="#limits" data-section="limits" data-group="limits"><svg><use href="#i-gauge"/></svg><span class="nav-name">Limits</span><span class="nav-count" id="limits-count" hidden></span></a>
        <a href="#usage" data-section="usage" data-group="usage"><svg><use href="#i-usage"/></svg><span class="nav-name">Usage</span></a>
        <a href="#coach" data-section="coach" data-group="insights"><svg><use href="#i-bulb"/></svg><span class="nav-name">Insights</span><svg class="nav-chev" aria-hidden="true"><use href="#i-chev"/></svg></a>
        <a href="#leaderboard" data-section="leaderboard" data-group="community" hidden><svg><use href="#i-people"/></svg><span class="nav-name">Community</span><svg class="nav-chev" aria-hidden="true"><use href="#i-chev"/></svg></a>
      </nav>
      <div class="side-label" id="tree-label"><span>Limits</span><span class="side-live" id="side-live" hidden></span></div>
      <div class="acct-tree" id="tree"></div>
    </div>
    <div class="side-foot">
      <a class="side-account" href="#settings" data-section="settings"><span class="avatar" id="side-avatar" aria-hidden="true">K</span><span class="side-account-copy"><b id="side-name">Settings</b><small id="side-sub">This computer</small></span><svg class="icon" aria-hidden="true"><use href="#i-settings"/></svg></a>
    </div>
  </aside>
  <div class="content" id="content">
    <div class="backdrop" id="backdrop" aria-hidden="true"></div>
    <div class="hero-art" id="hero-art" hidden aria-hidden="true"><canvas id="field"></canvas><div class="hero-scene" id="hero-scene"></div></div>
    <header class="topbar"><div class="top-title"><h1 id="title">Home</h1><div class="toolbar" id="toolbar"></div></div><div class="top-actions"><span class="top-read" id="top-read"></span><button type="button" class="icon-btn" id="refresh" data-action="refresh" aria-label="Read limits and usage now"><svg class="icon" aria-hidden="true"><use href="#i-refresh"/></svg></button></div><div class="meter" id="top-meter" role="progressbar" aria-label="Keyhop is reading" aria-hidden="true"><span></span></div></header>
    <main class="main" id="main" tabindex="-1" aria-busy="true"><div class="home-cols boot-skel" role="status" aria-label="Reading your accounts"><div class="home-col"><section class="card htotal skel-card"><span class="skel" style="width:110px;height:10px"></span><span class="skel" style="width:190px;height:22px"></span><span class="skel" style="width:240px;height:44px"></span></section><section class="card htrend skel-card"></section></div><div class="home-col"><section class="card skel-card" style="height:300px"></section><section class="card skel-card" style="height:160px"></section></div></div></main>
  </div>
  <footer class="statusbar">
    <span id="mode" hidden></span>
    <span class="chip live" id="status-live" hidden><i aria-hidden="true"></i>Live</span>
    <button type="button" class="chip bad" id="status-needs" data-action="goto" data-section="limits" hidden></button>
    <span class="status-quiet" id="status-clear" hidden>Limits clear</span>
    <a class="chip warn" id="status-outage" href="#" target="_blank" rel="noopener" hidden></a>
    <span class="status-grow"></span>
    <button type="button" class="status-fig" id="status-theme" data-action="theme-toggle" title="Switch the field between night and day">Night</button>
    <button type="button" class="status-btn" id="status-read" data-action="refresh"><span id="read">Limits not read yet</span></button>
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
