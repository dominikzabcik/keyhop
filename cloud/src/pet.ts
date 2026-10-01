import { Hono } from "hono";
import { apiUser } from "./auth";
import { type AppEnv, type Tool, MEASURED_TOOLS, today } from "./env";
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

/** The same tool colours the dashboard charts use, so a Claude pet is the same amber as a Claude bar. */
const TOOL_COLORS: Record<(typeof MEASURED_TOOLS)[number], string> = {
  claude: "#C9821A",
  cursor: "#2F6FC0",
  codex: "#B8423F",
  gemini: "#1E9A78",
  opencode: "#7A6BC4",
  pi: "#C45B8A",
};

const LINEAGE_NAMES: Record<(typeof MEASURED_TOOLS)[number] | "mix", string> = {
  claude: "Claude",
  cursor: "Cursor",
  codex: "Codex",
  gemini: "Gemini",
  opencode: "OpenCode",
  pi: "Pi",
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
  /** screen is the handheld glass, shine is what blinks (the eyes), flame is kept for older clients. Body pixels omit it. */
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
 * The pet lives on a small handheld screen, the way a Game & Watch does. The screen is part of the
 * shape list, so a client never has to choose a background that the ink can be read on. The tool
 * colour tints the glass and fills the creature's antenna tip, ear linings and chest light.
 */
const INK = "#232B1D";
const SHELL = "#2F3629";
const GLASS = "#C9D2A6";
/** The accent when a pet has no single tool: a mid green that sits between glass and ink. */
const NEUTRAL_ACCENT = "#6E7A52";

/** K ink, A accent, E ink that blinks. */
type Ink = "K" | "A" | "E";
type Cell = Ink | null;

const GRID_W = 44;
const GRID_H = 46;
/** One drawn pixel is this many units on the canvas. */
const PX = 5;
/** The bottom row of the feet. The floor line sits one row under it. */
const FLOOR = 38;
/** Columns 0 to 21 lie left of the centre line, 22 to 43 right of it. */
const MID = GRID_W / 2;

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

  /** Paints a pixel and its mirror. `far` is the distance from the centre line, 0 being the pair beside it. */
  pair(far: number, y: number, ink: Cell = "K"): void {
    this.set(MID - 1 - far, y, ink);
    this.set(MID + far, y, ink);
  }

  span(from: number, to: number, y: number, ink: Cell = "K"): void {
    for (let far = from; far <= to; far++) this.pair(far, y, ink);
  }

  /** A box centred on the screen, 1 pixel outline, glass inside. */
  box(top: number, height: number, half: number): void {
    for (let y = top; y < top + height; y++) {
      const edge = y === top || y === top + height - 1;
      for (let far = 0; far < half; far++) this.pair(far, y, edge || far === half - 1 ? "K" : null);
    }
  }

  /** Any filled shape, drawn as its outline. `halves[i]` is the half width of row i from `top`. */
  silhouette(top: number, halves: number[]): void {
    halves.forEach((half, i) => {
      const above = i === 0 ? 0 : halves[i - 1];
      const below = i === halves.length - 1 ? 0 : halves[i + 1];
      for (let far = 0; far < half; far++) {
        const edge = far >= Math.min(above, below) || far === half - 1;
        this.pair(far, top + i, edge ? "K" : null);
      }
    });
  }
}

interface Frame {
  /** Half width of the head, and its height. */
  head: number;
  headRows: number;
  /** Half width of the body and its height. Zero for a pet that is all head. */
  body: number;
  bodyRows: number;
  ear: number;
  eyeGap: number;
  eyeWidth: number;
  eyeRows: number;
  /** Half width of the smile. */
  smile: number;
  bolts: boolean;
  /** 0 no arms, otherwise how long. */
  arm: number;
  chest: number;
  halo: boolean;
}

