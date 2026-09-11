import { html, raw } from "hono/html";
import type { HtmlEscapedString } from "hono/utils/html";
import { type Tool, TOOLS, TOOL_NAMES, type User, addDays } from "./env";
import { BACKDROP_SCRIPT } from "./backdrop";
import type { Metric, Totals } from "./stats";

export type Html = HtmlEscapedString | Promise<HtmlEscapedString>;

// Brand marks from Simple Icons (CC0), the same paths as Sources/Switchr/Core/ProviderMarks.swift.
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

/** Switchr's pixel mark: two rows of four squares, three lit on top and one below. */
export const PIXEL_MARK = `<svg class="pixel" viewBox="0 0 22 12" aria-hidden="true"><g fill="#EBEBEB"><rect x="0" y="0" width="4" height="4" rx="1"/><rect x="6" y="0" width="4" height="4" rx="1"/><rect x="12" y="0" width="4" height="4" rx="1"/><rect x="0" y="8" width="4" height="4" rx="1"/></g><g fill="#EBEBEB" fill-opacity=".22"><rect x="18" y="0" width="4" height="4" rx="1"/><rect x="6" y="8" width="4" height="4" rx="1"/><rect x="12" y="8" width="4" height="4" rx="1"/><rect x="18" y="8" width="4" height="4" rx="1"/></g></svg>`;

const FAVICON =
  "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='7' fill='%23171717'/%3E%3Cg fill='%23EBEBEB'%3E%3Crect x='6' y='10' width='4' height='4' rx='1'/%3E%3Crect x='11' y='10' width='4' height='4' rx='1'/%3E%3Crect x='16' y='10' width='4' height='4' rx='1'/%3E%3Crect x='6' y='18' width='4' height='4' rx='1'/%3E%3C/g%3E%3Cg fill='%23EBEBEB' fill-opacity='.25'%3E%3Crect x='21' y='10' width='4' height='4' rx='1'/%3E%3Crect x='11' y='18' width='4' height='4' rx='1'/%3E%3Crect x='16' y='18' width='4' height='4' rx='1'/%3E%3Crect x='21' y='18' width='4' height='4' rx='1'/%3E%3C/g%3E%3C/svg%3E";

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
.mono { font-family: var(--mono); font-size: 12.5px; }
.muted { color: var(--muted); } .subtle { color: var(--subtle); }

/* The backdrop: an illustrated scene behind the first screen, fading into the page below. Its motion
   is transform and opacity only, so it stays smooth. It scrolls away with the page. */
.backdrop { position: absolute; top: 0; left: 0; right: 0; height: 100vh; min-height: 760px; z-index: 0; overflow: hidden; pointer-events: none; }
.backdrop::after { content: ""; position: absolute; left: 0; right: 0; bottom: 0; height: 38%; background: linear-gradient(to bottom, rgba(23,23,23,0), var(--bg)); }
.top { position: relative; z-index: 1; border-bottom: 1px solid hsl(0 0% 100% / .05); background: transparent; }
.top-inner { max-width: 1080px; margin: 0 auto; height: 56px; padding: 0 24px; display: flex; align-items: center; gap: 20px; }
.brand { display: flex; align-items: center; gap: 10px; text-decoration: none; font-weight: 650; }
.pixel { width: 22px; height: 12px; flex: none; }
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
.center-card .pixel { width: 44px; height: 24px; }
.center-card .form { width: 100%; text-align: left; }
.code { font-family: var(--mono); font-size: 22px; letter-spacing: .12em; text-align: center; height: 48px; }

.site-foot { position: relative; z-index: 1; max-width: 1080px; margin: 0 auto; padding: 20px 24px 40px; color: var(--subtle); font-size: 12.5px; display: flex; gap: 16px; flex-wrap: wrap; border-top: 1px solid var(--border); }
.site-foot a { color: var(--muted); text-decoration: none; } .site-foot a:hover { color: var(--text); }

@media (max-width: 860px) {
  .podium, .split, .aside-layout { grid-template-columns: 1fr; }
  .stats { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .hide-sm { display: none; }
  .top-inner { gap: 10px; padding: 0 16px; }
  main { padding: 24px 16px 48px; }
}
@media (prefers-reduced-motion: reduce) { * { transition: none !important; } }
`;

export function layout(options: {
  title: string;
  description?: string;
  origin: string;
  path: string;
  user: User | null;
  active?: "leaderboard" | "teams";
  body: Html;
  nonce: string;
}): Html {
  const description = options.description ?? "Switchr leaderboards: who uses the most Claude Code, Cursor and Codex.";
  const current = (name: string) => (options.active === name ? raw('aria-current="page"') : "");
  const user = options.user;
  return html`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark">
<title>${options.title}</title>
<meta name="description" content="${description}">
<meta property="og:site_name" content="Switchr">
<meta property="og:title" content="${options.title}">
<meta property="og:description" content="${description}">
<meta property="og:url" content="${options.origin}${options.path}">
<meta name="twitter:card" content="summary">
<link rel="icon" href="${raw(FAVICON)}">
<style>${raw(CSS)}</style>
</head>
<body>
<div class="backdrop" aria-hidden="true"></div>
<header class="top"><div class="top-inner">
  <a class="brand" href="/leaderboard">${raw(PIXEL_MARK)}Switchr</a>
  <nav class="nav" aria-label="Main">
    <a href="/leaderboard" ${current("leaderboard")}>Leaderboard</a>
    ${user ? html`<a href="/teams" ${current("teams")}>Teams</a>` : ""}
  </nav>
  <div class="who">
    ${user
      ? html`<a class="me-link" href="/u/${user.login}">${avatar(user, 24)}<span class="hide-sm">${user.login}</span></a>
          <a class="btn ghost sm" href="/settings">Settings</a>`
      : html`<a class="btn sm" href="/login?next=${encodeURIComponent(options.path)}">${githubIcon()}Sign in with GitHub</a>`}
  </div>
</div></header>
<main>${options.body}</main>
<footer class="site-foot">
  <span>Switchr</span>
  <span>Totals are sent by the Switchr app: tokens, API value and requests per day. Nothing else.</span>
  <a href="https://github.com/dominikzabcik/switchr">GitHub</a>
</footer>
<script nonce="${options.nonce}">${raw(BACKDROP_SCRIPT)}
(function () {
  var host = document.querySelector(".backdrop");
  if (!host || !window.SwitchrBackdrop) return;
  window.SwitchrBackdrop.mount(host, { scene: "leaves", opacity: 0.85 });
})();
</script>
</body>
</html>`;
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
