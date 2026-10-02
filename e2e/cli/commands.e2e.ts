import { execFile, spawn } from 'node:child_process';
import { mkdtemp, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { test, expect } from 'e2e';

const run = promisify(execFile);
const root = fileURLToPath(new URL('../..', import.meta.url));

// Named `Keyhop`, an unknown command opens the Mac app. Named `keyhop`, it is the command.
async function keyhop() {
  const home = await mkdtemp(join(tmpdir(), 'keyhop-e2e-'));
  const binary = join(home, 'keyhop');
  await symlink(join(root, '.build/debug/Keyhop'), binary);
  return { binary, home };
}

async function once(binary: string, home: string, args: string[]) {
  try {
    const { stdout, stderr } = await run(binary, args, {
      env: { ...process.env, KEYHOP_DATA_DIR: home, KEYHOP_CLOUD_URL: 'http://127.0.0.1:9' },
      timeout: 60_000,
    });
    return { code: 0, out: stdout + stderr };
  } catch (error) {
    const failed = error as { code?: number; stdout?: string; stderr?: string; message?: string };
    return { code: failed.code ?? 1, out: String(failed.stdout ?? '') + String(failed.stderr ?? failed.message) };
  }
}

const commands: { name: string; args: string[]; says?: string[]; json?: boolean; has?: string[]; expectFailure?: boolean }[] = [
  { name: 'version', args: ['version'], says: ['.'] },
  { name: 'help', args: ['help'], says: ['Usage: keyhop', 'dashboard', '--port', 'mcp', 'work'] },
  { name: 'status', args: ['status', '--sample'], says: ['Claude Code'] },
  { name: 'status --json', args: ['status', '--sample', '--json'], json: true, has: ['tools', 'today', 'version'] },
  { name: 'usage', args: ['usage', '--range', 'today', '--no-read', '--json'], json: true, has: ['total', 'tools', 'sessions'] },
  { name: 'usage week', args: ['usage', '--range', 'week', '--no-read'], says: ['tokens'] },
  { name: 'work status', args: ['work', 'status', '--json'], json: true, has: ['enabled', 'roots'] },
  { name: 'budget list', args: ['budget', 'list', '--json'], json: true },
  { name: 'doctor', args: ['doctor', '--json'], json: true, has: ['tools'] },
  { name: 'cloud status', args: ['cloud', 'status', '--json'], json: true },
  { name: 'unknown command', args: ['definitely-not-a-command'], expectFailure: true, says: ['keyhop help'] },
  { name: 'unknown option', args: ['status', '--nope'], expectFailure: true, says: ['keyhop'] },
];

for (const command of commands) {
  test(`keyhop ${command.name}`, async () => {
    const { binary, home } = await keyhop();
    const result = await once(binary, home, command.args);
    expect(result.code === 0).toBe(!command.expectFailure);
    if (command.json) {
      const parsed = JSON.parse(result.out) as Record<string, unknown>;
      for (const key of command.has ?? []) expect(parsed).toHaveProperty(key);
    }
    for (const text of command.says ?? []) expect(result.out).toContain(text);
    for (const broken of ['undefined', 'NaN', '(null)', '—']) expect(result.out).not.toContain(broken);
  });
}

test('keyhop mcp offers status, usage and a recommendation', async () => {
  const { binary, home } = await keyhop();
  const requests = [
    { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'e2e', version: '1' } } },
    { jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} },
  ];
  const out = await new Promise<string>((resolve, reject) => {
    const child = spawn(binary, ['mcp'], {
      env: { ...process.env, KEYHOP_DATA_DIR: home, KEYHOP_CLOUD_URL: 'http://127.0.0.1:9' },
    });
    let text = '';
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error('keyhop mcp did not answer'));
    }, 30_000);
    child.stdout.on('data', (chunk) => { text += chunk; });
    child.stderr.on('data', (chunk) => { text += chunk; });
    child.on('close', () => {
      clearTimeout(timer);
      resolve(text);
    });
    child.stdin.write(requests.map((request) => JSON.stringify(request)).join('\n') + '\n');
    child.stdin.end();
  });
  for (const name of ['keyhop_status', 'keyhop_usage', 'keyhop_recommendation']) expect(out).toContain(name);
});