const FRAMES: Frame[] = [
  { head: 0, headRows: 0, body: 0, bodyRows: 0, ear: 0, eyeGap: 0, eyeWidth: 0, eyeRows: 0, smile: 0, bolts: false, arm: 0, chest: 0, halo: false },
  { head: 6, headRows: 9, body: 0, bodyRows: 0, ear: 2, eyeGap: 1, eyeWidth: 2, eyeRows: 3, smile: 1, bolts: false, arm: 0, chest: 0, halo: false },
  { head: 7, headRows: 10, body: 4, bodyRows: 5, ear: 3, eyeGap: 1, eyeWidth: 2, eyeRows: 3, smile: 1, bolts: false, arm: 0, chest: 0, halo: false },
  { head: 8, headRows: 11, body: 6, bodyRows: 7, ear: 4, eyeGap: 2, eyeWidth: 2, eyeRows: 4, smile: 2, bolts: true, arm: 5, chest: 1, halo: false },
  { head: 9, headRows: 12, body: 7, bodyRows: 8, ear: 5, eyeGap: 2, eyeWidth: 3, eyeRows: 4, smile: 2, bolts: true, arm: 6, chest: 2, halo: false },
  { head: 10, headRows: 13, body: 8, bodyRows: 9, ear: 5, eyeGap: 2, eyeWidth: 3, eyeRows: 5, smile: 3, bolts: true, arm: 7, chest: 3, halo: true },
];

/** Antenna stem rows: the pet sleeps with it folded, stands with it up, and stretches it when the streak is long. */
const STEM: Record<Pet["pose"], number> = { settled: 0, up: 2, tall: 4 };

/** Two dashes asleep, bars awake, and a pair of arcs when the streak is long. */
function eyes(g: Grid, top: number, f: Frame, pose: Pet["pose"]): void {
  const middle = top + Math.floor((f.eyeRows - 1) / 2);
  if (pose === "settled") {
    g.span(f.eyeGap, f.eyeGap + f.eyeWidth, middle);
    return;
  }
  if (pose === "up") {
    for (let r = 0; r < f.eyeRows; r++) g.span(f.eyeGap, f.eyeGap + f.eyeWidth - 1, top + r, "E");
    return;
  }
  const w = f.eyeWidth + 1;
  g.span(f.eyeGap + 1, f.eyeGap + w - 2, middle, "E");
  g.pair(f.eyeGap, middle + 1, "E");
  g.pair(f.eyeGap + w - 1, middle + 1, "E");
}

function mouth(g: Grid, y: number, f: Frame, pose: Pet["pose"]): void {
  if (pose === "settled") {
    g.pair(0, y);
    return;
  }
  if (pose === "up") {
    g.span(0, f.smile - 1, y + 1);
    g.pair(f.smile, y);
    return;
  }
  g.span(0, f.smile, y);
  g.span(0, f.smile, y + 1);
}

function ears(g: Grid, f: Frame, headTop: number, pose: Pet["pose"]): void {
  const height = pose === "settled" ? Math.max(1, f.ear - 2) : f.ear;
  for (let r = 0; r < height; r++) {
    const y = headTop - height + r;
    for (let k = 0; k <= r; k++) {
      const far = f.head - 1 - k;
      const lining = f.ear >= 4 && pose !== "settled" && r >= 2 && k >= 1 && k < r;
      g.pair(far, y, lining ? "A" : "K");
    }
  }
}

function antenna(g: Grid, headTop: number, pose: Pet["pose"]): number {
  const stem = STEM[pose];
  for (let r = 0; r < stem; r++) g.pair(0, headTop - 1 - r);
  const tip = headTop - stem - 2;
  g.span(0, 0, tip, "A");
  g.span(0, 0, tip + 1, "A");
  return tip;
}

function arms(g: Grid, f: Frame, bodyTop: number, pose: Pet["pose"]): void {
  if (f.arm === 0) return;
  const reach = f.body;
  g.pair(reach, bodyTop + 1);
  for (let r = 0; r < f.arm; r++) {
    const y = bodyTop + 1 + r;
    g.set(MID - 1 - reach - 1, y, "K");
    g.set(MID - 1 - reach - 2, y, "K");
    if (pose === "tall") continue;
    g.set(MID + reach + 1, y, "K");
    g.set(MID + reach + 2, y, "K");
  }
  if (pose !== "tall") return;
  const out = f.head + 3;
  for (let far = reach; far <= out; far++) {
    g.set(MID + far, bodyTop + 1, "K");
    g.set(MID + far, bodyTop + 2, "K");
  }
  for (let y = bodyTop - 5; y <= bodyTop + 2; y++) {
    g.set(MID + out - 1, y, "K");
    g.set(MID + out, y, "K");
  }
  g.set(MID + out - 2, bodyTop - 5, "K");
  g.set(MID + out + 1, bodyTop - 5, "K");
}

