import { html, raw } from "hono/html";
import type { HtmlEscapedString } from "hono/utils/html";
import { type Tool, TOOLS, TOOL_NAMES, type User, addDays } from "./env";
import { BACKDROP_SCRIPT } from "./backdrop";
import type { Metric, Totals } from "./stats";

export type Html = HtmlEscapedString | Promise<HtmlEscapedString>;

// Brand marks from Simple Icons (CC0), the same paths as Sources/Keyhop/Core/ProviderMarks.swift.
export const MARKS: Record<Tool, string> = {
  claude:
    "m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z",
  cursor:
    "M11.503.131 1.891 5.678a.84.84 0 0 0-.42.726v11.188c0 .3.162.575.42.724l9.609 5.55a1 1 0 0 0 .998 0l9.61-5.55a.84.84 0 0 0 .42-.724V6.404a.84.84 0 0 0-.42-.726L12.497.131a1.01 1.01 0 0 0-.996 0M2.657 6.338h18.55c.263 0 .43.287.297.515L12.23 22.918c-.062.107-.229.064-.229-.06V12.335a.59.59 0 0 0-.295-.51l-9.11-5.257c-.109-.063-.064-.23.061-.23",
  codex:
    "M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.142.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464zM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.872zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667zm2.0107-3.0231l-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66zM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813zm1.0976-2.3654l2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z",
};

const GITHUB =
  "M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12";

/** Keyhop's pixel mark: two rows of four squares, three lit on top and one below. */
export const PIXEL_MARK = `<svg class="pixel" viewBox="0 0 24 24" aria-hidden="true"><g fill="#EBEBEB"><rect x="2.5" y="2.5" width="6" height="19.5" rx="1.5"/><rect x="9.6" y="9.2" width="6" height="6" rx="1.5"/><rect x="16" y="1" width="6" height="6" rx="1.5"/><rect x="16" y="17" width="6" height="6" rx="1.5"/></g></svg>`;

const FAVICON =
  "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='7' fill='%23171717'/%3E%3Cg fill='%23EBEBEB'%3E%3Crect x='3.3' y='3.3' width='8' height='26' rx='2'/%3E%3Crect x='12.8' y='12.3' width='8' height='8' rx='2'/%3E%3Crect x='21.3' y='1.3' width='8' height='8' rx='2'/%3E%3Crect x='21.3' y='22.7' width='8' height='8' rx='2'/%3E%3C/g%3E%3C/svg%3E";

