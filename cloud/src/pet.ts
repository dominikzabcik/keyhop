import { Hono } from "hono";
import { apiUser } from "./auth";
import { type AppEnv, type MeasuredTool, type Tool, MEASURED_TOOLS, today } from "./env";
import { streaks } from "./stats";
import { esc, frame, MONO, SANS, shortTokens, svgHeaders, svgOpen, themeOf, type Theme } from "./svg";

/**
 * One lifetime creature per linked account. Nothing is stored: stage, lineage, pose and build are
 * counted from the daily totals, the same way a season is, so a re-sync cannot leave the pet
 * disagreeing with the usage it came from.
 *
 * The body is a list of rectangles. Every client paints that list and none of them invent a second
 * layout.
 */

/**
 * The same tool colours the dashboard charts use, so a Claude pet is the same amber as a Claude bar.
 * The measured-only tools take hues between the first six; the V2 design pass may retune them.
 */
const TOOL_COLORS: Record<MeasuredTool, string> = {
  claude: "#C9821A",
  cursor: "#2F6FC0",
  codex: "#B8423F",
  gemini: "#1E9A78",
  opencode: "#7A6BC4",
  pi: "#C45B8A",
  amp: "#D2622A",
  goose: "#3F9A3B",
  qwen: "#9C49B8",
  kimi: "#1C8FB0",
  grok: "#4A5A72",
  kilo: "#8A9A1E",
  openclaw: "#9B2D6E",
};

const LINEAGE_NAMES: Record<MeasuredTool | "mix", string> = {
  claude: "Claude",
  cursor: "Cursor",
  codex: "Codex",
  gemini: "Gemini",
  opencode: "OpenCode",
  pi: "Pi",
  amp: "Amp",
  goose: "Goose",
  qwen: "Qwen",
  kimi: "Kimi",
  grok: "Grok",
  kilo: "Kilo",
  openclaw: "OpenClaw",
  mix: "Mix",
};

/** All-time tokens where each stage starts. The last sits past the ten-billion badge. */
const STAGES: { key: string; name: string; at: number }[] = [
  { key: "speck", name: "Speck", at: 0 },
  { key: "hatch", name: "Hatch", at: 1_000_000 },
  { key: "frame", name: "Frame", at: 50_000_000 },
  { key: "bulk", name: "Bulk", at: 500_000_000 },
  { key: "mass", name: "Mass", at: 5_000_000_000 },
  { key: "monument", name: "Monument", at: 25_000_000_000 },
];

export interface PetShape {
  x: number;
  y: number;
  w: number;
  h: number;
  opacity: number;
  fill: string;
  /** shine blinks (the eyes). flame and screen stay so an older list still decodes. */
  kind?: "flame" | "eye" | "shine" | "screen";
}

export interface Pet {
  stage: string;
  stageName: string;
  /** A measured tool, "mix", or null when nothing has been synced yet. */
  lineage: string | null;
  lineageName: string | null;
  pose: "settled" | "up" | "tall";
  /** 0 none, 1 any commit, 2 a hundred, 3 a thousand. */
  build: 0 | 1 | 2 | 3;
  tokens: number;
  commits: number;
  streak: number;
  next: { label: string; tokens: number } | null;
  width: number;
  height: number;
  shapes: PetShape[];
}

export interface PetInput {
  tokens: number;
  tools: Partial<Record<Tool, number>>;
  streak: number;
  commits: number;
}

/**
 * A block creature on the same grid as the night field: bone body, hard outline, one tool mark.
 * Pose only lifts the ears, so the feet stay put. Clients paint the rectangles and do not
 * invent a second body.
 */
const INK = "#140E0C";
const BODY = "#F3EAD8";
const SHADE = "#CDBFA6";
const LIFT = "#FFF6E8";
const EYE = "#FFF9F2";
/** The accent when a pet has no single tool: a mid green, never one tool's colour. */
const NEUTRAL_ACCENT = "#6E7A52";

/** K outline, B body, S the lower shade, L the highlight, A the marking, W the eye, E the pupil. */
type Ink = "K" | "B" | "S" | "L" | "A" | "W" | "E";
type Cell = Ink | null;

/** A Codex pet cell is 192×208. Two units per drawn pixel keeps the outline chunky at card size. */
const GRID_W = 96;
const GRID_H = 104;
const PX = 2;
/** The row the soles rest on. Every pose shares it. */
const FOOT = 99;
const CX = 48;
/** Each stage is a larger copy of the same character, anchored on the soles. */
const SCALES = [0.5, 0.62, 0.73, 0.84, 0.93, 1];

class Grid {
  readonly rows: Cell[][];

  constructor() {
    this.rows = Array.from({ length: GRID_H }, () => Array<Cell>(GRID_W).fill(null));
  }

