import { execFileSync, spawn } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const cloud = join(dirname(fileURLToPath(import.meta.url)), '../../cloud');
const port = process.env.PORT;
if (!port) {
  console.error('PORT is required');
  process.exit(1);
}

const wrangler = join(cloud, 'node_modules/wrangler/bin/wrangler.js');
execFileSync(process.execPath, [wrangler, 'd1', 'migrations', 'apply', 'switchr', '--local'], {
  cwd: cloud,
  stdio: 'inherit',
});

const child = spawn(process.execPath, [wrangler, 'dev', '--port', port, '--ip', '127.0.0.1'], {
  cwd: cloud,
  stdio: 'inherit',
});

const stop = () => {
  child.kill('SIGTERM');
};
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
child.on('exit', (code) => process.exit(code ?? 0));