// The dashboard's tokens and components, so the website and the app read as one product.
const CSS = `
:root {
  --bg: hsl(0 0% 9%); --panel: hsl(0 0% 10.6%); --raised: hsl(0 0% 13.5%); --hover: hsl(0 0% 100% / .05);
  --border: hsl(0 0% 100% / .08); --border-strong: hsl(0 0% 100% / .14); --faint: hsl(0 0% 100% / .08);
  --text: hsl(0 0% 92%); --muted: hsl(0 0% 63%); --subtle: hsl(0 0% 46%); --primary: hsl(0 0% 95%); --on-primary: hsl(0 0% 9%);
  --focus: hsl(211 92% 62%); --good: #5CC98A; --warn: #E3A64F; --bad: #EE7A69;
  --sans: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI Variable Text", "Segoe UI", Roboto, Cantarell, "Noto Sans", sans-serif;
  --mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
  color-scheme: dark;
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text); font: 14px/1.5 var(--sans); -webkit-font-smoothing: antialiased; }
a { color: inherit; }
button, input { font: inherit; color: inherit; }
:focus-visible { outline: 2px solid var(--focus); outline-offset: 2px; }
.skip-link { position: fixed; left: 16px; top: 12px; z-index: 20; padding: 9px 12px; border-radius: 7px; background: var(--primary); color: var(--on-primary); text-decoration: none; transform: translateY(-160%); transition: transform .12s ease; }
.skip-link:focus { transform: translateY(0); }
.mono { font-family: var(--mono); font-size: 12.5px; }
.muted { color: var(--muted); } .subtle { color: var(--subtle); }

/* The backdrop: an illustrated scene behind the first screen, fading into the page below. Its motion
   is transform and opacity only, so it stays smooth. It scrolls away with the page. */
.backdrop { position: absolute; top: 0; left: 0; right: 0; height: 100vh; min-height: 760px; z-index: 0; overflow: hidden; pointer-events: none; }
.backdrop::after { content: ""; position: absolute; left: 0; right: 0; bottom: 0; height: 38%; background: linear-gradient(to bottom, rgba(23,23,23,0), var(--bg)); }
.top { position: relative; z-index: 1; border-bottom: 1px solid hsl(0 0% 100% / .05); background: transparent; }
.top-inner { max-width: 1080px; margin: 0 auto; height: 56px; padding: 0 24px; display: flex; align-items: center; gap: 20px; }
.brand { display: flex; align-items: center; gap: 10px; text-decoration: none; font-weight: 650; }
.pixel { width: 17px; height: 17px; flex: none; }
.nav { display: flex; gap: 2px; }
.nav a, .who .me-link { height: 32px; padding: 0 10px; border-radius: 7px; display: inline-flex; align-items: center; gap: 8px; color: var(--muted); text-decoration: none; font-weight: 520; transition: background .12s ease, color .12s ease; }
.nav a:hover, .who .me-link:hover { background: var(--hover); color: var(--text); }
.nav a[aria-current="page"] { background: hsl(0 0% 100% / .08); color: var(--text); }
.who { margin-left: auto; display: flex; align-items: center; gap: 6px; }

body { position: relative; }
main { position: relative; z-index: 1; max-width: 1080px; margin: 0 auto; padding: 32px 24px 56px; display: grid; gap: 20px; }
.head { display: flex; align-items: flex-end; justify-content: space-between; gap: 16px; flex-wrap: wrap; }
h1 { margin: 0; font-size: 22px; font-weight: 640; letter-spacing: -.01em; line-height: 1.25; }
/* A soft shadow right behind the words keeps them clear of bright dots, without a band behind them. */
.head h1, .head .lede { text-shadow: 0 1px 18px hsl(0 0% 9% / .95), 0 0 2px hsl(0 0% 9% / .8); }
.lede { margin: 4px 0 0; color: var(--muted); }
.toolbar { display: flex; gap: 8px; flex-wrap: wrap; }

.card { background: hsl(0 0% 10.6% / .8); -webkit-backdrop-filter: blur(18px) saturate(1.05); backdrop-filter: blur(18px) saturate(1.05); border: 1px solid var(--border); border-radius: 10px; min-width: 0; }
.card-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 14px 16px; border-bottom: 1px solid var(--border); }
.card-head h2 { margin: 0; font-size: 14px; font-weight: 600; }
.card-head .hint { color: var(--subtle); font-size: 12.5px; }
.card-body { padding: 16px; }
.empty { padding: 28px 16px; color: var(--muted); text-align: center; }
.split { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
.aside-layout { display: grid; grid-template-columns: minmax(0, 1fr) 320px; gap: 16px; align-items: start; }
.stack { display: grid; gap: 16px; align-content: start; }

.btn { display: inline-flex; align-items: center; justify-content: center; gap: 8px; height: 34px; padding: 0 14px; border-radius: 7px; border: 1px solid transparent;
  background: var(--primary); color: var(--on-primary); font-weight: 560; font-size: 13.5px; text-decoration: none; cursor: pointer; white-space: nowrap;
  transition: background .12s ease, border-color .12s ease, color .12s ease; }
.btn:hover { background: #fff; }
.btn.secondary { background: var(--raised); color: var(--text); border-color: var(--border); }
.btn.secondary:hover { background: hsl(0 0% 16%); border-color: var(--border-strong); }
.btn.ghost { background: transparent; color: var(--muted); }
.btn.ghost:hover { background: var(--hover); color: var(--text); }
.btn.danger { background: transparent; color: var(--bad); border-color: hsl(8 80% 67% / .35); }
.btn.danger:hover { background: hsl(8 80% 67% / .08); }
.btn.sm { height: 30px; padding: 0 10px; font-size: 13px; }
.btn svg { width: 16px; height: 16px; fill: currentColor; }

.badge { display: inline-flex; align-items: center; height: 20px; padding: 0 7px; border-radius: 6px; background: hsl(0 0% 100% / .07); color: var(--muted);
  font-size: 10.5px; font-weight: 650; letter-spacing: .03em; text-transform: uppercase; white-space: nowrap; }
.tabs { display: inline-flex; padding: 3px; gap: 2px; border-radius: 8px; background: var(--raised); border: 1px solid var(--border); }
.tabs a { height: 28px; padding: 0 11px; border-radius: 5px; display: inline-flex; align-items: center; color: var(--muted); text-decoration: none; font-size: 13px; font-weight: 540; }
.tabs a:hover { color: var(--text); }
.tabs a[aria-current="true"] { background: hsl(0 0% 100% / .1); color: var(--text); }
.field { height: 34px; width: 100%; padding: 0 10px; border-radius: 7px; border: 1px solid var(--border-strong); background: transparent; color: var(--text); }
.field:hover { border-color: hsl(0 0% 100% / .22); }
.field[readonly] { color: var(--muted); }
.form { display: grid; gap: 12px; }
.form label { display: grid; gap: 6px; font-size: 13px; color: var(--muted); font-weight: 520; }
.check { display: flex !important; grid-template-columns: none; align-items: flex-start; gap: 10px !important; color: var(--text) !important; }
.check input { margin: 3px 0 0; accent-color: hsl(0 0% 92%); width: 15px; height: 15px; flex: none; }
.check small { display: block; color: var(--muted); font-weight: 400; }
.notice { display: flex; gap: 12px; padding: 12px 14px; border: 1px solid hsl(36 72% 60% / .28); background: hsl(36 72% 60% / .06); border-radius: 10px; }
.notice b { font-weight: 600; } .notice p { margin: 2px 0 0; color: var(--muted); }
.ok { border-color: hsl(145 50% 58% / .3); background: hsl(145 50% 58% / .06); }
.error-text { color: var(--bad); margin: 0; font-size: 13px; }

.avatar { border-radius: 50%; background: var(--raised); flex: none; object-fit: cover; display: inline-grid; place-items: center; color: var(--muted); font-weight: 600; }
.person { display: flex; align-items: center; gap: 10px; min-width: 0; text-decoration: none; }
.person > span { display: grid; min-width: 0; line-height: 1.3; }
.person b { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.person small { color: var(--subtle); font-size: 12.5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
a.person:hover b { text-decoration: underline; text-underline-offset: 3px; }

.podium { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 16px; }
.place-card { padding: 16px; display: grid; gap: 14px; text-decoration: none; transition: border-color .12s ease; }
a.place-card:hover { border-color: var(--border-strong); }
.place { font-family: var(--mono); font-size: 12px; color: var(--subtle); }
.place-card .value { font-size: 26px; font-weight: 620; letter-spacing: -.01em; font-variant-numeric: tabular-nums; line-height: 1.1; }
.place-card.first .place { color: var(--text); }

.table-wrap { overflow-x: auto; }
.table { width: 100%; border-collapse: collapse; }
.table th { text-align: left; font-weight: 500; color: var(--subtle); font-size: 12.5px; padding: 10px 16px; border-bottom: 1px solid var(--border); white-space: nowrap; }
.table td { padding: 10px 16px; border-bottom: 1px solid var(--border); vertical-align: middle; }
.table tr:last-child td { border-bottom: 0; }
.table .rank { width: 52px; font-family: var(--mono); font-size: 12.5px; color: var(--subtle); }
.table .num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; color: var(--muted); }
.table .strong { color: var(--text); font-family: var(--mono); font-size: 13px; font-weight: 560; }
.table tr.me td { background: hsl(0 0% 100% / .035); }
.you { margin-left: 8px; }

.mix { display: flex; gap: 2px; width: 180px; height: 6px; border-radius: 99px; overflow: hidden; background: var(--faint); }
.mix span { min-width: 2px; }
.mix .claude, .swatch.claude { background: hsl(0 0% 100% / .9); }
.mix .cursor, .swatch.cursor { background: hsl(0 0% 100% / .55); }
.mix .codex, .swatch.codex { background: hsl(0 0% 100% / .28); }
.place-card .mix { width: 100%; }
.legend { display: flex; flex-wrap: wrap; gap: 6px 16px; list-style: none; margin: 0; padding: 0; font-size: 12.5px; color: var(--muted); }
.legend li { display: flex; align-items: center; gap: 6px; }
.swatch { width: 8px; height: 8px; border-radius: 2px; }
.mark { width: 14px; height: 14px; fill: var(--text); flex: none; }

.stats { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 16px; }
.stat { padding: 14px 16px 16px; }
.stat .label { color: var(--muted); font-size: 13px; }
.stat .value { margin-top: 6px; font-size: 24px; font-weight: 620; letter-spacing: -.01em; font-variant-numeric: tabular-nums; line-height: 1.2; }
.stat .foot { margin-top: 4px; font-size: 12.5px; color: var(--subtle); }
.profile-head { display: flex; align-items: center; gap: 18px; padding: 20px; flex-wrap: wrap; }
.profile-head .grow { flex: 1; min-width: 200px; }
.share { display: grid; gap: 6px; width: min(340px, 100%); font-size: 12.5px; color: var(--subtle); }
.heat { display: block; max-width: 100%; height: auto; }
.heat rect.l0 { fill: hsl(0 0% 100% / .05); } .heat rect.l1 { fill: hsl(0 0% 100% / .18); } .heat rect.l2 { fill: hsl(0 0% 100% / .36); }
.heat rect.l3 { fill: hsl(0 0% 100% / .6); } .heat rect.l4 { fill: hsl(0 0% 100% / .9); }
.heat text { fill: var(--subtle); font: 10.5px var(--mono); }
.tool-row { display: grid; grid-template-columns: 22px minmax(0, 1fr) 90px; gap: 10px; align-items: center; padding: 8px 0; }
.tool-row + .tool-row { border-top: 1px solid var(--border); }
.bar { height: 6px; border-radius: 99px; background: var(--faint); overflow: hidden; margin-top: 6px; }
.bar span { display: block; height: 100%; background: var(--text); border-radius: inherit; }
.kv { display: grid; grid-template-columns: 1fr auto; gap: 10px 16px; }
.kv span:nth-child(odd) { color: var(--muted); } .kv span:nth-child(even) { text-align: right; font-variant-numeric: tabular-nums; }
.list-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 12px 16px; }
.list-row + .list-row { border-top: 1px solid var(--border); }
.list-row form { margin: 0; }
.center-card { max-width: 440px; width: 100%; margin: 40px auto 0; padding: 32px 28px; display: grid; gap: 16px; text-align: center; justify-items: center; }
.center-card .pixel { width: 40px; height: 40px; }
.center-card .form { width: 100%; text-align: left; }
.code { font-family: var(--mono); font-size: 22px; letter-spacing: .12em; text-align: center; height: 48px; }

/* Tiers are told apart by their mark and their name; the tone is a quiet shift, never a colour badge. */
.tier { display: inline-flex; align-items: center; gap: 7px; font-weight: 600; font-size: 12.5px; color: var(--tier); white-space: nowrap; }
.tier .tier-mark { width: 15px; height: 12px; fill: currentColor; flex: none; }
.tier.lg { font-size: 16px; gap: 10px; }
.tier.lg .tier-mark { width: 23px; height: 18px; }
.tier-bronze { --tier: hsl(26 20% 58%); }
.tier-silver { --tier: hsl(0 0% 68%); }
.tier-gold { --tier: hsl(42 26% 66%); }
.tier-platinum { --tier: hsl(190 12% 72%); }
.tier-diamond { --tier: hsl(205 20% 80%); }
.tier-master { --tier: hsl(0 0% 95%); }
.season-head { display: flex; align-items: center; gap: 18px; padding: 18px 20px; flex-wrap: wrap; }
.season-head .grow { flex: 1; min-width: 220px; }
.season-head .next { color: var(--muted); font-size: 13px; margin: 6px 0 0; }
.ladder { display: grid; gap: 0; }
.ladder-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 10px 16px; }
.ladder-row + .ladder-row { border-top: 1px solid var(--border); }
.ladder-row.here { background: hsl(0 0% 100% / .04); }
.ladder-row .at { color: var(--subtle); font-family: var(--mono); font-size: 12.5px; }

.site-foot { position: relative; z-index: 1; max-width: 1080px; margin: 0 auto; padding: 20px 24px 40px; color: var(--subtle); font-size: 12.5px; display: flex; gap: 16px; flex-wrap: wrap; border-top: 1px solid var(--border); }
.site-foot a { color: var(--muted); text-decoration: none; } .site-foot a:hover { color: var(--text); }

/* Landing page: the product UI itself is the visual language. */
.landing .backdrop { height: 920px; min-height: 0; }
.landing .backdrop::after { height: 54%; }
.landing .top-inner, .landing .site-foot { max-width: 1180px; }
.landing .top { border-color: transparent; }
.landing-main { max-width: 1180px; padding-top: 0; padding-bottom: 0; gap: 0; overflow: hidden; }
.landing-main h1, .landing-main h2, .landing-main h3, .landing-main p { margin-top: 0; }
.landing-main h2 { margin-bottom: 0; font-size: clamp(30px, 4vw, 52px); line-height: 1.05; letter-spacing: -.045em; font-weight: 650; }
.landing-main h3 { margin-bottom: 7px; font-size: 16px; line-height: 1.3; font-weight: 620; letter-spacing: -.01em; }
.landing-main .mark { width: 18px; height: 18px; }
.landing-main .btn { height: 42px; padding: 0 18px; border-radius: 9px; }
.landing-main .btn svg { width: 15px; height: 15px; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
.landing-kicker { display: inline-flex; align-items: center; gap: 8px; margin-bottom: 20px; color: hsl(0 0% 77%); font: 11.5px/1 var(--mono); letter-spacing: .08em; text-transform: uppercase; }
.landing-kicker::before { content: ""; width: 6px; height: 6px; border-radius: 50%; background: var(--good); box-shadow: 0 0 14px hsl(145 50% 58% / .6); }
.landing-hero { min-height: 780px; padding: 120px 0 64px; display: grid; grid-template-columns: minmax(0, .82fr) minmax(520px, 1.18fr); gap: 62px; align-items: center; }
.hero-copy { position: relative; z-index: 3; padding-left: 22px; }
.hero-copy h1 { max-width: 600px; margin: 0 0 24px; font-size: clamp(50px, 6.5vw, 84px); line-height: .93; letter-spacing: -.065em; font-weight: 670; text-shadow: 0 4px 28px hsl(0 0% 9% / .75); }
.hero-copy h1 span { color: var(--muted); }
.hero-copy > p { max-width: 520px; margin-bottom: 30px; color: hsl(0 0% 71%); font-size: 18px; line-height: 1.58; text-wrap: balance; }
.hero-actions { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.hero-note { margin-top: 17px; display: flex; gap: 8px 18px; flex-wrap: wrap; color: var(--subtle); font-size: 12.5px; }
.hero-note span { display: inline-flex; align-items: center; gap: 7px; }
.hero-note span::before { content: ""; width: 3px; height: 3px; border-radius: 50%; background: var(--subtle); }
.tool-strip { margin-top: 36px; display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.tool-pill { height: 34px; padding: 0 11px; display: inline-flex; align-items: center; gap: 8px; border: 1px solid var(--border); border-radius: 8px; background: hsl(0 0% 10% / .54); color: var(--muted); font-size: 12.5px; -webkit-backdrop-filter: blur(10px); backdrop-filter: blur(10px); }
.tool-pill .mark { width: 14px; height: 14px; fill: var(--muted); }
.product-stage { position: relative; min-height: 570px; display: grid; align-items: center; perspective: 1200px; }
.product-window { width: 760px; overflow: hidden; border-radius: 14px; border: 1px solid hsl(0 0% 100% / .14); background: #151515; box-shadow: 0 40px 100px rgba(0,0,0,.46), 0 0 0 1px rgba(0,0,0,.5); transform: rotateY(-6deg) rotateX(2deg); transform-origin: 50% 50%; animation: product-in .8s cubic-bezier(.2,.8,.2,1) both, product-float 8s 1s ease-in-out infinite alternate; }
@keyframes product-in { from { opacity: 0; transform: translateY(26px) rotateY(-6deg) rotateX(2deg); } to { opacity: 1; transform: translateY(0) rotateY(-6deg) rotateX(2deg); } }
@keyframes product-float { from { translate: 0 0; } to { translate: 0 -8px; } }
.product-titlebar { height: 42px; padding: 0 14px; display: flex; align-items: center; gap: 7px; border-bottom: 1px solid var(--border); color: var(--muted); font-size: 11.5px; }
.window-dot { width: 8px; height: 8px; border-radius: 50%; background: hsl(0 0% 100% / .13); }
.product-titlebar .title { margin-left: 8px; color: hsl(0 0% 72%); font-weight: 570; }
.product-shell { display: grid; grid-template-columns: 146px 1fr; min-height: 430px; }
.product-sidebar { padding: 15px 10px; border-right: 1px solid var(--border); background: #121212; display: flex; flex-direction: column; gap: 4px; }
.product-brand { display: flex; align-items: center; gap: 8px; padding: 3px 7px 18px; font-weight: 640; }
.product-brand .pixel { width: 15px; height: 15px; }
.sidebar-link { height: 31px; padding: 0 9px; display: flex; align-items: center; gap: 9px; border-radius: 7px; color: hsl(0 0% 57%); font-size: 11.5px; font-weight: 550; }
.sidebar-link svg { width: 13px; height: 13px; fill: none; stroke: currentColor; stroke-width: 1.8; }
.sidebar-link.active { background: hsl(0 0% 100% / .09); color: var(--text); }
.sidebar-space { flex: 1; }
.sidebar-sync { padding: 10px 9px 2px; border-top: 1px solid var(--border); color: var(--subtle); font: 10px/1.5 var(--mono); }
.product-content { padding: 18px; background: #171717; }
.product-content-head { display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px; }
.product-content-head b { font-size: 15px; font-weight: 620; }
.sample-tag { padding: 3px 6px; border-radius: 5px; color: var(--warn); background: hsl(36 72% 60% / .09); font: 9px/1 var(--mono); letter-spacing: .08em; }
.mock-alert { margin-bottom: 12px; padding: 10px 12px; display: flex; gap: 9px; border-radius: 8px; border: 1px solid hsl(36 72% 60% / .25); background: hsl(36 72% 60% / .045); }
.mock-alert i { width: 6px; height: 6px; margin-top: 5px; border-radius: 50%; background: var(--warn); box-shadow: 0 0 9px hsl(36 72% 60% / .55); }
.mock-alert span { color: hsl(0 0% 72%); font-size: 10.5px; }
.mock-alert b { display: block; color: var(--text); font-size: 11.5px; font-weight: 590; }
.mock-stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 9px; margin-bottom: 11px; }
.mock-stat { padding: 10px; border: 1px solid var(--border); border-radius: 8px; background: #1b1b1b; }
.mock-stat small { display: block; color: var(--subtle); font-size: 9.5px; }
.mock-stat strong { display: block; margin-top: 4px; font-size: 17px; font-weight: 630; }
.mock-stat em { color: var(--good); font: normal 9px/1 var(--mono); }
.mock-panel { border: 1px solid var(--border); border-radius: 8px; overflow: hidden; background: #1a1a1a; }
.mock-panel-head { padding: 9px 11px; display: flex; justify-content: space-between; border-bottom: 1px solid var(--border); color: var(--subtle); font-size: 9.5px; }
.mock-panel-head b { color: var(--text); font-size: 10.5px; font-weight: 580; }
.account-line { min-height: 52px; padding: 9px 11px; display: grid; grid-template-columns: 120px 1fr 42px; gap: 12px; align-items: center; }
.account-line + .account-line { border-top: 1px solid var(--border); }
.account-name { display: flex; align-items: center; gap: 8px; min-width: 0; }
.account-name .mark { width: 13px; height: 13px; }
.account-name span { min-width: 0; display: grid; color: var(--text); font-size: 10.5px; font-weight: 580; }
.account-name small { overflow: hidden; text-overflow: ellipsis; color: var(--subtle); font-size: 8.5px; font-weight: 400; }
.limit-line { display: grid; grid-template-columns: 1fr auto; gap: 4px 8px; align-items: center; color: var(--muted); font-size: 8.5px; }
.limit-track { grid-column: 1 / -1; height: 4px; overflow: hidden; border-radius: 99px; background: hsl(0 0% 100% / .08); }
.limit-track span { display: block; height: 100%; border-radius: inherit; background: hsl(0 0% 84%); }
.limit-track span.warn { background: var(--warn); }
.limit-track span.bad { background: var(--bad); }
.account-action { color: var(--subtle); font-size: 8.5px; text-align: right; }
.tray-card { position: absolute; right: -12px; bottom: 6px; z-index: 4; width: 270px; border: 1px solid hsl(0 0% 100% / .15); border-radius: 14px; overflow: hidden; background: hsl(0 0% 9% / .96); box-shadow: 0 28px 80px rgba(0,0,0,.65); -webkit-backdrop-filter: blur(24px); backdrop-filter: blur(24px); animation: tray-in .65s .35s cubic-bezier(.2,.8,.2,1) both; }
@keyframes tray-in { from { opacity: 0; transform: translate(18px, 14px) scale(.97); } to { opacity: 1; transform: none; } }
.tray-tabs { margin: 10px; padding: 3px; display: grid; grid-template-columns: repeat(3, 1fr); gap: 3px; border: 1px solid var(--border); border-radius: 8px; background: var(--raised); }
.tray-tab { height: 28px; display: flex; align-items: center; justify-content: center; gap: 6px; border-radius: 5px; color: var(--subtle); font-size: 10px; font-weight: 580; }
.tray-tab .mark { width: 12px; height: 12px; fill: currentColor; }
.tray-tab.active { color: var(--text); background: hsl(0 0% 100% / .1); }
.tray-account { padding: 13px 14px; border-top: 1px solid var(--border); }
.tray-account-head { display: flex; align-items: start; justify-content: space-between; gap: 10px; }
.tray-account-head b { display: block; font-size: 12px; font-weight: 620; }
.tray-account-head small { color: var(--subtle); font-size: 9.5px; }
.in-use { display: inline-flex; align-items: center; gap: 5px; color: var(--muted); font: 9px/1 var(--mono); text-transform: uppercase; }
.in-use::before { content: ""; width: 6px; height: 6px; border-radius: 50%; background: var(--good); }
.tray-limits { margin-top: 12px; display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px; }
.tray-limit { color: var(--muted); font-size: 9.5px; }
.tray-limit b { float: right; color: var(--text); }
.tray-limit .limit-track { margin-top: 5px; }
.tray-switch { display: flex; align-items: center; justify-content: space-between; }
.tray-switch span { color: var(--subtle); font-size: 9.5px; }
.landing-section { padding: 118px 22px; border-top: 1px solid var(--border); }
.section-heading { max-width: 680px; margin-bottom: 54px; }
.section-heading p { max-width: 570px; margin: 18px 0 0; color: var(--muted); font-size: 16px; line-height: 1.65; }
.feature-grid { display: grid; grid-template-columns: repeat(12, 1fr); gap: 14px; }
.feature-card { position: relative; min-height: 310px; padding: 26px; overflow: hidden; border: 1px solid var(--border); border-radius: 12px; background: hsl(0 0% 10.6% / .74); -webkit-backdrop-filter: blur(18px); backdrop-filter: blur(18px); }
.feature-card:nth-child(1), .feature-card:nth-child(4) { grid-column: span 7; }
.feature-card:nth-child(2), .feature-card:nth-child(3) { grid-column: span 5; }
.feature-card > p { max-width: 390px; color: var(--muted); font-size: 13.5px; }
.feature-label { margin-bottom: 20px; color: var(--subtle); font: 10px/1 var(--mono); letter-spacing: .08em; text-transform: uppercase; }
.feature-visual { position: absolute; left: 26px; right: 26px; bottom: 24px; height: 132px; }
.switch-visual { display: grid; gap: 8px; }
.switch-row { height: 52px; padding: 0 14px; display: flex; align-items: center; gap: 10px; border: 1px solid var(--border); border-radius: 9px; background: var(--panel); }
.switch-row .mark { width: 15px; height: 15px; }
.switch-row span { display: grid; font-size: 11.5px; font-weight: 580; }
.switch-row small { color: var(--subtle); font-size: 9.5px; font-weight: 400; }
.switch-row em { margin-left: auto; color: var(--good); font: normal 9px/1 var(--mono); text-transform: uppercase; }
.switch-row:last-child { translate: 42px 0; border-color: var(--border-strong); }
.limits-visual { display: grid; align-content: end; gap: 16px; }
.big-limit { display: grid; grid-template-columns: 1fr auto; gap: 7px; color: var(--muted); font-size: 10.5px; }
.big-limit b { color: var(--text); }
.big-limit .limit-track { grid-column: 1 / -1; height: 7px; }
.chart-visual { display: flex; align-items: end; gap: 8px; border-bottom: 1px solid var(--border-strong); }
.chart-visual i { flex: 1; min-width: 12px; height: var(--h); display: block; border-radius: 4px 4px 0 0; background: hsl(0 0% 100% / .14); }
.chart-visual i:nth-child(3n+1) { background: hsl(0 0% 100% / .78); }
.chart-visual i:nth-child(3n+2) { background: hsl(0 0% 100% / .42); }
.privacy-visual { display: grid; grid-template-columns: repeat(8, 1fr); gap: 7px; align-content: end; }
.privacy-visual i { aspect-ratio: 1; border: 1px solid var(--border); border-radius: 5px; background: hsl(0 0% 100% / .025); }
.privacy-visual i:nth-child(2), .privacy-visual i:nth-child(11), .privacy-visual i:nth-child(20), .privacy-visual i:nth-child(29) { background: hsl(145 50% 58% / .65); box-shadow: 0 0 14px hsl(145 50% 58% / .14); }
.workflow { display: grid; grid-template-columns: repeat(3, 1fr); border-top: 1px solid var(--border); border-bottom: 1px solid var(--border); }
.workflow-step { position: relative; padding: 36px 32px 42px; }
.workflow-step + .workflow-step { border-left: 1px solid var(--border); }
.workflow-number { margin-bottom: 48px; color: var(--subtle); font: 11px/1 var(--mono); }
.workflow-step p { margin-bottom: 0; color: var(--muted); }
.privacy-panel { min-height: 500px; padding: 66px; display: grid; grid-template-columns: 1fr 1fr; gap: 80px; align-items: center; overflow: hidden; border: 1px solid var(--border); border-radius: 14px; background: radial-gradient(90% 130% at 100% 0%, hsl(28 22% 16%) 0%, transparent 60%), var(--panel); }
.privacy-panel h2 { max-width: 540px; }
.privacy-panel h2 span { color: var(--muted); }
.privacy-copy > p { margin: 22px 0 0; max-width: 500px; color: var(--muted); font-size: 15px; line-height: 1.7; }
.privacy-list { display: grid; gap: 0; border-top: 1px solid var(--border); }
.privacy-item { padding: 19px 0; display: grid; grid-template-columns: 26px 1fr; gap: 14px; border-bottom: 1px solid var(--border); }
.privacy-item svg { width: 18px; height: 18px; fill: none; stroke: hsl(0 0% 76%); stroke-width: 1.6; }
.privacy-item b { display: block; margin-bottom: 3px; font-size: 13px; font-weight: 600; }
.privacy-item span { color: var(--muted); font-size: 12.5px; }
.install-panel { display: grid; grid-template-columns: .8fr 1.2fr; gap: 70px; align-items: center; }
.install-copy p { margin: 20px 0 28px; color: var(--muted); font-size: 15px; line-height: 1.65; }
.platforms { display: flex; gap: 7px; flex-wrap: wrap; }
.platform { padding: 5px 8px; border: 1px solid var(--border); border-radius: 6px; color: var(--muted); font: 10px/1 var(--mono); }
.install-terminal { overflow: hidden; border: 1px solid var(--border-strong); border-radius: 12px; background: #111; box-shadow: 0 28px 70px rgba(0,0,0,.28); }
.terminal-head { height: 42px; padding: 0 14px; display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid var(--border); color: var(--subtle); font: 10px/1 var(--mono); }
.terminal-body { min-height: 190px; padding: 28px; display: grid; align-content: center; gap: 26px; font: 12px/1.65 var(--mono); color: hsl(0 0% 74%); }
.terminal-line { display: grid; grid-template-columns: 14px 1fr; gap: 9px; }
.terminal-line span { color: var(--good); }
.terminal-body .comment { color: var(--subtle); }
.closing { padding: 110px 22px 120px; text-align: center; border-top: 1px solid var(--border); }
.closing .pixel { width: 44px; height: 44px; margin-bottom: 26px; }
.closing h2 { max-width: 700px; margin: 0 auto 18px; }
.closing p { max-width: 560px; margin: 0 auto 30px; color: var(--muted); font-size: 16px; }
.closing-actions { display: flex; justify-content: center; gap: 10px; flex-wrap: wrap; }
.community-panel { min-height: 370px; padding: 52px; display: grid; grid-template-columns: minmax(0, 1fr) 420px; gap: 70px; align-items: center; border: 1px solid var(--border); border-radius: 14px; background: var(--panel); }
.community-copy p { max-width: 520px; margin: 20px 0 28px; color: var(--muted); font-size: 15px; line-height: 1.65; }
.mini-board { overflow: hidden; border: 1px solid var(--border); border-radius: 10px; background: #171717; }
.mini-board-head, .mini-board-row { display: grid; grid-template-columns: 34px 1fr auto; gap: 12px; align-items: center; padding: 13px 15px; }
.mini-board-head { border-bottom: 1px solid var(--border); color: var(--subtle); font: 10px/1 var(--mono); text-transform: uppercase; }
.mini-board-row + .mini-board-row { border-top: 1px solid var(--border); }
.mini-rank { color: var(--subtle); font: 11px/1 var(--mono); }
.mini-person { display: flex; align-items: center; gap: 9px; font-size: 12px; font-weight: 580; }
.mini-avatar { width: 25px; height: 25px; display: grid; place-items: center; border-radius: 50%; background: var(--raised); color: var(--muted); font-size: 9px; }
.mini-total { font: 11px/1 var(--mono); }
.roadmap-heading { margin-bottom: 52px; display: grid; grid-template-columns: minmax(0, 1.15fr) minmax(300px, .85fr); gap: 70px; align-items: end; }
.roadmap-heading h2 { max-width: 680px; }
.roadmap-heading > p { max-width: 500px; margin: 0 0 4px; color: var(--muted); font-size: 15px; line-height: 1.7; }
.future-grid { display: grid; grid-template-columns: repeat(12, minmax(0, 1fr)); gap: 12px; }
.future-card { min-height: 390px; padding: 30px; display: flex; flex-direction: column; overflow: hidden; border: 1px solid var(--border); border-radius: 13px; background: hsl(0 0% 10.5% / .86); }
.future-card:nth-child(1), .future-card:nth-child(4) { grid-column: span 7; }
.future-card:nth-child(2), .future-card:nth-child(3) { grid-column: span 5; }
.future-ai { background: radial-gradient(100% 110% at 100% 100%, hsl(145 24% 15%) 0%, transparent 56%), hsl(0 0% 10.5% / .92); }
.future-mcp { background: radial-gradient(100% 100% at 100% 0%, hsl(250 18% 16%) 0%, transparent 58%), hsl(0 0% 10.5% / .92); }
.future-mobile { background: radial-gradient(100% 100% at 0% 100%, hsl(205 16% 15%) 0%, transparent 58%), hsl(0 0% 10.5% / .92); }
.future-extend { background: radial-gradient(100% 100% at 100% 100%, hsl(28 18% 15%) 0%, transparent 58%), hsl(0 0% 10.5% / .92); }
.future-label { margin-bottom: 25px; display: flex; align-items: center; justify-content: space-between; gap: 12px; color: var(--subtle); font: 10px/1 var(--mono); letter-spacing: .06em; text-transform: uppercase; }
.future-label em { padding: 5px 7px; border: 1px solid var(--border); border-radius: 999px; color: var(--muted); font-style: normal; letter-spacing: .03em; }
.future-card h3 { max-width: 530px; margin-bottom: 12px; font-size: 22px; line-height: 1.18; letter-spacing: -.025em; }
.future-card > p { max-width: 550px; margin-bottom: 28px; color: var(--muted); font-size: 13.5px; line-height: 1.65; }
.future-preview { min-height: 112px; margin-top: auto; padding: 16px; border: 1px solid var(--border); border-radius: 10px; background: hsl(0 0% 6% / .58); box-shadow: inset 0 1px hsl(0 0% 100% / .025); }
.route-preview { display: grid; gap: 8px; }
.route-preview div { padding: 11px 12px; display: grid; grid-template-columns: 1fr auto; gap: 4px 12px; border-radius: 7px; background: hsl(0 0% 100% / .035); }
.route-preview span { grid-column: 1 / -1; color: var(--subtle); font: 9px/1 var(--mono); text-transform: uppercase; }
.route-preview b { font-size: 11.5px; font-weight: 580; }
.route-preview em { color: var(--good); font: normal 10px/1 var(--mono); }
.mcp-preview { display: grid; align-content: center; gap: 10px; font-family: var(--mono); }
.mcp-preview span { color: var(--subtle); font-size: 9px; text-transform: uppercase; }
.mcp-preview code { color: hsl(0 0% 77%); font-size: 11px; }
.mcp-preview b { color: var(--good); font-size: 10px; font-weight: 500; }
.phone-preview { width: 210px; min-height: 148px; margin-left: auto; margin-right: auto; padding: 12px 13px; border-radius: 22px 22px 10px 10px; }
.phone-top { display: flex; align-items: center; justify-content: space-between; color: var(--subtle); font: 8px/1 var(--mono); }
.phone-top i { width: 46px; height: 9px; border-radius: 999px; background: #070707; }
.phone-alert { margin-top: 22px; display: grid; gap: 6px; }
.phone-alert span { color: var(--subtle); font-size: 9px; }
.phone-alert b { font-size: 11.5px; font-weight: 580; }
.phone-meter { height: 5px; margin-top: 15px; overflow: hidden; border-radius: 999px; background: var(--raised); }
.phone-meter span { width: 72%; height: 100%; display: block; border-radius: inherit; background: hsl(205 24% 70%); }
.rules-preview { display: grid; align-content: center; gap: 12px; color: var(--subtle); font: 9.5px/1.35 var(--mono); }
.rules-preview b { color: hsl(0 0% 76%); font-weight: 500; }
.rules-preview div { padding-top: 3px; display: flex; gap: 6px; flex-wrap: wrap; }
.rules-preview i { padding: 5px 7px; border: 1px solid var(--border); border-radius: 5px; color: var(--muted); font-style: normal; }
.roadmap-invite { margin-top: 12px; padding: 24px 28px; display: flex; align-items: center; justify-content: space-between; gap: 24px; border: 1px dashed var(--border-strong); border-radius: 12px; }
.roadmap-invite > div { display: grid; gap: 4px; }
.roadmap-invite b { font-size: 14px; font-weight: 610; }
.roadmap-invite span { color: var(--muted); font-size: 12.5px; }
.faq-list { max-width: 860px; margin-left: auto; border-top: 1px solid var(--border); }
.faq-list details { border-bottom: 1px solid var(--border); }
.faq-list summary { min-height: 66px; display: flex; align-items: center; justify-content: space-between; gap: 20px; list-style: none; cursor: pointer; font-size: 15px; font-weight: 580; }
.faq-list summary::-webkit-details-marker { display: none; }
.faq-list summary::after { content: "+"; color: var(--subtle); font: 18px/1 var(--mono); }
.faq-list details[open] summary::after { content: "−"; }
.faq-list details p { max-width: 700px; margin: -4px 0 24px; color: var(--muted); line-height: 1.7; }

/* Public supporting pages share the landing page's quiet editorial system. */
.marketing .backdrop { height: 620px; min-height: 0; opacity: .55; }
.marketing .backdrop::after { height: 65%; }
.marketing .top-inner, .marketing .site-foot { max-width: 1080px; }
.marketing-main { max-width: 1080px; padding: 0 24px 90px; display: block; }
.marketing-page { position: relative; }
.page-hero { max-width: 820px; min-height: 440px; padding: 118px 0 92px; display: flex; flex-direction: column; justify-content: center; }
.page-hero h1 { max-width: 780px; margin: 0; font-size: clamp(48px, 7vw, 78px); line-height: .96; letter-spacing: -.06em; font-weight: 660; text-shadow: 0 3px 28px hsl(0 0% 9% / .78); }
.page-hero > p { max-width: 680px; margin: 26px 0 0; color: hsl(0 0% 69%); font-size: 17px; line-height: 1.65; text-wrap: balance; }
.platform-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; padding-bottom: 90px; }
.platform-card { min-height: 350px; padding: 28px; display: flex; flex-direction: column; border: 1px solid var(--border); border-radius: 12px; background: hsl(0 0% 10.6% / .86); -webkit-backdrop-filter: blur(18px); backdrop-filter: blur(18px); }
.platform-card.featured { grid-column: 1 / -1; min-height: 330px; }
.platform-head { display: flex; align-items: center; gap: 15px; }
.platform-head h2 { margin: 0; font-size: 22px; font-weight: 630; letter-spacing: -.025em; }
.platform-head p { margin: 3px 0 0; color: var(--subtle); font-size: 12.5px; }
.platform-mark { width: 42px; height: 42px; display: grid; place-items: center; border: 1px solid var(--border-strong); border-radius: 10px; background: var(--raised); color: var(--text); font: 18px/1 var(--mono); }
.platform-card > p { max-width: 610px; margin: 22px 0; color: var(--muted); }
.platform-card code, .legal-content code, .prose code { color: hsl(0 0% 76%); font-family: var(--mono); font-size: .9em; }
.command-block { margin-top: 28px; padding: 15px 17px; display: grid; gap: 8px; overflow-x: auto; border: 1px solid var(--border); border-radius: 9px; background: #111; }
.command-block span { color: var(--subtle); font: 9.5px/1 var(--mono); text-transform: uppercase; letter-spacing: .08em; }
.command-block code { color: hsl(0 0% 76%); font: 11.5px/1.55 var(--mono); white-space: nowrap; }
.platform-actions { margin-top: auto; display: flex; align-items: center; gap: 14px; flex-wrap: wrap; }
.platform-actions > a:not(.btn) { color: var(--muted); font-size: 12.5px; text-underline-offset: 3px; }
.content-split { padding: 74px 0; display: grid; grid-template-columns: .75fr 1.25fr; gap: 90px; border-top: 1px solid var(--border); }
.content-split h2 { max-width: 390px; margin: 12px 0 0; font-size: clamp(28px, 4vw, 44px); line-height: 1.08; letter-spacing: -.04em; font-weight: 640; }
.section-index { color: var(--subtle); font: 10px/1 var(--mono); letter-spacing: .08em; }
.prose { color: var(--muted); font-size: 15px; line-height: 1.75; }
.prose p { margin: 0; }
.prose p + p { margin-top: 18px; }
.prose a, .legal-content a { color: var(--text); text-underline-offset: 3px; }
.page-cta { margin-top: 70px; padding: 28px; display: flex; align-items: center; justify-content: space-between; gap: 24px; border: 1px solid var(--border-strong); border-radius: 12px; background: var(--raised); }
.page-cta div { display: grid; gap: 3px; }
.page-cta b { font-size: 15px; font-weight: 610; }
.page-cta span { color: var(--muted); font-size: 13px; }
.legal-layout { padding-bottom: 40px; display: grid; grid-template-columns: 220px minmax(0, 1fr); gap: 86px; align-items: start; }
.legal-nav { position: sticky; top: 28px; display: grid; gap: 4px; }
.legal-nav span { margin-bottom: 10px; color: var(--subtle); font: 10px/1 var(--mono); text-transform: uppercase; letter-spacing: .08em; }
.legal-nav a { padding: 7px 0; color: var(--muted); text-decoration: none; font-size: 12.5px; }
.legal-nav a:hover { color: var(--text); }
.legal-content { min-width: 0; }
.legal-content section { padding: 0 0 62px; scroll-margin-top: 24px; }
.legal-content section + section { padding-top: 62px; border-top: 1px solid var(--border); }
.legal-content h2 { margin: 12px 0 20px; font-size: clamp(26px, 4vw, 40px); line-height: 1.1; letter-spacing: -.035em; font-weight: 640; }
.legal-content p, .legal-content li { color: var(--muted); font-size: 14.5px; line-height: 1.75; }
.legal-content p { margin: 0; }
.legal-content p + p { margin-top: 17px; }
.legal-content ul { margin: 0; padding-left: 20px; display: grid; gap: 12px; }
.legal-content li::marker { color: var(--subtle); }
.legal-content li b { color: var(--text); font-weight: 590; }
.updated { padding-top: 8px; color: var(--subtle) !important; font: 11px/1.5 var(--mono) !important; }
.security-report { min-height: 280px; margin-bottom: 88px; padding: 46px; display: flex; align-items: center; justify-content: space-between; gap: 50px; border: 1px solid hsl(145 50% 58% / .22); border-radius: 14px; background: radial-gradient(90% 160% at 100% 0%, hsl(145 24% 16%) 0%, transparent 62%), var(--panel); }
.security-report h2 { max-width: 600px; margin: 0 0 13px; font-size: clamp(28px, 4vw, 42px); line-height: 1.06; letter-spacing: -.04em; }
.security-report p { max-width: 620px; margin: 0; color: var(--muted); line-height: 1.7; }

@media (max-width: 860px) {
  .podium, .split, .aside-layout { grid-template-columns: 1fr; }
  .stats { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .hide-sm { display: none; }
  .top-inner { gap: 10px; padding: 0 16px; }
  main { padding: 24px 16px 48px; }
  .landing-main { padding: 0 16px; }
  .landing .top-inner, .marketing .top-inner { padding: 0 16px; }
  .landing .nav a[href="#product"] { display: none; }
  .landing-hero { min-height: auto; padding: 92px 0 72px; grid-template-columns: 1fr; gap: 54px; }
  .hero-copy { padding-left: 0; text-align: center; }
  .hero-copy h1, .hero-copy > p { margin-left: auto; margin-right: auto; }
  .hero-actions, .hero-note, .tool-strip { justify-content: center; }
  .product-stage { min-height: 500px; width: min(700px, calc(100vw - 16px)); justify-self: center; }
  .product-window { width: 700px; transform: scale(.9); }
  .tray-card { right: 0; }
  .landing-section { padding: 88px 0; }
  .feature-card:nth-child(n) { grid-column: span 6; }
  .privacy-panel { padding: 44px; grid-template-columns: 1fr; gap: 50px; }
  .install-panel { grid-template-columns: 1fr; gap: 44px; }
  .community-panel { padding: 42px; grid-template-columns: 1fr; gap: 44px; }
  .roadmap-heading { grid-template-columns: 1fr; gap: 24px; }
  .future-card:nth-child(n) { grid-column: span 6; }
  .closing { padding-left: 0; padding-right: 0; }
  .marketing-main { padding-left: 16px; padding-right: 16px; }
  .platform-grid { grid-template-columns: 1fr; }
  .platform-card.featured { grid-column: auto; }
  .content-split { grid-template-columns: 1fr; gap: 32px; }
  .legal-layout { grid-template-columns: 1fr; gap: 48px; }
  .legal-nav { position: static; grid-template-columns: repeat(3, auto); justify-content: start; }
  .legal-nav span { grid-column: 1 / -1; }
  .security-report { align-items: flex-start; flex-direction: column; }
}
@media (max-width: 600px) {
  .landing .nav, .marketing .nav { display: none; }
  .landing-hero { padding-top: 74px; }
  .hero-copy h1 { font-size: clamp(48px, 15vw, 68px); }
  .hero-copy > p { font-size: 16px; }
  .product-stage { min-height: 390px; }
  .product-window { width: 600px; transform: translateX(-25px) scale(.66); transform-origin: 50% 50%; animation: none; }
  .tray-card { width: 236px; right: 2px; bottom: 0; }
  .feature-grid { grid-template-columns: 1fr; }
  .feature-card:nth-child(n) { grid-column: 1; min-height: 290px; }
  .workflow { grid-template-columns: 1fr; }
  .workflow-step { padding: 28px 4px 30px; }
  .workflow-step + .workflow-step { border-left: 0; border-top: 1px solid var(--border); }
  .workflow-number { margin-bottom: 24px; }
  .privacy-panel { padding: 34px 24px; }
  .community-panel { padding: 34px 24px; }
  .future-grid { grid-template-columns: 1fr; }
  .future-card:nth-child(n) { grid-column: 1; min-height: 360px; padding: 26px 22px; }
  .roadmap-invite { align-items: stretch; flex-direction: column; padding: 24px 22px; }
  .roadmap-invite .btn { width: 100%; }
  .mini-board { margin: 0 -10px; }
  .terminal-body { padding: 22px 18px; font-size: 10.5px; overflow-wrap: anywhere; }
  .landing .site-foot, .marketing .site-foot { padding-left: 16px; padding-right: 16px; }
  .page-hero { min-height: 390px; padding: 88px 0 70px; }
  .page-hero h1 { font-size: clamp(44px, 14vw, 62px); }
  .platform-card, .security-report { padding: 26px 22px; }
  .platform-actions { align-items: stretch; flex-direction: column; }
  .platform-actions .btn { width: 100%; }
  .content-split { padding: 58px 0; }
  .page-cta { align-items: stretch; flex-direction: column; }
  .legal-nav { grid-template-columns: repeat(2, auto); }
}
@media (prefers-reduced-motion: reduce) { * { transition: none !important; animation: none !important; } }
`;

