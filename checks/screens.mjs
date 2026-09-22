/**
 * Every screen Keyhop shows, in one list.
 *
 * The website's pages and the Mac window's sections are both web pages, so one harness drives
 * both. A screen names itself, says where to find it, and may name what it must contain; the
 * checks that apply to every screen live in checks.mjs and are never repeated here.
 */

/** Widths the website has to survive: a phone, a small laptop, a wide window. */
export const WIDTHS = [
  { name: "phone", width: 390, height: 844 },
  { name: "laptop", width: 1280, height: 800 },
  { name: "wide", width: 1680, height: 1050 },
];

/** Keyhop's window can't be made smaller than this, so it is never checked at phone width. */
export const APP_WIDTHS = [
  { name: "smallest", width: 960, height: 620 },
  { name: "laptop", width: 1280, height: 820 },
  { name: "wide", width: 1680, height: 1050 },
];

/** Pages anyone can reach without signing in. */
export const SITE_SCREENS = [
  { name: "home", path: "/", mustSay: ["Every account.", "One hop away.", "Download Keyhop"] },
  { name: "download", path: "/download", mustSay: ["macOS", "Linux", "Windows"] },
  { name: "leaderboard", path: "/leaderboard", mustSay: ["Leaderboard"] },
  { name: "season", path: "/season", mustSay: ["Season"] },
  { name: "privacy", path: "/privacy", mustSay: ["What stays on your computer"] },
  { name: "terms", path: "/terms", mustSay: ["Provider rules still apply"] },
  { name: "security", path: "/security", mustSay: ["Report problems privately."] },
  { name: "login", path: "/login", mustSay: ["GitHub"] },
  { name: "missing", path: "/no-such-page", expect: { status: [404] } },
];

/** Pages that only exist once someone is signed in. The harness signs itself in to reach them. */
export const ACCOUNT_SCREENS = [
  { name: "profile", path: "/u/checks-visitor", mustSay: ["checks-visitor"] },
  { name: "settings", path: "/settings", mustSay: ["Settings"] },
  { name: "teams", path: "/teams", mustSay: ["Teams"] },
  { name: "link", path: "/link", mustSay: [] },
  { name: "welcome", path: "/welcome", mustSay: [] },
  { name: "leaderboard-signed-in", path: "/leaderboard", mustSay: ["Leaderboard"] },
  { name: "season-signed-in", path: "/season", mustSay: ["Season"] },
  { name: "team-day", path: "/t/checks/day", mustSay: ["Today", "Importer"] },
];

/** The Mac window, served by `keyhop dashboard --sample`. Its sections live behind the hash. */
export const APP_SCREENS = [
  { name: "overview", section: "overview", mustSay: ["In use"] },
  { name: "accounts", section: "accounts", mustSay: ["Add account"] },
  { name: "usage", section: "usage", mustSay: ["Tokens", "Tools", "Sessions", "Cache read", "API value"] },
  { name: "budgets", section: "budgets", mustSay: ["Budget"] },
  { name: "leaderboard", section: "leaderboard", mustSay: [] },
  // Asking GitHub for the latest release needs the network. A machine without it still has to
  // show Settings, and say that the check failed rather than showing nothing.
  { name: "settings", section: "settings", mustSay: ["Updates", "Storage and privacy", "What you shipped"], mayFail: ["/api/update"] },
];

/**
 * Things the whole interface must never say, whatever the screen. Each is a real mistake that has
 * shipped somewhere before: a value that never resolved, a placeholder, or a plural that reads as
 * a bug.
 */
export const NEVER_SAY = [
  "undefined",
  "NaN",
  "[object Object]",
  "null·",
  "Infinity",
  "0 of 0",
  " is over its",
  "accounts is ",
];

/** An em dash is a house rule, not a typo: the writing uses a hyphen, a colon or two sentences. */
export const BANNED_CHARACTERS = [
  { character: "—", name: "em dash" },
  { character: "–", name: "en dash" },
];
