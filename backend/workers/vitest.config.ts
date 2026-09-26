/**
 * Vitest workspace: node stubs + workerd pool for spend-ledger concurrency (#14).
 */

import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    projects: ['vitest.node.config.ts', 'vitest.workers-pool.config.ts'],
  },
});
