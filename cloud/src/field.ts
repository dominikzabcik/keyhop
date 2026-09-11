// The Field: Switchr's live dot-matrix backdrop. The same script runs in the app's dashboard
// (Sources/Switchr/Dashboard/Field.swift), and a Swift test keeps the two copies identical.
export const FIELD_SCRIPT = String.raw`/* field:start */
(function () {
  "use strict";
  if (window.SwitchrField) return;

  // A scene drawn as dots behind the page. Nothing on the page depends on it: without it, a page
  // is simply its plain dark surface.
  var PITCH = 6;
  var DOT = 4.5;
  var FRAME_MS = 42;
  var BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
  var TINTS = { mono: [235, 235, 235], ember: [236, 186, 120], moss: [160, 208, 170] };

  function hash(x, y) {
    var h = (Math.imul(x | 0, 374761393) + Math.imul(y | 0, 668265263)) | 0;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
  }

  function ease(t) {
    return t * t * (3 - 2 * t);
  }

  function noise(x, y) {
    var xi = Math.floor(x), yi = Math.floor(y);
    var u = ease(x - xi), v = ease(y - yi);
    var a = hash(xi, yi), b = hash(xi + 1, yi), c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  }

  function stars(x, y, t) {
    var s = hash(x * 3 + 17, y * 5 + 11);
    if (s < 0.9972) return 0;
    return (0.4 + 0.6 * hash(y, x)) * (0.6 + 0.4 * Math.sin(t * (0.8 + s * 2.4) + x * 0.7));
  }

  // A planet's lit edge sweeping across the top of the page, its atmosphere catching light from
  // the right, drifting dunes and a few stars. band is the height of the composed area, in rows.
  function horizon(cols, rows, band) {
    var apex = band * 0.6;
    var r = Math.max(cols * 0.9, band * 2.2);
    var cx = cols * 0.68, cy = apex + r;
    return function (x, y, t) {
      var dx = x - cx, dy = y - cy;
      var edge = Math.sqrt(dx * dx + dy * dy) - r;
      var light = Math.min(1, Math.max(0.15, 0.62 + dx / (cols * 0.75)));
      var breathe = 0.94 + 0.06 * Math.sin(t * 0.45);
      if (edge < 0) {
        var depth = -edge;
        var rim = Math.exp(-depth / 1.6) * light * breathe;
        if (depth > band * 0.7) return rim;
        var dunes = noise(x * 0.045 + t * 0.025, y * 0.18) * 0.65 + noise(x * 0.12 - t * 0.012, y * 0.45) * 0.35;
        return rim + Math.max(0, dunes - 0.45) * 1.1 * Math.exp(-depth / (band * 0.3)) * light;
      }
      var glow = Math.exp(-edge / 3.2) * light * breathe;
      var haze = Math.exp(-edge / (band * 0.4)) * 0.22 * light * light;
      return glow + haze + stars(x, y, t) * 0.85;
    };
  }

  function smoothed(values, radius) {
    var out = [];
    for (var i = 0; i < values.length; i++) {
      var sum = 0, count = 0;
      for (var j = Math.max(0, i - radius); j <= Math.min(values.length - 1, i + radius); j++) {
        sum += values[j];
        count++;
      }
      out.push(count ? sum / count : 0);
    }
    return out;
  }

  // Usage as a range of ridges: the front ridge follows the days closely, and the smoother ridges
  // behind it drift slowly.
  function signal(cols, rows, series, band) {
    function at(values, position) {
      if (!values.length) return 0;
      var p = ((position % 1) + 1) % 1;
      var i = p * (values.length - 1), a = Math.floor(i), f = ease(i - a);
      var from = values[a], to = values[Math.min(values.length - 1, a + 1)];
      return from + (to - from) * f;
    }
    function looped(values) {
      return values.concat(values.slice().reverse());
    }
    var height = band;
    var layers = [
      { values: smoothed(series, 2), floor: 0.04, amp: 0.42, bright: 1, drift: 0 },
      { values: looped(smoothed(series, 7)), floor: 0.16, amp: 0.36, bright: 0.5, drift: 0.004 },
      { values: looped(smoothed(series, 16)), floor: 0.28, amp: 0.32, bright: 0.28, drift: 0.009 },
    ];
    return function (x, y, t) {
      var u = x / Math.max(1, cols - 1);
      for (var i = 0; i < layers.length; i++) {
        var layer = layers[i];
        var position = layer.drift ? u * 0.5 + t * layer.drift : u;
        var ridge = height * (1 - (layer.floor + layer.amp * at(layer.values, position)));
        if (y >= ridge) {
          var below = y - ridge;
          var body = 0.07 * Math.max(0, 1 - below / (height * 0.5));
          return (Math.exp(-below / 2.2) * 0.85 + body) * layer.bright;
        }
      }
      return stars(x, y, t) * 0.7;
    };
  }

  // A picture, brightness by brightness, breathing in and out a little.
  function picture(cols, rows, source) {
    var scale = Math.max(cols / source.width, rows / source.height);
    return function (x, y, t) {
      var zoom = scale * (1.03 + 0.02 * Math.sin(t * 0.07));
      var ix = Math.floor((x - cols / 2) / zoom + source.width / 2);
      var iy = Math.floor((y - rows / 2) / zoom + source.height / 2);
      if (ix < 0 || iy < 0 || ix >= source.width || iy >= source.height) return 0;
      return source.data[iy * source.width + ix];
    };
  }

  function luminance(url, done) {
    var image = new Image();
    image.onload = function () {
      var w = 240, h = Math.max(1, Math.round(240 * image.height / image.width));
      var canvas = document.createElement("canvas");
      canvas.width = w;
      canvas.height = h;
      var context = canvas.getContext("2d");
      context.drawImage(image, 0, 0, w, h);
      var pixels = context.getImageData(0, 0, w, h).data;
      var data = new Float32Array(w * h);
      for (var i = 0; i < w * h; i++) {
        data[i] = (0.2126 * pixels[i * 4] + 0.7152 * pixels[i * 4 + 1] + 0.0722 * pixels[i * 4 + 2]) / 255;
      }
      // Stretch the contrast, so a dim photo still fills the full range of dots.
      var sorted = Array.prototype.slice.call(data).sort(function (a, b) { return a - b; });
      var low = sorted[Math.floor(sorted.length * 0.03)], high = sorted[Math.floor(sorted.length * 0.97)];
      var span = Math.max(0.05, high - low);
      for (var k = 0; k < data.length; k++) data[k] = Math.min(1, Math.max(0, (data[k] - low) / span));
      done({ width: w, height: h, data: data });
    };
    image.onerror = function () { done(null); };
    image.src = url;
  }

  function normalize(series) {
    var values = (series || []).map(function (value) { return Math.max(0, +value || 0); });
    var max = 0;
    for (var i = 0; i < values.length; i++) max = Math.max(max, values[i]);
    return values.map(function (value) { return max ? Math.sqrt(value / max) : 0; });
  }

  function mount(host, options) {
    var canvas = document.createElement("canvas");
    canvas.className = "field-canvas";
    canvas.setAttribute("aria-hidden", "true");
    host.appendChild(canvas);
    var context = canvas.getContext("2d");
    var reduced = window.matchMedia ? window.matchMedia("(prefers-reduced-motion: reduce)").matches : false;
    var settings = {}, scene = null, source = null, sourceUrl = null;
    var cols = 0, rows = 0, width = 0, height = 0;
    var pointer = null, ripples = [], frame = 0, last = 0, visible = true, started = performance.now();

    function build() {
      scene = null;
      if (!cols || !rows) return;
      // The composed part of a scene is a fixed height in pixels, so it sits in the same place in
      // any window, above the fade.
      var band = Math.max(8, (settings.band || 320) / PITCH);
      var kind = settings.scene;
      if (kind === "signal") scene = signal(cols, rows, normalize(settings.series), band);
      else if (kind === "image" && source) scene = picture(cols, rows, source);
      else if (kind === "horizon" || kind === "image") scene = horizon(cols, rows, band);
    }

    function resize() {
      var rect = host.getBoundingClientRect();
      width = rect.width;
      height = rect.height;
      var dpr = Math.min(2, window.devicePixelRatio || 1);
      canvas.width = Math.max(1, Math.round(width * dpr));
      canvas.height = Math.max(1, Math.round(height * dpr));
      canvas.style.width = width + "px";
      canvas.style.height = height + "px";
      context.setTransform(dpr, 0, 0, dpr, 0, 0);
      cols = Math.ceil(width / PITCH);
      rows = Math.ceil(height / PITCH);
      build();
      paint(performance.now());
      wake();
    }

    function paint(now) {
      context.clearRect(0, 0, width, height);
      if (!scene) return;
      var t = (now - started) / 1000;
      var tint = TINTS[settings.tint] || TINTS.mono;
      var intensity = Math.min(1, Math.max(0.2, settings.intensity == null ? 0.6 : +settings.intensity));
      var peak = 0.18 + 0.62 * intensity;
      var paths = [null, new Path2D(), new Path2D(), new Path2D(), new Path2D()];
      var px = pointer ? pointer.x / PITCH : -1e4, py = pointer ? pointer.y / PITCH : -1e4, reach = 15;
      var waves = [];
      for (var k = ripples.length - 1; k >= 0; k--) {
        var age = (now - ripples[k].born) / 1000;
        if (age > 1.6) { ripples.splice(k, 1); continue; }
        waves.push({ x: ripples[k].x / PITCH, y: ripples[k].y / PITCH, radius: age * 48, strength: 0.7 * (1 - age / 1.6) });
      }
      for (var y = 0; y < rows; y++) {
        for (var x = 0; x < cols; x++) {
          var v = scene(x, y, t);
          var dx = x - px, dy = y - py, d2 = dx * dx + dy * dy;
          if (d2 < reach * reach) {
            var lens = 1 - Math.sqrt(d2) / reach;
            v = v * (1 + lens * 0.9) + lens * lens * 0.12;
          }
          for (var w = 0; w < waves.length; w++) {
            var wx = x - waves[w].x, wy = y - waves[w].y;
            var ring = Math.abs(Math.sqrt(wx * wx + wy * wy) - waves[w].radius);
            if (ring < 2.5) v += (1 - ring / 2.5) * waves[w].strength;
          }
          // Near-empty cells stay empty, so dark areas read as clean instead of speckled.
          if (v < 0.06) continue;
          v = Math.pow(Math.min(1, v), 0.85);
          var level = Math.floor(v * 4 + BAYER[((y & 3) << 2) | (x & 3)] / 16);
          if (level < 1) continue;
          if (level > 4) level = 4;
          paths[level].rect(x * PITCH + 0.75, y * PITCH + 0.75, DOT, DOT);
        }
      }
      for (var l = 1; l <= 4; l++) {
        context.fillStyle = "rgba(" + tint[0] + "," + tint[1] + "," + tint[2] + "," + (peak * l / 4).toFixed(3) + ")";
        context.fill(paths[l]);
      }
    }

    function tick(now) {
      frame = 0;
      if (!visible || document.hidden || !scene) return;
      if (now - last >= FRAME_MS) {
        last = now;
        paint(now);
      }
      frame = requestAnimationFrame(tick);
    }

    function wake() {
      if (reduced) { paint(performance.now()); return; }
      if (!frame) frame = requestAnimationFrame(tick);
    }

    function local(event) {
      var rect = host.getBoundingClientRect();
      var x = event.clientX - rect.left, y = event.clientY - rect.top;
      return x < 0 || y < 0 || x > rect.width || y > rect.height ? null : { x: x, y: y };
    }

    if (!reduced) {
      window.addEventListener("pointermove", function (event) { pointer = local(event); }, { passive: true });
      document.documentElement.addEventListener("mouseleave", function () { pointer = null; });
      window.addEventListener("pointerdown", function (event) {
        // Ripples start only on open background, never from a click on the page's own controls.
        if (event.button !== 0) return;
        if (event.target.closest && event.target.closest("a, button, input, select, textarea, label, summary, table, .card, [data-action]")) return;
        var at = local(event);
        if (!at) return;
        ripples.push({ x: at.x, y: at.y, born: performance.now() });
        if (ripples.length > 4) ripples.shift();
        wake();
      }, { passive: true });
    }
    if (window.ResizeObserver) new ResizeObserver(resize).observe(host);
    else window.addEventListener("resize", resize);
    if (window.IntersectionObserver) {
      new IntersectionObserver(function (entries) {
        visible = entries[0].isIntersecting;
        if (visible) wake();
      }).observe(host);
    }
    document.addEventListener("visibilitychange", function () { if (!document.hidden) wake(); });

    function update(next) {
      settings = Object.assign({}, settings, next || {});
      host.hidden = settings.scene === "off";
      if (settings.scene === "image" && settings.image && settings.image !== sourceUrl) {
        sourceUrl = settings.image;
        source = null;
        luminance(sourceUrl, function (result) {
          if (sourceUrl !== settings.image) return;
          source = result;
          build();
          paint(performance.now());
          wake();
        });
      }
      build();
      paint(performance.now());
      wake();
    }

    update(options);
    resize();
    return { update: update };
  }

  window.SwitchrField = { mount: mount };
})();
/* field:end */`;