export function layout(options: {
  title: string;
  description?: string;
  path: string;
  user: User | null;
  active?: "leaderboard" | "teams" | "season";
  mode?: "app" | "landing" | "marketing";
  index?: boolean;
  softwareSchema?: boolean;
  canonicalPath?: string;
  body: Html;
  nonce: string;
}): Html {
  const description = options.description ?? "Keyhop leaderboards: who uses the most Claude Code, Cursor and Codex.";
  const current = (name: string) => (options.active === name ? raw('aria-current="page"') : "");
  const user = options.user;
  const mode = options.mode ?? "app";
  const publicSite = mode !== "app";
  const scene = mode === "landing" ? "orbit" : "leaves";
  const sceneOpacity = mode === "landing" ? 0.74 : mode === "marketing" ? 0.58 : 0.85;
  const robots = options.index === false ? "noindex, nofollow" : "index, follow, max-image-preview:large";
  const canonicalPath = options.canonicalPath ?? options.path.split("?")[0];
  const canonical = `https://keyhop.app${canonicalPath}`;
  const socialImage = "https://raw.githubusercontent.com/dominikzabcik/keyhop/main/docs/banner.png";
  const schema = options.softwareSchema
    ? JSON.stringify({
        "@context": "https://schema.org",
        "@type": "SoftwareApplication",
        name: "Keyhop",
        description,
        url: "https://keyhop.app/",
        downloadUrl: "https://keyhop.app/download",
        applicationCategory: "DeveloperApplication",
        operatingSystem: "macOS 14 or later, Linux, Windows 10 or later",
        isAccessibleForFree: true,
        license: "https://github.com/dominikzabcik/keyhop/blob/main/LICENSE",
        sameAs: "https://github.com/dominikzabcik/keyhop",
        offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
      }).replace(/</g, "\\u003c")
    : null;
  return html`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark">
<meta name="theme-color" content="#171717">
<meta name="robots" content="${robots}">
<title>${options.title}</title>
<meta name="description" content="${description}">
<link rel="canonical" href="${canonical}">
<meta property="og:site_name" content="Keyhop">
<meta property="og:type" content="website">
<meta property="og:locale" content="en_US">
<meta property="og:title" content="${options.title}">
<meta property="og:description" content="${description}">
<meta property="og:url" content="${canonical}">
<meta property="og:image" content="${socialImage}">
<meta property="og:image:type" content="image/png">
<meta property="og:image:width" content="2560">
<meta property="og:image:height" content="840">
<meta property="og:image:alt" content="Keyhop logo on a dark background">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${options.title}">
<meta name="twitter:description" content="${description}">
<meta name="twitter:image" content="${socialImage}">
<meta name="twitter:image:alt" content="Keyhop logo on a dark background">
<link rel="icon" href="${raw(FAVICON)}">
<style>${raw(CSS)}</style>
${schema ? html`<script type="application/ld+json" nonce="${options.nonce}">${raw(schema)}</script>` : ""}
</head>
<body class="${mode}">
<a class="skip-link" href="#main-content">Skip to content</a>
<div class="backdrop" aria-hidden="true"></div>
<header class="top"><div class="top-inner">
  <a class="brand" href="/">${raw(PIXEL_MARK)}Keyhop</a>
  ${publicSite
    ? html`<nav class="nav" aria-label="Main">
        <a href="${mode === "landing" ? "#product" : "/#product"}">Product</a>
        <a href="${mode === "landing" ? "#roadmap" : "/#roadmap"}">Roadmap</a>
        <a href="/leaderboard">Leaderboard</a>
        <a href="/privacy">Privacy</a>
        <a href="https://github.com/dominikzabcik/keyhop">GitHub</a>
      </nav>
      <div class="who"><a class="btn sm" href="/download">Get Keyhop</a></div>`
    : html`<nav class="nav" aria-label="Main">
        <a href="/leaderboard" ${current("leaderboard")}>Leaderboard</a>
        <a href="/season" ${current("season")}>Season</a>
        ${user ? html`<a href="/teams" ${current("teams")}>Teams</a>` : ""}
      </nav>
      <div class="who">
        ${user
          ? html`<a class="me-link" href="/u/${user.login}">${avatar(user, 24)}<span class="hide-sm">${user.login}</span></a>
              <a class="btn ghost sm" href="/settings">Settings</a>`
          : html`<a class="btn sm" href="/login?next=${encodeURIComponent(options.path)}">${githubIcon()}Sign in with GitHub</a>`}
      </div>`}
</div></header>
<main id="main-content" class="${mode === "landing" ? "landing-main" : mode === "marketing" ? "marketing-main" : ""}">${options.body}</main>
<footer class="site-foot">
  <span>Keyhop</span>
  <span>${publicSite ? "Free, open source and built for the tools you already use." : "Totals are sent by the Keyhop app: tokens, API value and requests per day. Nothing else."}</span>
  <a href="/download">Download</a>
  <a href="/privacy">Privacy</a>
  <a href="/terms">Terms</a>
  <a href="/security">Security</a>
  <a href="https://github.com/dominikzabcik/keyhop">GitHub</a>
</footer>
<script nonce="${options.nonce}">${raw(BACKDROP_SCRIPT)}
(function () {
  var host = document.querySelector(".backdrop");
  if (!host || !window.KeyhopBackdrop) return;
  window.KeyhopBackdrop.mount(host, { scene: "${scene}", opacity: ${sceneOpacity} });
})();
</script>
</body>
</html>`;
}

