export interface Env {
  DB: D1Database;
  DEVICE_START_LIMITER: RateLimit;
  DEVICE_POLL_LIMITER: RateLimit;
  /** Uploads per signed-in account: usage and limits. */
  UPLOAD_LIMITER: RateLimit;
  /** GitHub OAuth app credentials, set with `wrangler secret put`. */
  GITHUB_CLIENT_ID: string;
  GITHUB_CLIENT_SECRET: string;
  /** "true" enables /auth/dev, which signs in without GitHub. Honored only on localhost. */
  DEV_LOGIN?: string;
}

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
  Bindings: Env;
  Variables: {
    user: User | null;
    sessionKind: "web" | "app" | null;
    sessionAccess: "read" | "write" | null;
    /** Lets the page's one script run under the content security policy. */
    nonce: string;
  };
};

export const TOOLS = ["claude", "cursor", "codex", "gemini", "copilot", "windsurf"] as const;
export type Tool = (typeof TOOLS)[number];

/**
 * The tools Keyhop can actually count usage for. Copilot and Windsurf are switched by Keyhop but
 * write no local transcript it can read and publish no allowance it can ask for, so they never
 * appear in a day's totals. Goals that ask someone to "use every tool" count these, or they would
 * ask for something no one can do.
 */
export const MEASURED_TOOLS = ["claude", "cursor", "codex", "gemini"] as const;

export const TOOL_NAMES: Record<Tool, string> = {
  claude: "Claude Code",
  cursor: "Cursor",
  codex: "Codex",
  gemini: "Gemini CLI",
  copilot: "GitHub Copilot",
  windsurf: "Windsurf",
};

/** "claude, cursor, codex, gemini, copilot or windsurf", so an error never names a stale list. */
export const toolList = (): string => `${TOOLS.slice(0, -1).join(", ")} or ${TOOLS[TOOLS.length - 1]}`;

export const now = (): number => Math.floor(Date.now() / 1000);

/** Today's date in UTC as YYYY-MM-DD. */
export const today = (): string => new Date().toISOString().slice(0, 10);

export function addDays(day: string, count: number): string {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + count);
  return date.toISOString().slice(0, 10);
}