/** A cat's tail on the left, longer as the pet grows. It rises behind the arm, with a gap between them. */
function tail(g: Grid, f: Frame, index: number): void {
  if (!f.body) return;
  const length = 2 + index;
  const lift = FLOOR - 3;
  for (let far = f.body; far <= f.body + 5; far++) {
    g.set(MID - 1 - far, lift, "K");
    g.set(MID - 1 - far, lift - 1, "K");
  }
  for (let r = 0; r < length; r++) {
    const tip = index >= 4 && r >= length - 2;
    for (const far of [f.body + 4, f.body + 5]) g.set(MID - 1 - far, lift - 2 - r, tip ? "A" : "K");
  }
}

/** The sleeping mark: a Z that floats beside the head while the streak is cold. */
function sleep(g: Grid, f: Frame, headTop: number): void {
  const x = MID + f.head + 1;
  const y = headTop - 3;
  for (let k = 0; k < 4; k++) g.set(x + k, y, "K");
  g.set(x + 3, y + 1, "K");
  g.set(x + 2, y + 2, "K");
  g.set(x + 1, y + 3, "K");
  for (let k = 0; k < 4; k++) g.set(x + k, y + 4, "K");
}

function egg(g: Grid, pose: Pet["pose"]): void {
  const halves = [2, 3, 4, 4, 5, 5, 5, 4, 3];
  const top = FLOOR - halves.length + 1;
  g.silhouette(top, halves);
  g.set(MID - 3, top + 4, "A");
  g.set(MID - 2, top + 5, "A");
  g.set(MID - 1, top + 4, "A");
  g.set(MID, top + 5, "A");
  g.set(MID + 1, top + 4, "A");
  g.set(MID + 2, top + 5, "A");
  if (pose === "tall") {
    for (const side of [-1, 1]) {
      const x = side < 0 ? MID - 8 : MID + 7;
      g.set(x, top + 2, "A");
      g.set(x - 1, top + 3, "A");
      g.set(x + 1, top + 3, "A");
      g.set(x, top + 3, "A");
      g.set(x, top + 4, "A");
    }
  }
}

/** A floor line under the feet. The last stage stands on a thicker plinth. */
function floor(g: Grid, index: number): void {
  g.span(0, 17, FLOOR + 1);
  if (index === FRAMES.length - 1) g.span(0, 13, FLOOR + 2);
}

function robot(index: number, pose: Pet["pose"]): Grid {
  const g = new Grid();
  if (index === 0) {
    egg(g, pose);
    floor(g, index);
    return g;
  }
  const f = FRAMES[index];
  const bodyTop = f.body ? FLOOR - 1 - f.bodyRows : FLOOR - 1;
  const headTop = f.body ? bodyTop - f.headRows + 1 : FLOOR - 1 - f.headRows;

  ears(g, f, headTop, pose);
  const tip = antenna(g, headTop, pose);
  g.box(headTop, f.headRows, f.head);
  if (f.body) g.box(bodyTop, f.bodyRows, f.body);
  arms(g, f, bodyTop, pose);
  tail(g, f, index);

  const eyeTop = headTop + 2;
  eyes(g, eyeTop, f, pose);
  mouth(g, eyeTop + f.eyeRows + 1, f, pose);

  if (f.bolts) {
    const mid = headTop + Math.floor(f.headRows / 2);
    for (let r = -1; r <= 1; r++) g.pair(f.head, mid + r);
  }
  if (f.chest) {
    const lamp = Math.min(f.chest, 3);
    for (let r = 0; r < 2; r++) g.span(0, lamp - 1, bodyTop + 2 + r, "A");
  }

  const feetGap = f.body ? Math.max(1, f.body - 3) : Math.max(1, f.head - 4);
  for (const y of [FLOOR - 1, FLOOR]) g.span(feetGap, feetGap + 2, y);

  const top = Math.min(tip, headTop - (pose === "settled" ? Math.max(1, f.ear - 2) : f.ear));
  if (pose === "settled") sleep(g, f, headTop);
  if (f.halo) {
    const ring = [4, 7, 8, 8, 7, 4];
    const haloTop = top - 3;
    ring.forEach((half, i) => {
      if (i !== 0 && i !== ring.length - 1) {
        g.pair(half - 1, haloTop + i - 1, "A");
        return;
      }
      g.span(0, half - 1, haloTop + i - 1, "A");
    });
  }
  floor(g, index);
  return g;
}

