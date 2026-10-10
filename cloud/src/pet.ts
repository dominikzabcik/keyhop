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
 * A chibi that fills its frame, the way a Codex pet fills a 192×208 cell: one round body,
 * ears big enough to read, tiny feet, a thick outline, flat colour. Pose only lifts the ears
 * and the paw, so the feet stay put. The tool colour is the ears, the cheeks, and the blocks.
 * Clients paint the rectangles and do not invent a second body.
 */
const INK = "#241C16";
const BODY = "#F6DCC0";
const SHADE = "#E2BC8C";
const LIFT = "#FFF3DC";
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

/** Distances are measured up from the soles, then scaled. `dx` is right of centre. */
function gx(dx: number, s: number): number {
  return CX + dx * s;
}
function gy(up: number, s: number): number {
  return FOOT - up * s;
}

function ellipse(g: Grid, cx: number, cy: number, rx: number, ry: number, cell: Cell, guard?: (current: Cell) => boolean): void {
  if (rx < 0.45 || ry < 0.45) return;
  const y0 = Math.max(0, Math.floor(cy - ry));
  const y1 = Math.min(GRID_H - 1, Math.ceil(cy + ry));
  for (let y = y0; y <= y1; y++) {
    const ny = (y + 0.5 - cy) / ry;
    if (ny * ny > 1) continue;
    const hx = rx * Math.sqrt(1 - ny * ny);
    const x0 = Math.max(0, Math.ceil(cx - hx));
    const x1 = Math.min(GRID_W - 1, Math.floor(cx + hx - 1e-6));
    for (let x = x0; x <= x1; x++) {
      if (guard && !guard(g.get(x, y))) continue;
      g.set(x, y, cell);
    }
  }
}

const onBody = (cell: Cell) => cell === "B" || cell === "S" || cell === "L";

/** Ink ring, then a flat fill. The ring is two pixels: thick at card size, still a hard edge. */
function blob(g: Grid, cx: number, cy: number, rx: number, ry: number, fill: Cell, outline = 2): void {
  ellipse(g, cx, cy, rx + outline, ry + outline, "K");
  ellipse(g, cx, cy, rx, ry, fill);
}

function capsule(g: Grid, x0: number, y0: number, x1: number, y1: number, radius: number, fill: Cell): void {
  const steps = Math.max(1, Math.ceil(Math.hypot(x1 - x0, y1 - y0)));
  for (const rad of [radius + 2, radius]) {
    const cell: Cell = rad === radius ? fill : "K";
    for (let step = 0; step <= steps; step++) {
      const t = step / steps;
      ellipse(g, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, rad, rad * 0.92, cell);
    }
  }
}

/** A fat ear. The tool colour is the outside; the cream is the inside. Settled ears hang beside the cheek. */
function ear(g: Grid, dx: number, up: number, rx: number, ry: number, s: number): void {
  const cx = gx(dx, s);
  const cy = gy(up, s);
  blob(g, cx, cy, rx * s, ry * s, "A", 2);
  ellipse(g, cx, cy + ry * s * 0.08, rx * s * 0.48, ry * s * 0.52, "B", (cell) => cell === "A");
}

function smile(g: Grid, up: number, half: number, rise: number, s: number): void {
  const cx = gx(0, s);
  const cy = gy(up, s);
  const w = Math.max(2, half * s);
  const h = Math.max(1.2, rise * s);
  for (let x = Math.round(cx - w); x <= Math.round(cx + w); x++) {
    const t = (x - cx) / w;
    const y = Math.round(cy + h * (1 - t * t));
    g.set(x, y, "K");
    g.set(x, y + 1, "K");
  }
}