  get(x: number, y: number): Cell {
    return x < 0 || y < 0 || x >= GRID_W || y >= GRID_H ? null : this.rows[y][x];
  }

  set(x: number, y: number, ink: Cell): void {
    if (x >= 0 && y >= 0 && x < GRID_W && y < GRID_H) this.rows[y][x] = ink;
  }

}

function fill(g: Grid, x0: number, y0: number, x1: number, y1: number, cell: Cell): void {
  const xa = Math.round(Math.min(x0, x1));
  const xb = Math.round(Math.max(x0, x1));
  const ya = Math.round(Math.min(y0, y1));
  const yb = Math.round(Math.max(y0, y1));
  for (let y = ya; y <= yb; y++) for (let x = xa; x <= xb; x++) g.set(x, y, cell);
}

/** Chunk size at each stage. Later stages are the same animal in bigger pixels, so the shape count grows. */
const CHUNK = [2, 3, 4, 5, 6, 7];

/**
 * A side-view dune animal, one character per chunk. The amber cell is the tool mark.
 * Pose only stacks the ear, so the feet stay on the same row.
 */
const BODY_ROWS = [
  "......bbbb..",
  ".....bEbbbb.",
  "...bbbbbbbb.",
  ".bbbbbbbbb..",
  "Abbbbbbb....",
  "bbbbbbbb....",
  "bbbbbbbb....",
  "ssssssss....",
  ".bb..bb.....",
  ".ss..ss.....",
];

const EAR_ROWS: Record<Pet["pose"], string[]> = {
  settled: [],
  up: ["......bb...."],
  tall: ["......bb....", "......bb...."],
};

const CHUNK_INK: Record<string, Ink> = { b: "B", s: "S", A: "A", E: "E" };

function stamp(g: Grid, rows: string[], cell: number, top: number, left: number): void {
  rows.forEach((row, ry) => {
    [...row].forEach((ch, rx) => {
      const ink = CHUNK_INK[ch];
      if (!ink) return;
      fill(g, left + rx * cell, top + ry * cell, left + (rx + 1) * cell - 1, top + (ry + 1) * cell - 1, ink);
    });
  });
}

/** One pixel of ink around the silhouette, the same edge the night-field runner uses. */
function outline(g: Grid): void {
  const marks: [number, number][] = [];
  for (let y = 0; y < GRID_H; y++) {
    for (let x = 0; x < GRID_W; x++) {
      if (g.rows[y][x]) continue;
      if (g.get(x - 1, y) || g.get(x + 1, y) || g.get(x, y - 1) || g.get(x, y + 1)) marks.push([x, y]);
    }
  }
  for (const [x, y] of marks) g.set(x, y, "K");
}

function companion(stage: number, pose: Pet["pose"]): Grid {
  const g = new Grid();
  const cell = CHUNK[stage];
  const left = Math.round(CX - (BODY_ROWS[0].length * cell) / 2);
  const bodyTop = FOOT - BODY_ROWS.length * cell;
  const ears = EAR_ROWS[pose];
  stamp(g, ears, cell, bodyTop - ears.length * cell, left);
  stamp(g, BODY_ROWS, cell, bodyTop, left);
  outline(g);
  return g;
}

/** One extra unit so neighbouring pixels overlap. A scaled card would otherwise show hairline gaps. */
export const PET_WIDTH = GRID_W * PX + 1;
export const PET_HEIGHT = GRID_H * PX + 1;

function rect(x: number, y: number, w: number, h: number, fill: string, kind?: PetShape["kind"]): PetShape {
  return { x: x * PX, y: y * PX, w: w * PX + 1, h: h * PX + 1, opacity: 1, fill, ...(kind ? { kind } : {}) };
}

function raster(grid: Grid, accent: string): PetShape[] {
  const colours: Record<Ink, string> = { K: INK, B: BODY, S: SHADE, L: LIFT, A: accent, W: EYE, E: INK };
  const shapes: PetShape[] = [];
  for (let y = 0; y < GRID_H; y++) {
    let run: PetShape | null = null;
    const flush = () => {
      if (run) shapes.push(run);
      run = null;
    };
    for (let x = 0; x < GRID_W; x++) {
      const cell = grid.rows[y][x];
      if (!cell) {
        flush();
        continue;
      }
      const fill = colours[cell];
      const kind: PetShape["kind"] = cell === "E" ? "shine" : undefined;
      if (run && run.fill === fill && run.kind === kind && run.x + run.w === x * PX + 1) {
        run.w += PX;
        continue;
      }
      flush();
      run = { x: x * PX, y: y * PX, w: PX + 1, h: PX + 1, opacity: 1, fill, ...(kind ? { kind } : {}) };
    }
    flush();
  }
  return shapes;
}

