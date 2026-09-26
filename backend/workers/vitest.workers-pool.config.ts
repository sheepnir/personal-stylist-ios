/**
 * Workerd pool for spend-ledger concurrency tests (#14).
 */

import { fileURLToPath } from 'node:url';
import { cloudflareTest } from '@cloudflare/vitest-plugin';
import { defineProject } from 'vitest/config';

export default defineProject({
  plugins: [
    cloudflareTest({
      main: fileURLToPath(new URL('./src/index.ts', import.meta.url)),
      wrangler: {
        configPath: fileURLToPath(new URL('./wrangler.toml', import.meta.url)),
      },
    }),
  ],
  test: {
    name: 'workers-pool',
    globals: true,
    include: ['tests/spendLedger.concurrency.test.ts'],
  },
});
