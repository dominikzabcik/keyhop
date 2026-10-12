import Foundation

/// The backdrop scenes, the night and day field, and the appearance settings that drive them.
extension DashboardPage {
    static let scriptBackdrop = ##"""
  // MARK: Backdrop

  let fieldLoop = null;
  let fieldBeat = 0;
  let runnerPhase = 0;
  let fieldDash = 0;
  let shownPressure = null;
  let gaitHold = "sit";
  let skyCache = null;
  let skyKey = "";

  // Night or day is a saved choice; "auto" follows the system. The sky is painted again on a change.
  const daylight = matchMedia("(prefers-color-scheme: light)");
  function applyTheme() {
    const wanted = data.state?.appearance?.theme || "night";
    const theme = wanted === "auto" ? (daylight.matches ? "day" : "night") : wanted;
    if (ui.theme === theme) return;
    ui.theme = theme;
    document.documentElement.dataset.theme = theme;
    const meta = document.querySelector('meta[name="color-scheme"]');
    if (meta) meta.content = theme === "day" ? "light" : "dark";
    skyKey = "";
    paintField();
  }
  daylight.addEventListener("change", () => { if (data.state) { applyTheme(); render(); applyBackdrop(); } });

  function fieldWanted() {
    if (ui.section !== "overview" || !data.state) return false;
    return (data.state.appearance?.scene || "leaves") === "leaves";
  }

  function horizon(nx) {
    return 0.66 + Math.sin(nx * 4.8 + 0.4) * 0.04 + Math.sin(nx * 10.5 + 1.1) * 0.015;
  }

