export interface User {
  id: string;
  github_id: number;
  login: string;
  /** From GitHub, refreshed at every sign-in. */
  name: string | null;
  /** Chosen here, and left alone by that refresh. */
  display_name: string | null;
  bio: string | null;
  link: string | null;
  avatar_url: string | null;
  public: number;
  created_at: number;
}

export type AppEnv = {
  // Wrangler generates this from wrangler.jsonc, keeping runtime bindings and TypeScript in sync.
  Bindings: Cloudflare.Env;
  Variables: {
    user: User | null;
    sessionKind: "web" | "app" | null;
    sessionAccess: "read" | "write" | null;
    /** Lets the page's one script run under the content security policy. */
    nonce: string;
  };
};

export const TOOLS = [
  "claude", "cursor", "codex", "gemini", "opencode", "pi", "copilot", "windsurf", "codebuff",
  "amp", "goose", "qwen", "kimi", "grok", "kilo", "openclaw",
] as const;
export type Tool = (typeof TOOLS)[number];

/**
 * The tools Keyhop can count from exact local or provider records. Copilot, Windsurf and Codebuff
 * expose limit state but no complete model-token transcript, so they cannot appear in daily totals.
 * Every measured tool counts the same way: toward totals, the leaderboard, the pet and the quests.
 */
export const MEASURED_TOOLS = [
  "claude", "cursor", "codex", "gemini", "opencode", "pi",
  "amp", "goose", "qwen", "kimi", "grok", "kilo", "openclaw",
] as const;
export type MeasuredTool = (typeof MEASURED_TOOLS)[number];

/** How many tool rows a breakdown always shows, so a quiet window keeps the shape it had with six tools. */
export const SHOWN_TOOL_ROWS = 6;

/**
 * The measured tools worth a row: those with tokens, in the fixed order, padded with the next
 * tools in that order up to six. Thirteen rows of mostly zeros would bury the few that matter.
 */
export function shownTools(tools: Partial<Record<Tool, number>>): MeasuredTool[] {
  const used = MEASURED_TOOLS.filter((tool) => (tools[tool] ?? 0) > 0);
  if (used.length >= SHOWN_TOOL_ROWS) return used;
  const padding = MEASURED_TOOLS.filter((tool) => !used.includes(tool)).slice(0, SHOWN_TOOL_ROWS - used.length);
  return MEASURED_TOOLS.filter((tool) => used.includes(tool) || padding.includes(tool));
}

export const TOOL_NAMES: Record<Tool, string> = {
  claude: "Claude Code",
  cursor: "Cursor",
  codex: "Codex",
  gemini: "Gemini CLI",
  opencode: "OpenCode",
  pi: "Pi",
  copilot: "GitHub Copilot",
  windsurf: "Windsurf",
  codebuff: "Codebuff",
  amp: "Amp",
  goose: "Goose",
  qwen: "Qwen Code",
  kimi: "Kimi Code",
  grok: "Grok Build",
  kilo: "Kilo",
  openclaw: "OpenClaw",
};

/**
 * The tools that report limit windows. Measured-only tools (amp, goose, qwen, kimi, grok, kilo,
 * openclaw) have no logins and no limits, so limit uploads keep to this narrower list, matching
 * account_limits' CHECK.
 */
export const LIMIT_TOOLS = ["claude", "cursor", "codex", "gemini", "opencode", "pi", "copilot", "windsurf", "codebuff"] as const;

/** A current human-readable list, so validation errors never name stale tools. */
export const toolList = (): string => `${TOOLS.slice(0, -1).join(", ")} or ${TOOLS[TOOLS.length - 1]}`;

export const limitToolList = (): string => `${LIMIT_TOOLS.slice(0, -1).join(", ")} or ${LIMIT_TOOLS[LIMIT_TOOLS.length - 1]}`;

export const now = (): number => Math.floor(Date.now() / 1000);

/** Today's date in UTC as YYYY-MM-DD. */
export const today = (): string => new Date().toISOString().slice(0, 10);

export function addDays(day: string, count: number): string {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + count);
  return date.toISOString().slice(0, 10);
}
