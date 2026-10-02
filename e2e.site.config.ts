import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { E2EConfig } from 'e2e';
import { web } from '@e2e-dev/web';

const root = dirname(fileURLToPath(import.meta.url));

// One local website, two sizes. The same command object is what makes the runner share the process.
const site = {
  url: 'http://127.0.0.1:0',
  command: {
    executable: process.execPath,
    args: [join(root, 'e2e/site/serve.mjs')],
    env: { PORT: '{port}' },
    cwd: root,
    startupTimeout: 120_000,
    log: '.e2e/logs/site.log',
  },
};

export default {
  tests: 'e2e/site/**/*.e2e.ts',
  workers: 1,
  timeout: 60_000,
  targets: [
    { name: 'laptop', engine: web({ viewport: { width: 1280, height: 800 } }), app: site },
    { name: 'phone', engine: web({ viewport: { width: 390, height: 844 } }), app: site },
  ],
} satisfies E2EConfig;
