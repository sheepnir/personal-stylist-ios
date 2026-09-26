/**
 * Node-pool Vitest project (existing unit/integration stubs).
 */

import { fileURLToPath } from 'node:url';
import { defineProject } from 'vitest/config';

export default defineProject({
  resolve: {
    alias: {
      'cloudflare:workers': fileURLToPath(
        new URL('./tests/cloudflare-runtime.ts', import.meta.url)
      ),
    },
  },
  test: {
    name: 'node',
    globals: true,
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    exclude: ['tests/spendLedger.concurrency.test.ts'],
  },
});