/** Blocks beside the feet, one more at each step of build. They stay above the sole. */
function stack(stage: number, build: number, fill: string): PetShape[] {
  const shapes: PetShape[] = [];
  const s = SCALES[stage];
  const footLeft = CX + -20 * s;
  for (let i = 0; i < build; i++) {
    const w = Math.max(4, Math.round((8 - i) * Math.max(s, 0.7)));
    const h = Math.max(3, Math.round(4.5 * Math.max(s, 0.7)));
    const x = Math.max(1, Math.round(footLeft - w - 3));
    const y = Math.max(1, Math.round(FOOT - 2 - (i + 1) * (h + 1)));
    shapes.push(rect(x - 1, y - 1, w + 2, h + 2, INK));
    shapes.push(rect(x, y, w, h, fill));
  }
  return shapes;
}

function stageIndex(tokens: number): number {
  let index = 0;
  for (let i = STAGES.length - 1; i >= 0; i--) {
    if (tokens >= STAGES[i].at) {
      index = i;
      break;
    }
  }
  return index;
}

/** The measured tool with at least half the tokens. A tie keeps the earlier tool. Below half, mix. */
export function lineageFor(tools: Partial<Record<Tool, number>>): { key: string; name: string } | null {
  let total = 0;
  let best: { key: MeasuredTool; tokens: number } | null = null;
  for (const tool of MEASURED_TOOLS) {
    const tokens = tools[tool] ?? 0;
    total += tokens;
    if (!best || tokens > best.tokens) best = { key: tool, tokens };
  }
  if (total <= 0 || !best) return null;
  if (best.tokens * 2 < total) return { key: "mix", name: LINEAGE_NAMES.mix };
  return { key: best.key, name: LINEAGE_NAMES[best.key] };
}

function poseFor(streak: number): Pet["pose"] {
  if (streak >= 7) return "tall";
  if (streak >= 1) return "up";
  return "settled";
}

function buildFor(commits: number): Pet["build"] {
  if (commits >= 1000) return 3;
  if (commits >= 100) return 2;
  if (commits >= 1) return 1;
  return 0;
}

/** The creature for these totals. The same inputs always return the same rectangles. */
export function petFrom(input: PetInput): Pet {
  const tokens = Math.max(0, input.tokens);
  const commits = Math.max(0, input.commits);
  const streak = Math.max(0, input.streak);
  const index = stageIndex(tokens);
  const stage = STAGES[index];
  const following = STAGES[index + 1];
  const lineage = lineageFor(input.tools);
  const pose = poseFor(streak);
  const build = buildFor(commits);
  const tint = lineage && lineage.key !== "mix" ? TOOL_COLORS[lineage.key as MeasuredTool] : null;
  const accent = tint ?? NEUTRAL_ACCENT;
  const shapes = [...raster(companion(index, pose), accent), ...stack(index, build, accent)];

  return {
    stage: stage.key,
    stageName: stage.name,
    lineage: lineage?.key ?? null,
    lineageName: lineage?.name ?? null,
    pose,
    build,
    tokens,
    commits,
    streak,
    next: following ? { label: following.name, tokens: following.at - tokens } : null,
    width: PET_WIDTH,
    height: PET_HEIGHT,
    shapes,
  };
}

interface UsageRow {
  user_id: string;
  tool: Tool;
  tokens: number;
}

interface DayRow {
  user_id: string;
  day: string;
}

interface WorkRow {
  user_id: string;
  day: string;
  commits: number;
}