  function skyOf(w, h, day) {
    const img = new ImageData(w, h);
    const bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];
    const px = img.data;
    const clouds = [[0.22, 0.2, 0.2], [0.55, 0.16, 0.26], [0.78, 0.28, 0.18]];
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const nx = x / w, ny = y / h;
        const skyT = Math.min(1, ny / 0.72);
        let r, g, b;
        if (day) { r = 132 + skyT * 100; g = 188 + skyT * 36; b = 222 - skyT * 20; }
        else { r = 12 + skyT * 20; g = 18 + skyT * 8; b = 36 - skyT * 16; }
        let ck = 0;
        for (const [cx, cy, s] of clouds) {
          const d = ((nx - cx) / s) ** 2 + ((ny - cy) / (s * 0.42)) ** 2;
          if (d < 1) ck = Math.max(ck, (1 - d) * 0.7);
        }
        if (ck) {
          if (day) { r += (255 - r) * ck * 0.85; g += (255 - g) * ck * 0.85; b += (255 - b) * ck * 0.75; }
          else { r += 48 * ck; g += 58 * ck; b += 78 * ck; }
        }
        if (!day) {
          const n = Math.abs(Math.sin(x * 12.9898 + y * 78.233) * 43758.5453) % 1;
          if (n > 0.992 && ny < horizon(nx) - 0.08) r = g = b = 220;
        }
        const h1 = horizon(nx);
        const h2 = h1 + 0.075 + Math.sin(nx * 3.1) * 0.012;
        if (ny > h2) { if (day) { r = 198; g = 168; b = 128; } else { r = 18; g = 14; b = 12; } }
        else if (ny > h1) { if (day) { r = 226; g = 196; b = 156; } else { r = 72; g = 52; b = 36; } }
        const t = (bayer[y & 3][x & 3] / 16 - 0.5) * 48;
        const q = (v) => Math.max(0, Math.min(255, Math.round((v + t) / 36) * 36));
        const i = (y * w + x) * 4;
        px[i] = q(r); px[i + 1] = q(g); px[i + 2] = q(b); px[i + 3] = 255;
      }
    }
    return img;
  }

  // Same enamels as the usage chart. The body stays bone so it reads on the dune; one pixel wears the tool.
  const fieldInkOf = {
    claude: "#C9821A", cursor: "#2F6FC0", codex: "#B8423F", gemini: "#1E9A78",
    opencode: "#7A6BC4", pi: "#C45B8A", copilot: "#6B8F9E", windsurf: "#3D8B9A", codebuff: "#A67C52",
  };

  // The sky stays cached. The moon and the runner are the meter: low and warm when a login is
  // against its limit, sitting when nothing has a limit to read. The head wears the tool that
  // sets that pace. A hop repaints it with the destination for one sprint.
  function fieldTarget() {
    const tools = data.state?.status?.tools || [];
    let pressure = 0;
    let gait = "sit";
    let pace = "";
    for (const row of accountRows(tools)) {
      const lane = laneOf(row.account);
      const used = Math.max(0, maxUsed(row.account)) / 100;
      const weight = lane === "needs" ? Math.max(used, 0.92) : used;
      if (weight > pressure) { pressure = weight; pace = row.tool.id; }
      if (lane === "needs") gait = "run";
      else if (gait === "sit" && lane !== "quiet") gait = "walk";
    }
    const tool = fieldDash > 0 ? ui.homeTool : pace;
    return { pressure: Math.min(1, pressure), gait, ink: fieldInkOf[tool] || "#f3ead8" };
  }

  // Hold a gait past the line that entered it, so a login flickering around 85% does not strobe the runner.
  function shownGait(pressure, raw) {
    if (raw === "run" || pressure >= 0.85) gaitHold = "run";
    else if (gaitHold === "run" && pressure >= 0.72) gaitHold = "run";
    else if (raw === "sit") gaitHold = pressure >= 0.12 && gaitHold !== "sit" ? "walk" : "sit";
    else gaitHold = "walk";
    return gaitHold;
  }

  function fieldMood() {
    const target = fieldTarget();
    if (shownPressure == null || still.matches) shownPressure = target.pressure;
    else {
      const gap = target.pressure - shownPressure;
      shownPressure = Math.abs(gap) < 0.02 ? target.pressure : shownPressure + gap * 0.35;
    }
    const gait = fieldDash > 0 ? "run" : shownGait(target.pressure, target.gait);
    return { pressure: shownPressure, gait, ink: target.ink };
  }

  // By day the same disc is the sun: it sinks and reddens as a login nears its limit.
  function paintMoon(ctx, w, h, pressure, day) {
    const cx = Math.round(w * 0.86 / 2) * 2;
    const cy = Math.round(h * (0.11 + pressure * 0.28) / 2) * 2;
    const heat = Math.max(0, Math.min(1, (pressure - 0.45) / 0.55));
    const disc = day
      ? [255, 222 + (150 - 222) * heat, 140 + (70 - 140) * heat]
      : [236 + (227 - 236) * heat, 224 + (166 - 224) * heat, 196 + (79 - 196) * heat];
    const bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];
    const glow = 42;
    const img = ctx.getImageData(0, 0, w, h);
    const px = img.data;
    const x0 = Math.max(0, cx - glow), x1 = Math.min(w - 1, cx + glow);
    const y0 = Math.max(0, cy - glow), y1 = Math.min(h - 1, cy + glow);
    const q = (v, x, y) => {
      const t = (bayer[y & 3][x & 3] / 16 - 0.5) * 48;
      return Math.max(0, Math.min(255, Math.round((v + t) / 36) * 36));
    };
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const d = Math.hypot(x - cx, y - cy);
        const i = (y * w + x) * 4;
        if (d < 12) {
          px[i] = q(disc[0], x, y); px[i + 1] = q(disc[1], x, y); px[i + 2] = q(disc[2], x, y);
        } else if (d < glow) {
          const k = (1 - (d - 12) / (glow - 12)) * (0.34 + heat * 0.4);
          px[i] = q(px[i] + (150 + heat * 50) * k, x, y);
          px[i + 1] = q(px[i + 1] + (120 - heat * 30) * k, x, y);
          px[i + 2] = q(px[i + 2] + (60 - heat * 24) * k, x, y);
        }
      }
    }
    ctx.putImageData(img, 0, 0);
  }

  function stampSprite(ctx, x, y, cells, mark, scale, day) {
    const origin = Math.round(x / 2) * 2;
    const top = Math.round(y / 2) * 2;
    ctx.fillStyle = day ? "#f3ead8" : "#140e0c";
    for (const [dx, dy] of cells) {
      for (const [ox, oy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        ctx.fillRect(origin + dx * scale + ox, top + dy * scale + oy, scale, scale);
      }
    }
    ctx.fillStyle = day ? "#2c241c" : "#f3ead8";
    for (const [dx, dy] of cells) ctx.fillRect(origin + dx * scale, top + dy * scale, scale, scale);
    const head = cells[0];
    if (head && mark) {
      ctx.fillStyle = mark;
      ctx.fillRect(origin + head[0] * scale, top + head[1] * scale, scale, scale);
    }
  }

  function paintField() {
    const canvas = $("#field");
    const stage = $("#hero-art");
    if (!canvas || !stage || stage.hidden || !fieldWanted()) return;
    const rect = stage.getBoundingClientRect();
    if (rect.width < 2 || rect.height < 2) return;
    const w = Math.max(2, Math.round(rect.width / 2));
    const h = Math.max(2, Math.round(rect.height / 2));
    const day = ui.theme === "day";
    const key = w + "x" + h + (day ? ":day" : ":night");
    if (skyKey !== key) { skyCache = skyOf(w, h, day); skyKey = key; }
    if (canvas.width !== w) canvas.width = w;
    if (canvas.height !== h) canvas.height = h;
    const ctx = canvas.getContext("2d");
    if (!ctx || !skyCache) return;
    ctx.putImageData(skyCache, 0, 0);
    const mood = fieldMood();
    paintMoon(ctx, w, h, mood.pressure, day);
    const walk = [
      [[2, 0], [1, 1], [2, 1], [3, 1], [0, 2], [2, 2], [4, 2], [1, 3], [3, 4]],
      [[2, 0], [1, 1], [2, 1], [3, 1], [1, 2], [3, 2], [2, 3], [2, 4]],
    ];
    const run = [
      [[4, 0], [2, 1], [3, 1], [4, 1], [1, 2], [3, 2], [5, 2], [2, 3], [4, 3], [0, 3], [5, 4]],
      [[4, 1], [3, 1], [4, 1], [5, 1], [2, 2], [4, 2], [3, 3], [5, 3], [1, 4]],
    ];
    const sit = [
      [[2, 1], [1, 2], [2, 2], [3, 2], [1, 3], [2, 3], [3, 3]],
      [[2, 1], [1, 2], [2, 2], [3, 2], [1, 3], [2, 3], [3, 3], [2, 4]],
    ];
    const frames = mood.gait === "run" ? run : mood.gait === "walk" ? walk : sit;
    const along = still.matches || mood.gait === "sit" ? 0.45
      : mood.gait === "run" ? (runnerPhase % 24) / 24
      : (runnerPhase % 48) / 48;
    // The words take the wallpaper's left. The runner stays on the open dune under the moon.
    const nx = 0.78 + along * 0.14;
    const cells = frames[(still.matches ? 0 : fieldBeat) % 2];
    const scale = 4;
    const tall = cells.reduce((top, cell) => Math.max(top, cell[1]), 0) + 1;
    const x = Math.round(nx * w / 2) * 2;
    const y = Math.round((horizon(Math.max(0, Math.min(0.99, nx))) * h - tall * scale) / 2) * 2;
    stampSprite(ctx, x, y, cells, mood.ink, scale, day);
    paintDunePet(ctx, w, h, rect.width);
  }

  let petStamp = null;
  let petStampKey = "";

  // The sidebar used to squash this drawing into 36px. On the dune one of its own pixels stays one pixel.
  function paintDunePet(ctx, w, h, stageW) {
    const pet = data.pet;
    if (!pet?.shapes?.length || !stageW) return;
    // In Home's wallpaper the words take the left; the pet stands on the dune past them.
    if (stageW < 640) return;
    const cssW = Math.min(pet.width, 120, stageW * 0.13);
    const dw = Math.max(8, Math.round(cssW / 4) * 2);
    const dh = Math.max(8, Math.round(dw * pet.height / pet.width / 2) * 2);
    const blink = still.matches || fieldBeat % 6 !== 0;
    const key = [pet.stage, pet.pose, pet.lineage, pet.build, pet.tokens, blink].join(":");
    if (!petStamp || petStampKey !== key) {
      const plate = document.createElement("canvas");
      plate.width = pet.width;
      plate.height = pet.height;
      const pen = plate.getContext("2d");
      if (!pen) return;
      for (const shape of pet.shapes) {
        if (!blink && (shape.kind === "shine" || shape.kind === "eye")) continue;
        pen.globalAlpha = shape.opacity == null ? 1 : shape.opacity;
        pen.fillStyle = shape.fill;
        const bob = shape.kind === "flame" && !blink ? -2 : 0;
        pen.fillRect(shape.x, shape.y + bob, shape.w, shape.h);
      }
      petStamp = plate;
      petStampKey = key;
    }
    const span = (dw * 2) / stageW;
    const left = 0.7;
    const foot = left + span / 2;
    const x = Math.round(left * w / 2) * 2;
    const y = Math.round((horizon(Math.max(0, Math.min(0.99, foot))) * h - dh) / 2) * 2;
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(petStamp, x, y, dw, dh);
  }

  function syncField() {
    const on = fieldWanted();
    $("#content")?.classList.toggle("is-field", on);
    const canvas = $("#field");
    if (canvas) canvas.hidden = !on;
    const host = $("#backdrop");
    if (host && data.state) host.classList.toggle("scoped-out", backdropScopedOut());
    if (!on) {
      if (fieldLoop) { clearInterval(fieldLoop); fieldLoop = null; }
      return;
    }
    paintField();
    requestAnimationFrame(paintField);
    if (!fieldLoop && !still.matches) {
      fieldLoop = setInterval(() => {
        if (document.hidden) return;
        fieldBeat += 1;
        const target = fieldTarget();
        const gait = fieldDash > 0 ? "run" : shownGait(target.pressure, target.gait);
        if (fieldDash > 0) { runnerPhase += 6; fieldDash -= 1; }
        else if (gait === "run") runnerPhase += 2;
        else if (gait === "walk") runnerPhase += 1;
        paintField();
      }, 700);
    }
  }


  let backdrop = null;
  let heroBackdrop = null;
  let backdropImage = null;
  let backdropImageLoading = false;

  async function applyBackdrop() {
    const host = $("#backdrop");
    if (!host || !window.KeyhopBackdrop) { syncField(); return; }
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
    document.documentElement.classList.toggle("has-backdrop", scene !== "off" && !backdropScopedOut());
    host.classList.toggle("scoped-out", backdropScopedOut());
    // The scenes are painted for the night. By day they show at under half their strength.
    const opacity = ui.theme === "day" && scene !== "image" ? look.opacity * 0.4 : look.opacity;
    const options = { scene, opacity, image: scene === "image" ? backdropImage : null };
    if (backdrop) backdrop.update(options);
    else backdrop = window.KeyhopBackdrop.mount(host, options);
    // Home carries the scene in its wallpaper; the field paints itself, any other scene is mounted there.
    const heroScene = $("#hero-scene");
    if (heroScene) {
      const sceneThere = ui.section === "overview" && scene !== "leaves" ? options : { ...options, scene: "off" };
      if (heroBackdrop) heroBackdrop.update(sceneThere);
      else heroBackdrop = window.KeyhopBackdrop.mount(heroScene, sceneThere);
    }
    syncField();
  }

  // Behind the other sections the scene shows only when it is set to show everywhere. Home has its own.
  function backdropScopedOut() {
    if (ui.section === "overview") return true;
    return (data.state?.appearance?.scope || "overview") !== "all";
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
      leaves: "On Home, a dithered field. The moon, or by day the sun, drops as a login nears its limit. A runner keeps that pace, and its head wears the tool. Behind the other sections, leaves sway on their stems.",
      dunes: "A desert world's horizon, turning slowly under the stars.",
      orbit: "A ringed planet floating in the dark.",
      arcade: "Pixel runners racing along a ridge of pixel hills.",
      image: "Your picture, softly behind everything.",
      off: "A plain surface.",
    }[look.scene];
    const themeNote = { night: "The night field: dark surfaces, light ink.", day: "The day field: light surfaces, dark ink.", auto: "Follows the system's light or dark setting." }[look.theme || "night"];
    return `<section class="card"><div class="card-head"><h2>Backdrop</h2><span class="hint">Window scene & material</span></div>
      <div class="list">
        <div class="row setting-row"><div><b>Field</b><p>${themeNote}</p></div>${pick("theme", [["night", "Night"], ["day", "Day"], ["auto", "Auto"]], look.theme || "night")}</div>
        <div class="row setting-row"><div><b>Scene</b><p>${about}</p></div>${pick("scene", [["leaves", "Leaves"], ["dunes", "Dunes"], ["orbit", "Orbit"], ["arcade", "Arcade"], ["image", "Picture"], ["off", "Off"]], look.scene)}</div>
        <div class="row setting-row"><div><b>Show on</b><p>${look.scope === "overview" ? "Only in Home's wallpaper. Every other section stays plain." : "In Home's wallpaper and behind every section."}</p></div>${pick("scope", [["overview", "Home only"], ["all", "Everywhere"]], look.scope)}</div>
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

"""##
}
