/**
 * Vitest workspace: node stubs + workerd pool for spend-ledger concurrency (#14).
 */

import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // workers-pool uses cloudflareTest(); npm test also runs it explicitly (second vitest invocation).
    projects: ['vitest.node.config.ts', 'vitest.workers-pool.config.ts'],
  },
});