export const PET_WIDTH = GRID_W * PX;
export const PET_HEIGHT = GRID_H * PX;

function mixHex(hex: string, target: number, amount: number): string {
  const value = parseInt(hex.slice(1), 16);
  const channel = (shift: number) => {
    const from = (value >> shift) & 255;
    const to = (target >> shift) & 255;
    return Math.round(from * (1 - amount) + to * amount);
  };
  return `#${[channel(16), channel(8), channel(0)].map((part) => part.toString(16).padStart(2, "0")).join("")}`.toUpperCase();
}

function rect(x: number, y: number, w: number, h: number, fill: string, kind?: PetShape["kind"]): PetShape {
  return { x: x * PX, y: y * PX, w: w * PX, h: h * PX, opacity: 1, fill, ...(kind ? { kind } : {}) };
}

/** The handheld glass: a dark shell with clipped corners and a tinted pane inside it. */
function screen(glass: string): PetShape[] {
  return [
    rect(1, 0, GRID_W - 2, GRID_H, SHELL, "screen"),
    rect(0, 1, GRID_W, GRID_H - 2, SHELL, "screen"),
    rect(1, 1, GRID_W - 2, GRID_H - 2, glass, "screen"),
  ];
}

function raster(grid: Grid, accent: string, ink: string): PetShape[] {
  const colours: Record<Ink, string> = { K: ink, A: accent, E: ink };
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
      if (run && run.fill === fill && run.kind === kind && run.x + run.w === x * PX) {
        run.w += PX;
        continue;
      }
      flush();
      run = { x: x * PX, y: y * PX, w: PX, h: PX, opacity: 1, fill, ...(kind ? { kind } : {}) };
    }
    flush();
  }
  return shapes;
}

/** Bricks on the ground beside the floor line, one per step of build, centred under the creature. */
function bricks(count: number): { x: number; w: number }[] {
  const width = 4;
  const gap = 2;
  const total = count * width + (count - 1) * gap;
  const left = (GRID_W - total) / 2;
  return Array.from({ length: count }, (_, i) => ({ x: left + i * (width + gap), w: width }));
}

const BUILD: { x: number; w: number }[][] = [[], bricks(1), bricks(3), bricks(5)];
const BRICK_TOP = FLOOR + 4;

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
  let best: { key: (typeof MEASURED_TOOLS)[number]; tokens: number } | null = null;
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
  const tint = lineage && lineage.key !== "mix" ? TOOL_COLORS[lineage.key as (typeof MEASURED_TOOLS)[number]] : null;
  const glass = tint ? mixHex(tint, 0xdde4bc, 0.78) : GLASS;

  const shapes = [...screen(glass), ...raster(robot(index, pose), tint ?? NEUTRAL_ACCENT, INK)];
  for (const block of BUILD[build]) shapes.push(rect(block.x, BRICK_TOP, block.w, 2, INK));

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
        `<rect x="${shape.x}" y="${shape.y}" width="${shape.w}" height="${shape.h}" rx="0.6" fill="${shape.fill}" fill-opacity="${shape.opacity}"${shape.kind ? ` class="${shape.kind}"` : ""}/>`,
    )
    .join("");
  const label = pet.lineageName ? `${pet.stageName} · ${pet.lineageName}` : pet.stageName;
  return `<svg class="${className}" viewBox="0 0 ${pet.width} ${pet.height}" role="img" aria-label="${esc(label)}">${rects}</svg>`;
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
        `<rect x="${left + shape.x * scale}" y="${top + shape.y * scale}" width="${shape.w * scale}" height="${shape.h * scale}" rx="${0.6 * scale}" fill="${shape.fill}" fill-opacity="${shape.opacity}"${shape.kind ? ` class="${shape.kind}"` : ""}/>`,
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
