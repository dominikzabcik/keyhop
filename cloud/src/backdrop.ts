// Switchr's backdrop: illustrated scenes behind the page. The same script runs in the app's
// dashboard (Sources/Switchr/Dashboard/Backdrop.swift), and a Swift test keeps the two copies equal.
export const BACKDROP_SCRIPT = String.raw`/* backdrop:start */
(function () {
  "use strict";
  if (window.SwitchrBackdrop) return;

  // Every moving part animates only transform and opacity, which the browser hands to the GPU, so
  // the scenes stay smooth and cost next to nothing. Nothing on the page depends on them.
  var CSS = [
    ".bd { container-type: size; }",
    ".bd-scene { position: absolute; inset: 0; overflow: hidden; }",
    ".bd-layer { position: absolute; inset: 0; }",
    ".bd-veil { position: absolute; inset: 0; background: linear-gradient(to bottom, rgba(23,23,23,.1) 0%, rgba(23,23,23,.35) 45%, rgba(23,23,23,.72) 80%, rgba(23,23,23,.86) 100%); }",

    ".bd-leaves { background: radial-gradient(130% 90% at 75% 0%, #231b15 0%, #181513 50%, #141414 100%); }",
    ".bd-leaf, .bd-fall { position: absolute; width: 0; height: 0; transform-origin: 0 0; will-change: transform; }",
    ".bd-leaf svg, .bd-fall svg { position: absolute; left: 0; top: 0; display: block; transform: translate(-50%, -84%); }",
    ".bd-leaf { animation: bd-sway 12s ease-in-out infinite alternate; }",
    "@keyframes bd-sway { from { transform: rotate(calc(var(--r) - var(--sway))); } to { transform: rotate(calc(var(--r) + var(--sway))); } }",
    ".bd-fall { top: 0; opacity: 0; animation: bd-fall 30s linear infinite; }",
    "@keyframes bd-fall {",
    "  0% { transform: translate(0, -12cqh) rotate(0deg); opacity: 0; }",
    "  10% { opacity: var(--o); }",
    "  30% { transform: translate(60px, 26cqh) rotate(110deg); }",
    "  55% { transform: translate(-40px, 58cqh) rotate(200deg); }",
    "  80% { transform: translate(70px, 90cqh) rotate(290deg); }",
    "  92% { opacity: var(--o); }",
    "  100% { transform: translate(20px, 115cqh) rotate(360deg); opacity: 0; }",
    "}",
    ".bd-mote { position: absolute; width: 3px; height: 3px; border-radius: 50%; background: #d8b27a; opacity: 0; will-change: transform, opacity; animation: bd-mote 20s linear infinite; }",
    "@keyframes bd-mote { 0% { transform: translate(0, 0); opacity: 0; } 15% { opacity: .55; } 85% { opacity: .35; } 100% { transform: translate(24px, -34cqh); opacity: 0; } }",

    ".bd-dunes { background: linear-gradient(to bottom, #0b0b0f 0%, #131110 45%, #1c1511 58%, #141414 100%); }",
    ".bd-world, .bd-limb { position: absolute; left: 50%; top: 36cqh; width: 180cqw; height: 180cqw; margin-left: -90cqw; border-radius: 50%; }",
    ".bd-world { overflow: hidden; background: radial-gradient(circle at 50% 2%, #d9ab79 0%, #ad7f52 3%, #74513a 9%, #3a291d 19%, #171210 36%); }",
    ".bd-sand { position: absolute; left: 0; top: 0; width: 200%; height: 24%; opacity: .32; will-change: transform; animation: bd-drift 150s linear infinite;",
    "  background-image: url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='420' height='120'%3E%3Cpath d='M0 70 Q52 40 105 62 T210 60 T315 58 T420 70' fill='none' stroke='%23f0caa0' stroke-opacity='.6' stroke-width='1.4'/%3E%3Cpath d='M0 102 Q70 78 140 96 T280 94 T420 102' fill='none' stroke='%23f0caa0' stroke-opacity='.4' stroke-width='1.2'/%3E%3C/svg%3E\"); background-size: 420px 120px; }",
    ".bd-sand-2 { top: 2%; opacity: .2; background-size: 260px 74px; animation-duration: 95s; }",
    "@keyframes bd-drift { from { transform: translateX(0); } to { transform: translateX(-50%); } }",
    ".bd-limb { box-shadow: 0 -1px 0 0 rgba(255, 222, 184, .38), 0 -22px 70px -6px rgba(255, 176, 112, .16); }",
    ".bd-star { position: absolute; width: 2px; height: 2px; border-radius: 50%; background: #f2eee8; opacity: .2; will-change: opacity; animation: bd-twinkle 5s ease-in-out infinite; }",
    "@keyframes bd-twinkle { 0%, 100% { opacity: .12; } 50% { opacity: .8; } }",

    ".bd-orbit-scene { background: radial-gradient(140% 100% at 80% 0%, #17161d 0%, #131316 55%, #141414 100%); }",
    ".bd-orbit { position: absolute; right: 9cqw; top: 7cqh; width: min(34cqw, 460px); aspect-ratio: 1; will-change: transform; animation: bd-float 18s ease-in-out infinite alternate; }",
    "@keyframes bd-float { from { transform: translateY(0); } to { transform: translateY(16px); } }",
    ".bd-tilt { position: absolute; inset: 0; transform: rotate(-18deg); }",
    ".bd-globe { position: absolute; inset: 0; border-radius: 50%; overflow: hidden; background: #3d3a45; }",
    ".bd-bands { position: absolute; top: -10%; bottom: -10%; left: 0; width: 300%; will-change: transform; animation: bd-drift 90s linear infinite;",
    "  background: repeating-linear-gradient(90deg, transparent 0 1px), repeating-linear-gradient(0deg, #6f6679 0 7%, #4b4556 7% 12%, #8c8187 12% 15%, #3f3a48 15% 23%, #a69489 23% 25%, #58505f 25% 33%); }",
    ".bd-shade { position: absolute; inset: 0; border-radius: 50%; background: radial-gradient(circle at 68% 26%, rgba(255,238,216,.4) 0%, rgba(255,238,216,0) 40%), radial-gradient(circle at 26% 76%, rgba(10,10,14,.94) 18%, rgba(10,10,14,0) 64%); }",
    ".bd-ring { position: absolute; left: -46%; right: -46%; top: 42%; height: 16%; border-radius: 50%; border: 2px solid rgba(218, 204, 184, .5); box-shadow: 0 0 0 7px rgba(218,204,184,.07), inset 0 0 0 6px rgba(218,204,184,.1); }",
    ".bd-ring-back { clip-path: inset(0 0 50% 0); }",
    ".bd-ring-front { clip-path: inset(50% 0 0 0); }",

    ".bd-arcade { background: linear-gradient(to bottom, #101011 0%, #151515 40%); }",
    ".bd-pixel { position: absolute; width: 2px; height: 2px; background: #ebebeb; opacity: .1; animation: bd-blink 3.2s steps(1) infinite; }",
    "@keyframes bd-blink { 0%, 100% { opacity: .1; } 50% { opacity: .45; } }",
    ".bd-hills { position: absolute; left: 0; width: 100%; height: 16cqh; }",
    ".bd-hills svg { display: block; width: 100%; height: 100%; }",
    ".bd-ground { position: absolute; left: 0; right: 0; height: 2px; border-radius: 1px; background: rgba(235, 235, 235, .12); }",
    ".bd-runner { position: absolute; left: 0; width: 24px; height: 24px; will-change: transform; animation: bd-run 20s linear infinite; }",
    "@keyframes bd-run { from { transform: translateX(-40px); } to { transform: translateX(calc(100cqw + 40px)); } }",
    ".bd-hop { position: absolute; inset: 0; animation: bd-hop .46s steps(1) infinite; }",
    "@keyframes bd-hop { 0%, 49.9% { transform: translateY(0); } 50%, 100% { transform: translateY(-3px); } }",
    ".bd-frame { position: absolute; inset: 0; }",
    ".bd-frame svg { display: block; width: 100%; height: 100%; }",
    ".bd-frame-a { animation: bd-frame-a .46s steps(1) infinite; }",
    ".bd-frame-b { opacity: 0; animation: bd-frame-b .46s steps(1) infinite; }",
    "@keyframes bd-frame-a { 0%, 49.9% { opacity: 1; } 50%, 100% { opacity: 0; } }",
    "@keyframes bd-frame-b { 0%, 49.9% { opacity: 0; } 50%, 100% { opacity: 1; } }",
    ".bd-coin { position: absolute; width: 12px; height: 12px; }",

    ".bd-picture { background-position: center; background-size: cover; background-repeat: no-repeat; }",

    "@media (prefers-reduced-motion: reduce) { .bd *, .bd-runner, .bd-runner * { animation: none !important; } .bd-fall, .bd-mote { display: none; } }",
  ].join("\n");

  function number(n) {
    return String(Math.round(n * 10) / 10);
  }

  function seeded(seed) {
    var state = seed >>> 0;
    return function () {
      state = (state + 0x6d2b79f5) | 0;
      var t = Math.imul(state ^ (state >>> 15), 1 | state);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  // MARK: Leaves

  var TONES = {
    bronze: { dark: "#24190f", light: "#80593a", vein: "#cc9e66" },
    umber: { dark: "#1f1712", light: "#5e4633", vein: "#aa865c" },
    slate: { dark: "#191d21", light: "#3c444c", vein: "#8c7c64" },
  };
  var gradients = 0;

  // One leaf, drawn upright with its base at the bottom: a blade with a slight lean, a midrib
  // running into the stem, and paired side veins that sweep toward the tip.
  function leaf(length, tone, random) {
    var id = "bd-leaf-" + gradients++;
    var h = length, w = length * (0.2 + random() * 0.09);
    var lean = (random() - 0.5) * w * 0.4;
    var top = -h / 2, bottom = h / 2;
    var blade = "M0 " + number(bottom) +
      " C" + number(w * 1.12) + " " + number(h * 0.22) + " " + number(w * 0.92 + lean) + " " + number(-h * 0.28) + " " + number(lean * 0.3) + " " + number(top) +
      " C" + number(-w * 0.92 + lean) + " " + number(-h * 0.28) + " " + number(-w * 1.12) + " " + number(h * 0.22) + " 0 " + number(bottom) + "Z";
    var veins = "M0 " + number(bottom + h * 0.1) + " Q" + number(lean * 0.25) + " 0 " + number(lean * 0.3) + " " + number(top + h * 0.03);
    var count = 6 + Math.floor(random() * 4);
    for (var i = 1; i <= count; i++) {
      var y = bottom - i * (h / (count + 1));
      var reach = w * 0.86 * Math.sqrt(Math.max(0, 1 - Math.pow(y / (h / 2), 2)));
      var x = lean * 0.3 * (1 - (y - top) / h);
      veins += " M" + number(x) + " " + number(y) + " Q" + number(x + reach * 0.5) + " " + number(y - h * 0.03) + " " + number(x + reach) + " " + number(y - h * 0.11);
      veins += " M" + number(x) + " " + number(y) + " Q" + number(x - reach * 0.5) + " " + number(y - h * 0.03) + " " + number(x - reach) + " " + number(y - h * 0.11);
    }
    var boxWidth = w * 2.6, boxHeight = h * 1.25;
    return "<svg viewBox=\"" + number(-boxWidth / 2) + " " + number(top - h * 0.05) + " " + number(boxWidth) + " " + number(boxHeight) + "\" width=\"" + number(boxWidth) + "\" height=\"" + number(boxHeight) + "\">" +
      "<defs><linearGradient id=\"" + id + "\" x1=\"0\" y1=\"1\" x2=\"0.35\" y2=\"0\"><stop offset=\"0\" stop-color=\"" + tone.dark + "\"/><stop offset=\"1\" stop-color=\"" + tone.light + "\"/></linearGradient></defs>" +
      "<path d=\"" + blade + "\" fill=\"url(#" + id + ")\"/>" +
      "<path d=\"" + veins + "\" fill=\"none\" stroke=\"" + tone.vein + "\" stroke-opacity=\".55\" stroke-width=\"" + number(Math.max(0.8, h / 160)) + "\" stroke-linecap=\"round\"/></svg>";
  }

  function leaves(width, height, random) {
    var scale = Math.max(0.7, Math.min(1.4, width / 1300));
    var layers = [
      { count: 9, min: 120, max: 220, tones: ["slate", "umber"], opacity: 0.4, blur: 2.5, sway: 2 },
      { count: 9, min: 150, max: 270, tones: ["umber", "bronze", "slate"], opacity: 0.7, blur: 0, sway: 3 },
      { count: 5, min: 200, max: 340, tones: ["bronze", "umber"], opacity: 0.92, blur: 0, sway: 4 },
    ];
    var html = "";
    for (var d = 0; d < layers.length; d++) {
      var layer = layers[d];
      html += "<div class=\"bd-layer\" style=\"opacity:" + layer.opacity + (layer.blur ? ";filter:blur(" + layer.blur + "px)" : "") + "\">";
      for (var i = 0; i < layer.count; i++) {
        var x = ((i + random()) / layer.count) * width * 1.16 - width * 0.08;
        var y = random() * height * 1.1 - height * 0.05;
        var size = (layer.min + random() * (layer.max - layer.min)) * scale;
        var tone = TONES[layer.tones[Math.floor(random() * layer.tones.length)]];
        var turn = -70 + random() * 140 + (x < width / 2 ? -20 : 20);
        var duration = 9 + random() * 8;
        html += "<div class=\"bd-leaf\" style=\"left:" + number(x) + "px;top:" + number(y) + "px;--r:" + number(turn) + "deg;--sway:" + (layer.sway * (0.6 + random() * 0.8)).toFixed(2) +
          "deg;animation-duration:" + number(duration) + "s;animation-delay:" + number(-random() * duration) + "s\">" + leaf(size, tone, random) + "</div>";
      }
      html += "</div>";
    }
    // A few leaves falling through, and specks of pollen drifting up.
    for (var k = 0; k < 4; k++) {
      var fall = 24 + random() * 18;
      html += "<div class=\"bd-fall\" style=\"left:" + number(random() * width) + "px;--o:" + (0.55 + random() * 0.35).toFixed(2) + ";animation-duration:" + number(fall) + "s;animation-delay:" + number(-random() * fall) + "s\">" +
        leaf((70 + random() * 60) * scale, k % 2 ? TONES.bronze : TONES.umber, random) + "</div>";
    }
    for (var p = 0; p < 18; p++) {
      var rise = 14 + random() * 16;
      html += "<i class=\"bd-mote\" style=\"left:" + number(random() * width) + "px;top:" + number(height * (0.3 + random() * 0.8)) + "px;animation-duration:" + number(rise) + "s;animation-delay:" + number(-random() * rise) + "s\"></i>";
    }
    return "<div class=\"bd-scene bd-leaves\">" + html + "</div>";
  }

  // MARK: Dunes and Orbit

  function stars(count, depth, random) {
    var html = "";
    for (var i = 0; i < count; i++) {
      var twinkle = 3 + random() * 5;
      html += "<i class=\"bd-star\" style=\"left:" + (random() * 100).toFixed(2) + "%;top:" + (random() * depth).toFixed(2) + "%;animation-duration:" + number(twinkle) + "s;animation-delay:" + number(-random() * twinkle) + "s\"></i>";
    }
    return html;
  }

  function dunes(random) {
    return "<div class=\"bd-scene bd-dunes\">" + stars(46, 48, random) +
      "<div class=\"bd-world\"><div class=\"bd-sand\"></div><div class=\"bd-sand bd-sand-2\"></div></div><div class=\"bd-limb\"></div></div>";
  }

  function orbit(random) {
    return "<div class=\"bd-scene bd-orbit-scene\">" + stars(60, 100, random) +
      "<div class=\"bd-orbit\"><div class=\"bd-tilt\"><div class=\"bd-ring bd-ring-back\"></div>" +
      "<div class=\"bd-globe\"><div class=\"bd-bands\"></div><div class=\"bd-shade\"></div></div>" +
      "<div class=\"bd-ring bd-ring-front\"></div></div></div></div>";
  }

  // MARK: Arcade

  // Two-frame pixel sprites on an 8 x 8 grid. '#' is lit, '.' is clear.
  var SPRITES = {
    blip: {
      color: "#ebebeb",
      frames: [
        ["........", ".######.", "##.##.##", "########", "########", ".######.", ".#....#.", "#......#"],
        ["........", ".######.", "##.##.##", "########", "########", ".######.", "..#..#..", "..#..#.."],
      ],
    },
    spark: {
      color: "#e9a66c",
      frames: [
        ["...#....", "...#....", "#..#..#.", ".#####..", "..###...", ".#####..", "#..#..#.", "...#...."],
        ["#.....#.", ".#.#.#..", "..###...", "#######.", "..###...", ".#.#.#..", "#.....#.", "........"],
      ],
    },
    cube: {
      color: "#a3bf9c",
      frames: [
        ["..####..", ".#....#.", "#......#", "########", "#.#..#.#", "#.#..#.#", "########", ".#....#."],
        ["..####..", ".#....#.", "#......#", "########", "#.#..#.#", "#.#..#.#", "########", "#......#"],
      ],
    },
    coin: {
      color: "#d6a64a",
      frames: [
        ["........", "..####..", ".######.", "########", "########", ".######.", "..####..", "........"],
        ["........", "...##...", "...##...", "...##...", "...##...", "...##...", "...##...", "........"],
      ],
    },
  };

  function pixels(rows) {
    var path = "";
    for (var y = 0; y < rows.length; y++) {
      for (var x = 0; x < rows[y].length; x++) {
        if (rows[y].charAt(x) === "#") path += "M" + x + " " + y + "h1v1h-1z";
      }
    }
    return path;
  }

  function frames(kind) {
    var sprite = SPRITES[kind] || SPRITES.blip;
    function frame(rows, name) {
      return "<div class=\"bd-frame " + name + "\"><svg viewBox=\"0 0 8 8\" shape-rendering=\"crispEdges\" fill=\"" + sprite.color + "\"><path d=\"" + pixels(rows) + "\"/></svg></div>";
    }
    return frame(sprite.frames[0], "bd-frame-a") + frame(sprite.frames[1], "bd-frame-b");
  }

  // A pixel sprite running across its container, for anywhere on a page.
  function sprite(kind, style) {
    return "<div class=\"bd-runner\" style=\"" + (style || "") + "\"><div class=\"bd-hop\">" + frames(kind) + "</div></div>";
  }

  // Stepped pixel hills, as one path on a 160 x 40 grid.
  function hills(random, step, low, high, fill) {
    var height = low + random() * (high - low);
    var path = "M0 40";
    for (var x = 0; x < 160; x += step) {
      height = Math.max(low, Math.min(high, height + (random() - 0.5) * 12));
      path += "V" + (40 - Math.round(height)) + "H" + (x + step);
    }
    return "<svg viewBox=\"0 0 160 40\" preserveAspectRatio=\"none\" shape-rendering=\"crispEdges\"><path fill=\"" + fill + "\" d=\"" + path + "Z\"/></svg>";
  }

  // Pixel runners racing along a ridge, under a blinking pixel sky. The ground sits in the gap under
  // the Overview hero, so the runners pass behind the cards.
  function arcade(random) {
    var ground = 36;
    var html = "<div class=\"bd-scene bd-arcade\">";
    for (var i = 0; i < 30; i++) {
      html += "<div class=\"bd-pixel\" style=\"left:" + (random() * 100).toFixed(2) + "%;top:" + (2 + random() * 26).toFixed(2) + "cqh;animation-delay:" + number(-random() * 3.2) + "s\"></div>";
    }
    html += "<div class=\"bd-hills\" style=\"top:calc(" + ground + "cqh - 16cqh)\">" + hills(random, 4, 10, 38, "#1b1a19") + "</div>";
    html += "<div class=\"bd-hills\" style=\"top:calc(" + ground + "cqh - 16cqh)\">" + hills(random, 6, 3, 18, "#211d19") + "</div>";
    html += "<div class=\"bd-ground\" style=\"top:" + ground + "cqh\"></div>";
    var runners = [["blip", 19], ["spark", 27], ["cube", 23]];
    for (var r = 0; r < runners.length; r++) {
      html += sprite(runners[r][0], "top:calc(" + ground + "cqh - 24px);animation-duration:" + runners[r][1] + "s;animation-delay:" + number(-random() * runners[r][1]) + "s");
    }
    for (var c = 0; c < 6; c++) {
      html += "<div class=\"bd-coin\" style=\"left:" + (6 + random() * 88).toFixed(2) + "%;top:calc(" + ground + "cqh - 48px)\">" + frames("coin") + "</div>";
    }
    return html + "</div>";
  }

  // MARK: Mount

  function picture(url) {
    return "<div class=\"bd-scene bd-picture\" style=\"background-image:url('" + String(url).replace(/'/g, "%27") + "')\"></div>";
  }

  var styled = false;

  function mount(host, options) {
    if (!styled) {
      var style = document.createElement("style");
      style.textContent = CSS;
      document.head.appendChild(style);
      styled = true;
    }
    host.classList.add("bd");
    var settings = {}, built = "", timer = 0;

    function render() {
      var width = host.clientWidth || 1200, height = host.clientHeight || 800;
      var scene = settings.scene;
      // Leaves are laid out for the width, so a big resize lays them out again.
      var key = scene + "|" + (scene === "image" ? settings.image : "") + "|" + (scene === "leaves" ? Math.round(width / 240) + "x" + Math.round(height / 240) : "");
      if (key === built) return;
      built = key;
      gradients = 0;
      var random = seeded(20260911);
      var html = "";
      if (scene === "leaves") html = leaves(width, height, random);
      else if (scene === "dunes") html = dunes(random);
      else if (scene === "orbit") html = orbit(random);
      else if (scene === "arcade") html = arcade(random);
      else if (scene === "image" && settings.image) html = picture(settings.image);
      host.innerHTML = html ? html + (scene === "arcade" ? "" : "<div class=\"bd-veil\"></div>") : "";
    }

    function update(next) {
      settings = Object.assign({}, settings, next || {});
      host.hidden = !settings.scene || settings.scene === "off" || (settings.scene === "image" && !settings.image);
      host.style.opacity = String(Math.min(1, Math.max(0.1, settings.opacity == null ? 0.8 : +settings.opacity)));
      render();
    }

    if (window.ResizeObserver) {
      new ResizeObserver(function () {
        clearTimeout(timer);
        timer = setTimeout(render, 250);
      }).observe(host);
    }
    update(options);
    return { update: update };
  }

  window.SwitchrBackdrop = { mount: mount, sprite: sprite };
})();
/* backdrop:end */`;
