# Keyhop V2 — big-bang 2.0 (finální plán)

## Kontext

Keyhop (Mac app + `keyhop` CLI + keyhop.app + iOS) se má z interního nástroje stát **veřejný produkt zdarma**, jehož jádrem je nejlepší token tracker na trhu. Research konkurence (2026-10-10) ukázal, že trh se dělí na 4 tábory — CLI analyzéry (ccusage 18,9k⭐, codeburn 11,4k⭐), menu-bar měřiče (CodexBar 22,4k⭐), account switchery (claude-swap) a leaderboardy (tokscale, viberank) — a **nikdo nekombinuje všechny čtyři jako Keyhop**. Zároveň je slyšet kritika „tokenmaxxingu" (tokeny ≠ efektivita) a nedůvěra v čísla bez verifikace. V2 tuto pozici využije: spolehlivost + real-time + efektivita místo spotřeby + plochy v jednom vizuálním jazyce.

## Potvrzená rozhodnutí (grilling, 5 kol)

- **Produkt:** veřejný, zdarma navždy, žádná příprava monetizace. Úspěch = linked users + aktivní týmy.
- **Mechanika:** dlouhá větev `v2`, merge najednou (big-bang 2.0). Main dál vydává 0.14.x opravy. **Cloud roste aditivně na mainu** — D1 migrace a API zpětně kompatibilní, nasazováno průběžně; big-bang je zážitek aplikace/webu, ne deploy.
- **Harmonogram:** ~12 týdnů, milníky M1–M5 (pořadí níže).
- **Tracker (povinné osy):** spolehlivost (mezery z `reports/Mezery ve stacku Keyhop.md`) + real-time (lokálně FSEvents i živý cloud) + insights.
- **Nástroje:** parita se seznamem zdrojů ccusage všude, kde existují parsovatelné lokální logy (Amp, Droid/Factory, Goose, Qwen, Kimi, Copilot CLI, Antigravity, Grok Build…).
- **Gamifikace:** otočit k efektivitě — výchozí řazení efektivita/výsledky, divize podle plánu, anti-cheat/verifikace; raw tokeny zůstávají jako volitelná metrika. Pet zůstává na token stages (pose/markings už dnes nejsou spend).
- **Funkce z researche (vše ve scope):** subscription optimizer + chytřejší rotace; trvalá historie + multi-machine merge; efficiency coaching (optimize/compare/yield, spend per PR z lokálního gitu, `gh` jen volitelné obohacení); growth smyčky (share cards, Wrapped, Slack/Discord digesty, README widgety).
- **Živý cloud:** jen **agregáty, častěji** (à 1–2 min), pomíjivá live vrstva — trvale se dál ukládají jen denní součty; „show-data" transparentnost (příkaz + obrazovka).
- **UI:** `design/keyhop-v2/index.html` je závazný směr (tmavé/denní téma, sidebar 252 px, status bar, home s polem). Dopracovat chybějící sekce (Teams, Season, Profile, cloud Settings) a přenést jazyk na web, menu, tray, iOS.
- **Plochy V2-grade:** Mac + keyhop.app + CLI + Linux/Win tray + iOS. iOS pouze redesign, **bez publikace** (dál build ze zdrojáků).
- **Podpora:** docs + onboarding, GitHub Discussions + issue šablony + veřejná roadmapa (bez Discordu), in-app nápověda (lepší doctor, chybové stavy), více nástrojů/platforem.

## Milníky

