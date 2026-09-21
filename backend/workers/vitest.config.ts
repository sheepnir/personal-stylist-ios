/**
 * Vitest configuration for Workers tests.
 */

import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  resolve: { alias: { "cloudflare:workers": fileURLToPath(new URL("./tests/cloudflare-runtime.ts", import.meta.url)) } },
  test: {
    globals: true,
    environment: 'node',
  },
});