/** How many of the six steps a tier has climbed. */
const TIER_STEPS: Record<string, number> = { bronze: 1, silver: 2, gold: 3, platinum: 4, diamond: 5, master: 6 };

/**
 * A tier's mark: six squares climbing to the right, in the same pixel language as Keyhop's own,
 * with the steps this tier has reached lit.
 */
export function tierMark(key: string): Html {
  const lit = TIER_STEPS[key] ?? 1;
  const steps = Array.from({ length: 6 }, (_, index) => {
    const height = 3 + index * 2.4;
    return `<rect x="${index * 4}" y="${(17 - height).toFixed(1)}" width="3" height="${height.toFixed(1)}" rx="1" fill-opacity="${index < lit ? 1 : 0.22}"/>`;
  }).join("");
  return html`${raw(`<svg class="tier-mark" viewBox="0 0 23 18" aria-hidden="true">${steps}</svg>`)}`;
}

/** A tier, written out with its mark. */
export function tierTag(tier: { key: string; name: string; division: number | null }, size: "sm" | "lg" = "sm"): Html {
  const roman = ["", "I", "II", "III"][tier.division ?? 0];
  return html`<span class="tier tier-${tier.key}${size === "lg" ? " lg" : ""}">${tierMark(tier.key)}<span>${tier.name}${roman ? ` ${roman}` : ""}</span></span>`;
}