### M1 — Tracker core — STAV k 2026-10-10: HOTOVO až na výjimky níže
Hotovo na větvi `v2` (commity 0e8263b…203f320) + main (042b2ab):
- Real-time: LogWatch (FSEvents + debounce) → UsageTracker/AccountStore, polling fallback.
- Spolehlivost: Overrides modul (přebíjející credentialy: env tokeny, apiKeyHelper, Codex keyring store, Copilot vlastní login, CURSOR_API_KEY, Gemini šifrovaný store, OPENCODE_AUTH_CONTENT) v doctor + switch + menu. Refresh-race a env-adresáře už byly ošetřené. MCP discover a e2e 0.16 už hotové dřív.
- Nové nástroje: Provider rozdělen na switchable/measured-only; feedy Qwen, Kimi (vč. legacy, počítá i session-scope — ccusage to dělá špatně), OpenClaw, Grok (per-model split, USD ticks), Goose (usage_ledger), Kilo (OpenCode schéma), Amp (přepisované JSONy, ledger join). = 13 zdrojů tokenů.
- Multi-Mac: `keyhop merge <folder>` přes synchronizovanou složku, origin sloupec, dedup přes klíče, atribuce přes identity, ochrana proti re-exportu i proti cizí atribuci přes lokální periods.
- Auto-hop: opt-in "Hop before a limit automatically" v menu; limit alert s doporučením provede hop a oznámí ho.
- Cloud (main): migrace 0013 širší CHECK daily_usage + TOOLS/TOOL_NAMES/LIMIT_TOOLS; klient filtruje upload na staré nástroje, dokud migrace není nasazená (lift po deployi!).
Vědomě odloženo: `keyhop run <account>` + mapování adresář→účet (velký design, vlastní blok); Antigravity (křehký protobuf), Droid/Hermes (jen session součty), Copilot session rollups; Codex app-server rateLimits; nové quota pooly bez vendor schémat.

### M1 — původní zadání (referenčně)
- **Spolehlivost** dle `reports/Mezery ve stacku Keyhop.md` + `research_notes/`: nové credential stores (env tokeny, keyringy, Cursor Keychain/file mode), refresh-token races, nové quota pooly (Opus limit, credits, Agent SDK pool). Dotčené: `Sources/Keyhop/Providers/*`, `Core/AccountStore.swift`.
- **Real-time lokálně:** FSEvents/DispatchSource watching JSONL adresářů místo čistého 300s pollingu (`Tracking/TrackerEngine.swift:95` ingest zůstává inkrementální; polling jako fallback). Živý ticker pro menu i okno.
- **Nové nástroje:** rozšířit `Tracking/LogFeeds.swift` + `Providers/` na paritu s ccusage (jen zdroje s lokálními logy). Každý feed dostane unit test à la stávající adapter testy.
- **Trvalá historie + multi-Mac:** `usage.sqlite` už je trvalý sklad — doplnit export/import a **merge více strojů přes synchronizovanou složku** (iCloud/Syncthing, à la MyUsage) s dedupem přes event `key`; dokumentovat, že historie přežívá 30denní mazání transkriptů.
- **Chytřejší rotace:** hop *před* limitem z forecastu (`TrackerEngine.forecast`, `Core/Recommendation.swift`), `keyhop run <account>` (účet per terminál), mapování adresář→účet.

### M2 — UI podle sketche (~3 týdny)
- Mac okno: přepsat `Dashboard/DashboardPage.swift` (3851 ř.) podle `design/keyhop-v2/index.html` — design tokeny, obě témata, všech 10 sekcí + nové (sketch zatím pokrývá Limits/Account/Usage/Budgets/Leaderboard/Settings; doplnit Teams, Season, Profile, cloud Settings). Zvážit rozpad na moduly místo jednoho souboru.
- Menu bar: volitelně **čísla přímo v textu menu baru** (častý HN požadavek), outage badge, live ticker; pet karta v Overview (oživit mrtvý `companionRow`, `DashboardPage.swift:1870`); tool-mix bar na 6 nástrojů (`DashboardPage.swift:3194` vs `cloud/src/ui.ts:713`).
- keyhop.app ve stejném jazyce: `cloud/src/ui.ts`, `landing.ts`, `pages.ts`, `marketing.ts` (aditivně na mainu — vizuální změny webu jsou kompatibilní).
- Každou novou obrazovku prohnat `checks/` harnessem a Rams quick_review.

