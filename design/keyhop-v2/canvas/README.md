# Keyhop 2.0 design canvas (saved 2026-10-15)

This is a full copy of the claude.ai design canvas the V2 look was worked out on (https://claude.ai/artifact/YS2A2BFhyu5azD75nKWPJj, owned by the old Claude account). `project/` is the canvas exactly as it was published: `canvas.json` holds the layout and every `*.dc.html` is one artboard.

## Where it ended

- **Chosen direction: S1 "Crisp"**, polished: `project/S1-Home.dc.html` and `project/S1-Components.dc.html`.
  - A calm night with solid surfaces (no glass), 1px borders, radius 6 (cards 8) and 32px controls.
  - Geist, with Instrument Serif only on the one card title.
  - One accent for actions. Red and amber only for limits that are running out, mint for "↑16%" and money.
  - Home layout: a shadcn-style inset sidebar (team switcher, ⌘K, Platform group, collapsible Insights, live limits, account). Left column: big tokens number with tool share and six tool cards, then Tokens per day, then Top models. Right column: the Bulk card as a night scene with the hopping pet, its speech bubble and stages, then Activity heatmap, then Needs you.
- **Open question: the colour.** The owner liked S1 but did not "feel" the colours. Five palettes of the same S1 are in `project/P-<name>-Home.dc.html` and `P-<name>-Components.dc.html`, with screenshots in `shots/`:
  - Iris (current violet on blue-black)
  - Graphite (neutral zinc, white primary)
  - Emerald (zinc + green)
  - Ember (warm stone + the pet's orange; "tight" moves to yellow)
  - Cobalt (slate + blue)
- **devl.dev takes (2026-10-15, new account):** S1 restyled after devl.dev, which is built on coss-ui (cal.com). The four variants are `project/K-<mono|ember|blue|iris>-Home.dc.html` and `-Components`, made by `tools/devl.py`. The comparison page is https://claude.ai/artifact/J7dTXDiZn4qxFtfz4SygT2.
  - They share coss-ui's dark neutrals: background #161616, sidebar #111, cards #1A1A1A, borders at 10% white, radius 10 and 12, tracked uppercase labels, sans titles and numbers, amber-500 and red for limits running out, and emerald-400 for money.
  - Mono has a monospace body (Geist Mono) and a white primary. Ember has a monospace body and the pet's orange, with tight limits moving to yellow. Blue has a Geist body and blue-400. Iris has a Geist body and S1's violet on the neutral grounds.
- **Picked: Coss Blue** (2026-10-15). The owner loved it and asked for more air. `project/KB-Home.dc.html` is the polished Home:
  - a wider sidebar with roomier rows and group spacing, and a 60px header;
  - 18–24px gutters, more padding in every card, and four Top models instead of five;
  - finer heatmap cells and a Live tag in normal case.
  `KB-Components` is still the unpolished blue sheet.
- **Next once a colour is picked:** apply it to System, Limits, the menu bar popover and keyhop.app (Mac and web in parity), then rewrite `design/keyhop-v2/index.html` and the window and site tokens.

## How we got there (rows on the canvas, oldest at the bottom)

1. **A–D:** four first directions.
   - A Nocturne, nuphos-like.
   - B Field, the pixel pet world.
   - C Instrument, mono and dense.
   - D Daylight, editorial.
2. **A×C "Observatory":** a merge of A and C.
   - Its Home was "too much in one place". Rebuilt calm, it then felt too much like nuphos.
   - `AC-Web` is keyhop.app built with the full taste-skill run. Its standalone source is `web/index.html` with `web/assets/` and credits in `web/assets/credits.json`.
3. **U1–U3 (Pixel Night, Keycut, Signal):** three invented identities, all rejected on overall feel.
4. **N, N2 "Native":** native macOS plus colourful and friendly. N2 combined nuphos with TokenTracker (github.com/xiufengsun/TokenTracker): huge number, tool share, heatmap, pet moods and stages, plus CSS motion. It felt "too macOS".
5. **N3–N6:** four frames for N2.
   - N3 own app, N4 night glass, N5 pastels, N6 web top bar.
   - N4 was the closest pick, but it was too colourful. Calm and mono versions are N4b and N4c, and calm won.
6. **N7:** shadcn sidebars on the calm Home.
   - N7a inset, N7b floating, N7c icon rail.
   - `N7-Components` is a big component sheet. Its table renders empty, the same `<sc-for>`-in-`<table>` bug that was fixed in S1-Components and was left unfixed here.
7. **S1–S3 "Sharper":** Crisp, Edge and Blade. S1 Crisp won ("don't change it that much, just polish").

## Rules learned while doing it

- Keep the owner's words: "unique", but not invented costume. Calm over dense. They like the night field and the pet, shadcn anatomy, and the TokenTracker-style big numbers.
- `<sc-for>` inside `<table>/<tbody>` is hoisted out by the HTML parser, so the rows render empty. Use a div grid with `role="table"`.
- Every helper used in `renderVals()` must be defined in its scope. One Home broke on `rgba is not defined`.

## Tools (`tools/`)

- `node tools/render-dc.mjs <artboard.dc.html> <out.png> ['{"prop":"value"}']`
  - Renders an artboard to PNG with Playwright's Chromium: it expands `{{holes}}`, `<sc-for>` and `<sc-if>` with `renderVals()`.
  - Optional env vars: `SCALE=2` and `CLIP=x,y,w,h`.
- `node tools/check-dc.mjs <artboard>` runs `renderVals()` for each theme and checks that every hole resolves.
- `python3 tools/devl.py <mono|ember|blue|iris> project/S1-Home.dc.html project/S1-Components.dc.html` writes the `K-<name>-*` devl.dev takes.
- `HTML=<out.html> node tools/render-dc.mjs …` also saves the rendered artboard as static HTML.
- `python3 tools/palettes.py <iris|graphite|emerald|ember|cobalt> S1-Home.dc.html S1-Components.dc.html` writes the `P-<name>-*` recolours.

## Restoring the canvas on another claude.ai account

Create a new canvas from the Design artifact type. Publish `project/canvas.json` with every `project/*.dc.html` to it in one call (root = this folder, `file_path` = `project/canvas.json`, `files` = the rest). `AC-Web.dc.html` points at `/_blob/` assets of the old canvas. To show its pictures, upload `web/assets/*` to the new canvas and replace those URLs.