function eye(g: Grid, dx: number, up: number, s: number, pose: Pet["pose"]): void {
  const cx = gx(dx, s);
  const cy = gy(up, s);
  const rx = 7.2 * s;
  const ry = 8.2 * s;
  if (pose === "settled") {
    const w = Math.max(2, rx);
    for (let x = Math.round(cx - w); x <= Math.round(cx + w); x++) {
      const t = (x - cx) / w;
      const y = Math.round(cy + ry * 0.28 * (1 - t * t));
      g.set(x, y, "K");
      g.set(x, y + 1, "K");
    }
    return;
  }
  blob(g, cx, cy, rx, ry, "W", 1.4);
  const side = dx < 0 ? -1 : 1;
  ellipse(g, cx + side * rx * 0.08, cy + ry * 0.06, rx * 0.58, ry * 0.64, "E");
  ellipse(g, cx - side * rx * 0.22, cy - ry * 0.28, Math.max(0.9, rx * 0.2), Math.max(0.9, ry * 0.2), "W");
}

function companion(stage: number, pose: Pet["pose"]): Grid {
  const g = new Grid();
  const s = SCALES[stage];
  const leg = (dx: number, footDx: number) => {
    capsule(g, gx(dx, s), gy(16, s), gx(footDx, s), gy(5, s), Math.max(2.2, 3.4 * s), "S");
    blob(g, gx(footDx, s), gy(3.2, s), 7.2 * s, 3.6 * s, "S", 2);
  };
  leg(-8, -13);
  leg(8, 13);

  // Ears first, then the head covers their base, so they grow out of the skull instead of sitting on it.
  if (pose !== "settled") {
    ear(g, -15, 68, 13, 17, s);
    ear(g, 16, 66, 13, 18, s);
  }

  const bodyCx = gx(0, s);
  const bodyCy = gy(34, s);
  const bodyRx = 33 * s;
  const bodyRy = 27 * s;
  blob(g, bodyCx, bodyCy, bodyRx, bodyRy, "B", 2);
  ellipse(g, bodyCx + bodyRx * 0.1, bodyCy + bodyRy * 0.24, bodyRx * 0.7, bodyRy * 0.5, "S", onBody);
  ellipse(g, bodyCx - bodyRx * 0.34, bodyCy - bodyRy * 0.38, bodyRx * 0.16, bodyRy * 0.12, "L", (cell) => cell === "B");

  if (pose === "settled") {
    ear(g, -31, 44, 10, 7.5, s);
    ear(g, 31, 44, 10, 7.5, s);
  }

  eye(g, -12, 42, s, pose);
  eye(g, 12, 42, s, pose);
  smile(g, 27, pose === "tall" ? 8 : 6.2, pose === "settled" ? 1.6 : 3.4, s);
  ellipse(g, gx(-20, s), gy(33, s), 4.8 * s, 2.8 * s, "A", onBody);
  ellipse(g, gx(20, s), gy(33, s), 4.8 * s, 2.8 * s, "A", onBody);
  ellipse(g, gx(0, s), gy(18, s), 6.4 * s, 3.6 * s, "A", onBody);

  const nub = Math.max(2.6, 4.6 * s);
  capsule(g, gx(-26, s), gy(32, s), gx(-32, s), gy(18, s), nub, "B");
  if (pose === "tall") {
    const thick = Math.max(3.4, 6.4 * s);
    const pawX = gx(22, s);
    const pawY = gy(90, s);
    capsule(g, gx(28, s), gy(40, s), gx(38, s), gy(62, s), thick, "B");
    capsule(g, gx(38, s), gy(62, s), pawX, pawY, thick, "B");
    blob(g, pawX, pawY, 10 * s, 8.4 * s, "B", 2);
    ellipse(g, pawX, pawY + 1.2 * s, 2.2 * s, 1.7 * s, "A", onBody);
    ellipse(g, pawX - 3.2 * s, pawY + 2.2 * s, 1.3 * s, 1.1 * s, "A", onBody);
    ellipse(g, pawX + 3.2 * s, pawY + 2.2 * s, 1.3 * s, 1.1 * s, "A", onBody);
  } else {
    capsule(g, gx(26, s), gy(32, s), gx(32, s), gy(18, s), nub, "B");
  }
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
