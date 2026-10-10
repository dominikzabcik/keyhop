// Prints the Swift literal for `CloudPet.sample` from the same code the website runs, so the
// sample creature in the app's windows is the one keyhop.app would draw for those totals.
//
//   cd cloud && node scripts/pet-sample.mjs > /tmp/sample.swift
//
// Paste the output over the `static let sample = CloudPet(` block in Sources/Keyhop/Cloud/CloudAPI.swift.
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const dir = mkdtempSync(join(tmpdir(), "keyhop-pet-"));
const bundle = join(dir, "pet.mjs");
execFileSync("npx", ["esbuild", "src/pet.ts", "--bundle", "--platform=node", "--format=esm", "--external:cloudflare:*", `--outfile=${bundle}`, "--log-level=warning"], { stdio: "inherit" });
const { petFrom } = await import(pathToFileURL(bundle).href);

const pet = petFrom({ tokens: 800_000_000, tools: { claude: 800_000_000 }, streak: 12, commits: 140 });
const grouped = (n) => n.toLocaleString("en-US").replaceAll(",", "_");
const str = (value) => (value === null || value === undefined ? "nil" : JSON.stringify(value));
const lines = [
  "    static let sample = CloudPet(",
  `        stage: ${str(pet.stage)}, stageName: ${str(pet.stageName)}, lineage: ${str(pet.lineage)}, lineageName: ${str(pet.lineageName)},`,
  `        pose: ${str(pet.pose)}, build: ${pet.build}, tokens: ${grouped(pet.tokens)}, commits: ${pet.commits}, streak: ${pet.streak},`,
  `        next: ${pet.next ? `Step(label: ${str(pet.next.label)}, tokens: ${grouped(pet.next.tokens)})` : "nil"},`,
  `        width: ${pet.width}, height: ${pet.height},`,
  "        shapes: [",
  ...pet.shapes.map((s) => `            Shape(x: ${s.x}, y: ${s.y}, w: ${s.w}, h: ${s.h}, opacity: ${s.opacity}, fill: ${str(s.fill)}, kind: ${str(s.kind ?? null)}),`),
  "        ]",
  "    )",
];
writeFileSync(1, `${lines.join("\n")}\n`);
