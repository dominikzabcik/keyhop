/**
 * The commands, run the way a person runs them.
 *
 * Only the commands that read are run here. Nothing switches an account, signs a tool out, or
 * touches the cloud, and every run is given its own empty data folder, so a check can never reach
 * a real login, a real database, or the real keyhop.app.
 */

import { execFile } from "node:child_process";
import { mkdtemp, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const run = promisify(execFile);

/** Text that means something never resolved, wherever it appears. */
const BROKEN = ["undefined", "NaN", "(null)", "Optional(", "nil)", "—"];

/**
 * Each command: how it is run, and what has to be true of what it prints.
 *
 * `json` means the output has to parse, and `has` names keys that have to be in it. `says` names
 * text that has to appear in plain output. Nothing here needs the network.
 */
const COMMANDS = [
  { name: "version", args: ["version"], says: ["."] },
  { name: "help", args: ["help"], says: ["Usage: keyhop", "status", "usage", "mcp", "doctor"] },
  { name: "status", args: ["status", "--sample"], says: ["Claude Code", "%"] },
  { name: "status --json", args: ["status", "--sample", "--json"], json: true, has: ["tools", "today", "version"] },
  { name: "recommend", args: ["recommend", "--sample", "--json"], json: true, allowFailure: true },
  { name: "usage", args: ["usage", "--range", "today", "--no-read", "--json"], json: true, has: ["total"] },
  { name: "usage week", args: ["usage", "--range", "week", "--no-read"], says: ["tokens"] },
  { name: "budget list", args: ["budget", "list", "--json"], json: true },
  { name: "doctor", args: ["doctor", "--json"], json: true, has: ["tools"] },
  { name: "cloud status", args: ["cloud", "status", "--json"], json: true },
  { name: "unknown command", args: ["definitely-not-a-command"], expectFailure: true, says: ["keyhop help"] },
  { name: "mcp is offered", args: ["help"], says: ["mcp"] },
  { name: "unknown option", args: ["status", "--nope"], expectFailure: true, says: ["keyhop"] },
];

/** The three tools `keyhop mcp` serves, which an agent asks for by name. */
const MCP_TOOLS = ["keyhop_status", "keyhop_usage", "keyhop_recommendation"];

async function once(binary, args, home) {
  try {
    const { stdout, stderr } = await run(binary, args, {
      env: { ...process.env, KEYHOP_DATA_DIR: home, KEYHOP_CLOUD_URL: "http://127.0.0.1:9" },
      timeout: 60_000,
    });
    return { code: 0, out: stdout + stderr };
  } catch (error) {
    return { code: error.code ?? 1, out: String(error.stdout ?? "") + String(error.stderr ?? error.message) };
  }
}

/** Asks `keyhop mcp` for its tools the way an agent does, over stdin and stdout. */
async function askMCP(binary, home) {
  const requests = [
    { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "checks", version: "1" } } },
    { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} },
  ];
  const { code, out } = await new Promise((resolve) => {
    const child = execFile(binary, ["mcp"], {
      env: { ...process.env, KEYHOP_DATA_DIR: home },
      timeout: 30_000,
    }, (error, stdout, stderr) => resolve({ code: error?.code ?? 0, out: stdout + stderr }));
    child.stdin.write(requests.map((request) => JSON.stringify(request)).join("\n") + "\n");
    child.stdin.end();
  });
  return { code, out };
}

export async function checkCommands(built) {
  const found = [];
  const home = await mkdtemp(join(tmpdir(), "keyhop-checks-"));
  // Named `Keyhop`, the binary is the Mac app and an unknown command opens it. Named `keyhop`, as
  // the installer leaves it on PATH, it is the command. The commands are what is being checked.
  const binary = join(home, "keyhop");
  await symlink(built, binary);
  const fault = (name, kind, detail) => found.push({ screen: `cli/${name}`, width: "-", kind, detail });

  try {
    for (const command of COMMANDS) {
      const { code, out } = await once(binary, command.args, home);
      const failed = code !== 0;
      if (command.expectFailure && !failed) fault(command.name, "cli", "should have refused, and didn't");
      if (!command.expectFailure && failed && !command.allowFailure) {
        fault(command.name, "cli", `exited ${code}: ${out.trim().slice(0, 160)}`);
        continue;
      }

      for (const phrase of command.says ?? []) {
        if (!out.includes(phrase)) fault(command.name, "cli", `never says "${phrase}"`);
      }
      for (const bad of BROKEN) {
        if (out.includes(bad)) fault(command.name, "cli", `prints "${bad}"`);
      }
      if (command.json && !failed) {
        const body = out.slice(out.indexOf("{") === -1 ? 0 : out.indexOf("{"));
        try {
          const parsed = JSON.parse(body);
          for (const key of command.has ?? []) {
            if (!(key in parsed)) fault(command.name, "cli", `its JSON has no "${key}"`);
          }
        } catch (error) {
          fault(command.name, "cli", `--json printed something that isn't JSON: ${error.message}`);
        }
      }
    }

    // The agent side: three read-only tools, named the same way for as long as agents call them.
    const mcp = await askMCP(binary, home);
    for (const tool of MCP_TOOLS) {
      if (!mcp.out.includes(tool)) fault("mcp", "cli", `keyhop mcp never offers ${tool}`);
    }
    if (!mcp.out.includes('"jsonrpc"')) fault("mcp", "cli", "keyhop mcp answered nothing an agent could read");
  } finally {
    await rm(home, { recursive: true, force: true });
  }
  return found;
}
