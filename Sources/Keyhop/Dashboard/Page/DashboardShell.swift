import Foundation

/// The window's markup: title bar, the view bar for demoted views, the work surface and overlays.
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
  <header class="titlebar">
    <span class="app"><span class="kmark" aria-hidden="true">K</span>Keyhop</span>
    <span id="mode" hidden></span>
    <a class="top-chip warn" id="status-outage" href="#" target="_blank" rel="noopener" hidden></a>
    <span class="right">
      <span class="readtime" id="readtime"></span>
      <button type="button" class="iconbtn" id="refresh" data-action="refresh" aria-label="Read limits and usage now"><svg class="icon" aria-hidden="true"><use href="#i-refresh"/></svg></button>
      <button type="button" class="iconbtn" id="gear" data-action="goto" data-section="settings" aria-label="Settings"><svg class="icon" aria-hidden="true"><use href="#i-settings"/></svg></button>
    </span>
    <div class="meter" id="top-meter" role="progressbar" aria-label="Keyhop is reading" aria-hidden="true"><span></span></div>
  </header>
  <div class="viewbar" id="viewbar" hidden>
    <button type="button" class="iconbtn back" data-action="goto" data-section="home" aria-label="Back to limits"><svg class="icon" aria-hidden="true"><use href="#i-chev"/></svg></button>
    <h1 id="title">Keyhop</h1>
    <span id="viewtabs"></span>
    <div class="toolbar" id="toolbar"></div>
  </div>
  <main class="main" id="main" tabindex="-1" aria-busy="true"><div class="core boot-skel" role="status" aria-label="Reading your logins"><div class="skel-card" style="border:0"><span class="skel" style="width:60%;height:15px"></span><span class="skel" style="width:100%;height:47px"></span><span class="skel" style="width:100%;height:47px"></span><span class="skel" style="width:100%;height:47px"></span><span class="skel" style="width:40%;height:34px"></span></div></div></main>
</div>
<div class="tip" id="tip" hidden></div>
<div class="toast away" id="toast" role="status" aria-live="polite"></div>
<script id="boot" type="application/json">{{boot}}</script>
<script>
"""##
}