### M3 — Sociální vrstva + živý cloud (~2 týdny)
- **Efektivita a divize:** nové metriky (tokeny/merged PR z `Tracking/GitWork.swift`, cache-hit, streak) v `cloud/src/stats.ts`, `seasons.ts`; divize podle plánu; výchozí řazení efektivita.
- **Anti-cheat:** server-side validace uploadů (token math, cost floors/stropy à la viberank) v `cloud/src/usage.ts`.
- **Živá vrstva:** nový endpoint pro minutové agregáty (pomíjivé — TTL, bez trvalého ukládání; D1 drží dál jen dny), živý team day + leaderboard. Klient: zhuštěný sync v `Cloud/Cloud.swift` (`syncIfDue`).
- **Transparentnost:** `keyhop cloud show-data` + obrazovka v Settings ukazující přesný payload.

### M4 — Optimizer, coaching, growth (~2 týdny)
- **Subscription optimizer:** využití kapacity všech plánů („platíš X, využíváš Y %") — data už v limitech; nová sekce + CLI příkaz. Nikdo na trhu to nedělá.
- **Efficiency coaching:** analogy codeburn `optimize`/`compare`/`yield` nad lokálním skladem; spend per PR z merge commitů, `gh` jen volitelné obohacení.
- **Growth:** share cards, year-end Wrapped, Slack/Discord webhook digesty pro týmy, rozšířené README widgety (`cloud/src/widgets.ts`, `card.ts`).

### M5 — Parity, podpora, launch (~2 týdny)
- Tray (Linux/Win) a iOS redesign do V2 jazyka (`Sources/KeyhopTray/`, `ios/Sources/`); iOS bez publikace.
- CLI: nové příkazy (optimizer, coaching, show-data, run), hezčí reporty; MCP server rozšířit o nové nástroje.
- Docs + onboarding: README refresh (je zastaralý — sekce dashboardu), docs sekce na keyhop.app, průvodce prvním spuštěním; GitHub Discussions + issue šablony + veřejná roadmapa; in-app nápověda (doctor, chybové stavy).
- Launch: CHANGELOG 2.0, screenshoty, landing update.

## Inženýrská kvalita (průběžně, ne jen M5)
- Zavést SwiftFormat/SwiftLint a Biome (cloud/checks/e2e), coverage měření (swift test --enable-code-coverage, vitest coverage), Dependabot i pro 3 npm lockfiles.
- Nové funkce = nové testy ve stávajících vrstvách (unit, cloud vitest, e2e, checks). Jev zůstává advisory.
- Pravidelný rebase `v2` na main (drift je hlavní riziko dlouhé větve).

## Dokumentace rozhodnutí (domain modeling)
- Založit `CONTEXT.md` — glosář: Hop, Login vs. Account, Keep, Season/Division, Pet stages, Live vrstva, Efektivita (přesná definice metriky!).
- ADRs v `docs/adr/`: 0001 big-bang na větvi v2 + aditivní cloud; 0002 efficiency-first řazení + anti-cheat; 0003 živý sync jen z agregátů (privacy).
- Aktualizovat `AGENTS.md` o V2 fakta.

## Pre-flight ověření (před M3)
- Ověřit Cloudflare plán: D1 na Workers Free tvrdě selhává od 1. 9. 2026 (flag z vlastního researche) — živá vrstva zvýší počet dotazů; spočítat dopad na placený plán.
- Ověřit, že ingest kadence spolehlivě předbíhá mazání transkriptů (údajně i po 9 dnech).

## Verifikace
- Po každém milníku: `swift test`, `cloud: npm test + typecheck`, `npm run test:e2e`, `checks/run.mjs --site --app --cli`, ruční dogfood na vlastních datech.
- M2+: Rams review nových obrazovek; screenshots v CI (menu snapshots, linux-screens, windows tray).
- Interní buildy z větve `v2` pro vlastní použití (bez veřejného release až do 2.0).

## Rizika
- 12 týdnů je ambiciózní — pořadí M1→M5 je zároveň priorita; při skluzu se řeže od konce (M4 growth, M5 tray/iOS redesign), nikdy M1.
- Dlouhá větev: drift vůči main opravám → týdenní rebase, spolehlivostní fixy cherry-pick na main.
- Živý cloud = náklady a nové API — proto agregáty-only a pomíjivost.
