import { describe, expect, it, vi } from 'vitest';
import { callOpenRouter, type OpenRouterRequest } from '../src/openrouter.js';
import { PHASE_A_NO_LIVE_PROVIDER } from '../src/phaseA.js';
import type { Env } from '../src/types.js';

describe('phase A live provider guard', () => {
  it('PHASE_A_NO_LIVE_PROVIDER stays enabled for issue #26 phase A', () => {
    expect(PHASE_A_NO_LIVE_PROVIDER).toBe(true);
  });

  it('callOpenRouter fails closed without calling fetch', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockRejectedValue(
      new Error('fetch must not run in phase A'),
    );

    const env: Env = {
      DEVICE_TOKEN: 't',
      OPENROUTER_API_KEY: 'secret-key',
    };

    const request: OpenRouterRequest = {
      model: 'mock/stylist-v0',
      messages: [{ role: 'user', content: 'test' }],
    };

    await expect(callOpenRouter(request, env)).rejects.toThrow(/Phase A forbids live provider/);
    expect(fetchSpy).not.toHaveBeenCalled();
    fetchSpy.mockRestore();
  });
});