export function githubIcon(): Html {
  return html`<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${GITHUB}"/></svg>`;
}

export function mark(tool: Tool): Html {
  return html`<svg class="mark" viewBox="0 0 24 24" aria-hidden="true"><path d="${MARKS[tool]}"/></svg>`;
}

export function avatar(person: { login: string; avatar_url?: string | null; avatarUrl?: string | null }, size: number): Html {
  const url = person.avatar_url ?? person.avatarUrl;
  if (url) {
    const sized = url.includes("?") ? `${url}&s=${size * 2}` : `${url}?s=${size * 2}`;
    return html`<img class="avatar" src="${sized}" width="${size}" height="${size}" alt="">`;
  }
  return html`<span class="avatar" style="width:${size}px;height:${size}px;font-size:${Math.round(size * 0.42)}px" aria-hidden="true">${person.login.slice(0, 1).toUpperCase()}</span>`;
}

export function tokens(value: number): string {
  const size = Math.abs(value);
  const trim = (x: number, suffix: string) => {
    const text = x >= 100 ? x.toFixed(0) : x.toFixed(1);
    return (text.endsWith(".0") ? text.slice(0, -2) : text) + suffix;
  };
  if (size >= 1e9) return trim(value / 1e9, "B");
  if (size >= 1e6) return trim(value / 1e6, "M");
  if (size >= 1e3) return trim(value / 1e3, "K");
  return String(Math.round(value));
}

