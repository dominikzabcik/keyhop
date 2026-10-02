import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { E2EConfig } from 'e2e';
import { web } from '@e2e-dev/web';

const root = dirname(fileURLToPath(import.meta.url));

// The sample window picks its own session key and prints it as JSON. A fixed port lets the
// runner own the address; the tests read the key back out of the log.
const app = {
  url: 'http://127.0.0.1:0',
  command: {
    executable: join(root, '.build/debug/Keyhop'),
    args: ['dashboard', '--sample', '--no-open', '--json', '--port', '{port}'],
    cwd: root,
    startupTimeout: 30_000,
    log: '.e2e/logs/dashboard.log',
  },
};

export default {
  // Swift already owns `Tests/`. On a case-insensitive disk that is the same folder as `tests/`.
  tests: 'e2e/**/*.e2e.ts',
  workers: 1,
  timeout: 60_000,
  targets: [
    {
      name: 'window',
      engine: web({ viewport: { width: 1100, height: 800 } }),
      app,
    },
  ],
} satisfies E2EConfig;
