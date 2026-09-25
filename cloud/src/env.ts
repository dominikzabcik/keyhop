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

export const TOOLS = ["claude", "cursor", "codex", "gemini", "opencode", "pi", "copilot", "windsurf", "codebuff"] as const;
export type Tool = (typeof TOOLS)[number];

/**
 * The tools Keyhop can count from exact local or provider records. Copilot, Windsurf and Codebuff
 * expose limit state but no complete model-token transcript, so they cannot appear in daily totals.
 */
export const MEASURED_TOOLS = ["claude", "cursor", "codex", "gemini", "opencode", "pi"] as const;

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
};

/** A current human-readable list, so validation errors never name stale tools. */
export const toolList = (): string => `${TOOLS.slice(0, -1).join(", ")} or ${TOOLS[TOOLS.length - 1]}`;

export const now = (): number => Math.floor(Date.now() / 1000);

/** Today's date in UTC as YYYY-MM-DD. */
export const today = (): string => new Date().toISOString().slice(0, 10);

export function addDays(day: string, count: number): string {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + count);
  return date.toISOString().slice(0, 10);
}