export function usd(micros: number): string {
  const dollars = micros / 1_000_000;
  return dollars >= 1000 ? `$${Math.round(dollars).toLocaleString("en-US")}` : `$${dollars.toFixed(2)}`;
}

export const count = (value: number): string => Math.round(value).toLocaleString("en-US");

export function metricValue(totals: { tokens: number; costMicros: number; requests: number }, metric: Metric): string {
  if (metric === "cost") return usd(totals.costMicros);
  if (metric === "requests") return count(totals.requests);
  return tokens(totals.tokens);
}

export function mixBar(tools: Record<Tool, number>): Html {
  const total = TOOLS.reduce((sum, tool) => sum + tools[tool], 0);
  const title = TOOLS.filter((tool) => tools[tool] > 0)
    .map((tool) => `${TOOL_NAMES[tool]} ${tokens(tools[tool])}`)
    .join(", ");
  return html`<span class="mix" title="${title || "No tokens"}">${
    total > 0
      ? TOOLS.filter((tool) => tools[tool] > 0).map((tool) => html`<span class="${tool}" style="width:${((tools[tool] / total) * 100).toFixed(2)}%"></span>`)
      : ""
  }</span>`;
}

export function legend(): Html {
  return html`<ul class="legend">${TOOLS.map((tool) => html`<li><i class="swatch ${tool}"></i>${TOOL_NAMES[tool]}</li>`)}</ul>`;
}