/** One pet per id, including people who have synced nothing yet. */
export async function petsFor(db: D1Database, userIds: string[], reference = today()): Promise<Map<string, Pet>> {
  const pets = new Map<string, Pet>();
  if (userIds.length === 0) return pets;
  const marks = userIds.map(() => "?").join(", ");
  const [usage, days, work] = await Promise.all([
    db
      .prepare(`SELECT user_id, tool, SUM(tokens) AS tokens FROM daily_usage WHERE user_id IN (${marks}) GROUP BY user_id, tool`)
      .bind(...userIds)
      .all<UsageRow>(),
    db
      .prepare(
        `SELECT user_id, day FROM daily_usage WHERE user_id IN (${marks}) GROUP BY user_id, day HAVING SUM(tokens) > 0`,
      )
      .bind(...userIds)
      .all<DayRow>(),
    db
      .prepare(
        `SELECT user_id, day, SUM(commits) AS commits FROM daily_work WHERE user_id IN (${marks}) GROUP BY user_id, day`,
      )
      .bind(...userIds)
      .all<WorkRow>(),
  ]);

  const tools = new Map<string, Partial<Record<Tool, number>>>();
  const totals = new Map<string, number>();
  for (const row of usage.results) {
    const entry = tools.get(row.user_id) ?? {};
    entry[row.tool] = row.tokens;
    tools.set(row.user_id, entry);
    totals.set(row.user_id, (totals.get(row.user_id) ?? 0) + row.tokens);
  }
  const active = new Map<string, Set<string>>();
  const touch = (userId: string, day: string) => {
    const daysForUser = active.get(userId) ?? new Set<string>();
    daysForUser.add(day);
    active.set(userId, daysForUser);
  };
  for (const row of days.results) touch(row.user_id, row.day);
  const commits = new Map<string, number>();
  for (const row of work.results) {
    commits.set(row.user_id, (commits.get(row.user_id) ?? 0) + row.commits);
    if (row.commits > 0) touch(row.user_id, row.day);
  }

  for (const userId of userIds) {
    pets.set(
      userId,
      petFrom({
        tokens: totals.get(userId) ?? 0,
        tools: tools.get(userId) ?? {},
        streak: streaks(active.get(userId) ?? new Set(), reference).current,
        commits: commits.get(userId) ?? 0,
      }),
    );
  }
  return pets;
}

export async function petFor(db: D1Database, userId: string, reference = today()): Promise<Pet> {
  const pets = await petsFor(db, [userId], reference);
  return pets.get(userId) ?? petFrom({ tokens: 0, tools: {}, streak: 0, commits: 0 });
}

/** The creature alone, for a profile or a team row. Fills are our own colours, never someone's text. */
export function creatureMarkup(pet: Pet, className = "pet"): string {
  const rects = pet.shapes
    .map(
      (shape) =>
        `<rect x="${shape.x}" y="${shape.y}" width="${shape.w}" height="${shape.h}" fill="${shape.fill}" fill-opacity="${shape.opacity}"${shape.kind ? ` class="${shape.kind}"` : ""}/>`,
    )
    .join("");
  const label = pet.lineageName ? `${pet.stageName} · ${pet.lineageName}` : pet.stageName;
  return `<svg class="${className}" viewBox="0 0 ${pet.width} ${pet.height}" shape-rendering="crispEdges" role="img" aria-label="${esc(label)}">${rects}</svg>`;
}

/** A share image: the creature, its stage, and where to find the profile. */
export function petCard(pet: Pet, name: string, login: string, theme: Theme): string {
  const width = 880;
  const height = 320;
  const scale = 1.15;
  const left = 52;
  const top = 12;
  const body = pet.shapes
    .map(
      (shape) =>
        `<rect x="${left + shape.x * scale}" y="${top + shape.y * scale}" width="${shape.w * scale}" height="${shape.h * scale}" fill="${shape.fill}" fill-opacity="${shape.opacity}"${shape.kind ? ` class="${shape.kind}"` : ""}/>`,
    )
    .join("");
  const caption = pet.lineageName ? `${pet.stageName} · ${pet.lineageName}` : pet.stageName;
  const next = pet.next ? `${shortTokens(pet.next.tokens)} to ${pet.next.label}` : "Monument";
  const safeName = esc(name);
  return `${svgOpen(width, height, `${name}, ${caption}`)}
  ${frame(width, height, theme)}
  ${body}
  <text x="350" y="128" font-size="34" font-weight="640" fill="${theme.text}" font-family="${SANS}">${safeName}</text>
  <text x="350" y="168" font-size="20" font-weight="620" fill="${theme.text}" font-family="${SANS}">${esc(caption)}</text>
  <text x="350" y="198" font-size="15" fill="${theme.muted}" font-family="${SANS}">${esc(next)}</text>
  <text x="350" y="248" font-size="13" fill="${theme.faint}" font-family="${MONO}">keyhop.app/u/${esc(login)}</text>
</svg>`;
}

export const petRoutes = new Hono<AppEnv>();

petRoutes.get("/api/pet", apiUser, async (c) => {
  const user = c.get("user")!;
  return c.json(await petFor(c.env.DB, user.id));
});

petRoutes.get("/u/:login/pet.svg", async (c) => {
  const login = c.req.param("login");
  const person = await c.env.DB.prepare(
    "SELECT id, login, name, display_name, public FROM users WHERE login = ? COLLATE NOCASE",
  )
    .bind(login)
    .first<{ id: string; login: string; name: string | null; display_name: string | null; public: number }>();
  if (!person || person.public !== 1) return c.notFound();
  const creature = await petFor(c.env.DB, person.id);
  const name = person.display_name || person.name || person.login;
  svgHeaders(c);
  return c.body(petCard(creature, name, person.login, themeOf(c.req.query("theme"))));
});