export function toolRows(totals: Totals): Html {
  const max = Math.max(1, ...TOOLS.map((tool) => totals.tools[tool]));
  return html`${TOOLS.map(
    (tool) => html`<div class="tool-row">${mark(tool)}<div><div>${TOOL_NAMES[tool]}</div><div class="bar"><span style="width:${((totals.tools[tool] / max) * 100).toFixed(2)}%"></span></div></div><span class="mono" style="text-align:right">${tokens(totals.tools[tool])}</span></div>`,
  )}`;
}

const HEAT_WEEKS = 53;

/** A year of days, Monday at the top, shaded by quartile of the active days. Drawn at its real size. */
export function heatmap(days: { day: string; tokens: number }[], reference: string): Html {
  const byDay = new Map(days.map((entry) => [entry.day, entry.tokens]));
  const weekday = (new Date(`${reference}T00:00:00Z`).getUTCDay() + 6) % 7;
  const start = addDays(reference, -((HEAT_WEEKS - 1) * 7 + weekday));
  const values = days.map((entry) => entry.tokens).filter((value) => value > 0).sort((a, b) => a - b);
  const quantile = (q: number) => values[Math.min(values.length - 1, Math.floor(q * values.length))] ?? 0;
  const [q1, q2, q3] = [quantile(0.25), quantile(0.5), quantile(0.75)];
  const level = (value: number) => (value <= 0 ? 0 : value <= q1 ? 1 : value <= q2 ? 2 : value <= q3 ? 3 : 4);
  const cell = 14;
  const step = 18;
  const top = 20;
  const monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const parts: string[] = [];
  let lastMonth = -1;
  for (let column = 0; column < HEAT_WEEKS; column++) {
    const first = addDays(start, column * 7);
    const month = Number(first.slice(5, 7)) - 1;
    // A label needs about two columns of room, so none squeezes in at the right edge.
    if (month !== lastMonth && column < HEAT_WEEKS - 2) {
      parts.push(`<text x="${column * step}" y="11">${monthNames[month]}</text>`);
      lastMonth = month;
    }
    for (let row = 0; row < 7; row++) {
      const day = addDays(start, column * 7 + row);
      if (day > reference) continue;
      const value = byDay.get(day) ?? 0;
      parts.push(
        `<rect class="l${level(value)}" x="${column * step}" y="${top + row * step}" width="${cell}" height="${cell}" rx="3"><title>${day}: ${tokens(value)} tokens</title></rect>`,
      );
    }
  }
  const width = HEAT_WEEKS * step - (step - cell);
  const height = top + 7 * step - (step - cell);
  return html`${raw(`<svg class="heat" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" role="img" aria-label="Daily activity over the last year">${parts.join("")}</svg>`)}`;
}

export function monthYear(seconds: number): string {
  return new Date(seconds * 1000).toLocaleDateString("en-US", { month: "long", year: "numeric", timeZone: "UTC" });
}

export function ago(seconds: number, reference = Math.floor(Date.now() / 1000)): string {
  const delta = Math.max(0, reference - seconds);
  if (delta < 3600) return "within the hour";
  if (delta < 86400) return `${Math.floor(delta / 3600)} h ago`;
  return `${Math.floor(delta / 86400)} d ago`;
}
