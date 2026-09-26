/**
 * Basic smoke tests for Workers backend (M0-09).
 */

import { describe, it, expect } from 'vitest';
import { authenticate } from '../src/auth.js';
import { handleHealth } from '../src/routes.js';
import type { Env } from '../src/types.js';
import { emptyLedger } from './helpers.js';

describe('Authentication', () => {
  const mockEnv: Env = {
    DEVICE_TOKEN: 'test-token-123',
    OPENROUTER_API_KEY: 'test-key',
    USAGE_LEDGER: emptyLedger(),
  };

  it('should reject request without Authorization header', async () => {
    const request = new Request('http://test.com/v1/usage');
    const result = await authenticate(request, mockEnv);
    
    expect(result).toBeInstanceOf(Response);
    if (result instanceof Response) {
      expect(result.status).toBe(401);
      const body = await result.json();
      expect(body.code).toBe('UNAUTHORIZED');
    }
  });

  it('should reject request with invalid token format', async () => {
    const request = new Request('http://test.com/v1/usage', {
      headers: { 'Authorization': 'InvalidFormat' },
    });
    const result = await authenticate(request, mockEnv);
    
    expect(result).toBeInstanceOf(Response);
    if (result instanceof Response) {
      expect(result.status).toBe(401);
    }
  });

  it('should reject request with wrong token', async () => {
    const request = new Request('http://test.com/v1/usage', {
      headers: { 'Authorization': 'Bearer wrong-token' },
    });
    const result = await authenticate(request, mockEnv);
    
    expect(result).toBeInstanceOf(Response);
    if (result instanceof Response) {
      expect(result.status).toBe(401);
    }
  });

  it('should accept request with correct token', async () => {
    const request = new Request('http://test.com/v1/usage', {
      headers: { 'Authorization': 'Bearer test-token-123' },
    });
    const result = await authenticate(request, mockEnv);
    
    expect(result).not.toBeInstanceOf(Response);
    if (!(result instanceof Response)) {
      expect(result.deviceToken).toBe('test-token-123');
    }
  });
});

describe('GET /health', () => {
  it('serializes status as a quoted JSON string (issue #90)', async () => {
    const request = new Request('http://test.com/health');
    const result = await handleHealth(request, {} as Env);
    expect(result.status).toBe(200);
    const raw = await result.text();
    expect(raw).toContain('"status":"ok"');
    const body = JSON.parse(raw) as { status?: unknown };
    expect(body.status).toBe('ok');
    expect(typeof body.status).toBe('string');
  });
});

describe('POST /v1/outfit/generate ledger reads', () => {
  it('does not touch USAGE_LEDGER on the deterministic path (#165)', async () => {
    const { handleGenerate } = await import(
      '../src/routes.js'
    );

    let kvGets = 0;
    const env: Env = {
      DEVICE_TOKEN: 'test-token-123',
      OPENROUTER_API_KEY: 'test-key',
      USAGE_LEDGER: {
        get: async () => {
          kvGets += 1;
          return null;
        },
      } as unknown as KVNamespace,
    };

    const wardrobe = [
      {
        id: 'a1000001-0001-4000-8000-000000000001',
        displayName: 'Navy Oxford Shirt',
        slot: 'TOP',
        readiness: 'READY',
        availability: 'AVAILABLE',
        formality: 3,
        warmth: 2,
        seasons: ['SPRING', 'SUMMER', 'FALL', 'WINTER'],
        colorPrimary: { family: 'navy', hex: '#1b3a6b', name: 'Navy' },
        pattern: 'SOLID',
        surface: 'SMOOTH',
      },
      {
        id: 'a1000001-0001-4000-8000-000000000010',
        displayName: 'Charcoal Trousers',
        slot: 'BOTTOM',
        readiness: 'READY',
        availability: 'AVAILABLE',
        formality: 3,
        warmth: 2,
        seasons: ['SPRING', 'SUMMER', 'FALL', 'WINTER'],
        colorPrimary: { family: 'gray', hex: '#444444', name: 'Charcoal' },
        pattern: 'SOLID',
        surface: 'SMOOTH',
      },
      {
        id: 'a1000001-0001-4000-8000-000000000020',
        displayName: 'White Sneakers',
        slot: 'FOOTWEAR',
        readiness: 'READY',
        availability: 'AVAILABLE',
        formality: 2,
        warmth: 2,
        seasons: ['SPRING', 'SUMMER', 'FALL', 'WINTER'],
        colorPrimary: { family: 'white', hex: '#f5f5f5', name: 'White' },
        pattern: 'SOLID',
        surface: 'SMOOTH',
      },
    ];

    const request = new Request('http://test.com/v1/outfit/generate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        wardrobe,
        context: {
          occasion: 'WORK_STANDARD',
          occasionFormality: 3,
          temperatureBand: 'MILD',
          precipitation: false,
        },
        anchorGarmentId: wardrobe[0].id,
        options: { requireSlots: ['TOP', 'BOTTOM', 'FOOTWEAR'] },
      }),
    });

    const auth = { deviceToken: 'test-token-123' };
    const response = await handleGenerate(request, env, auth);
    expect(response.status).toBe(200);
    expect(kvGets).toBe(0);
  });
});

describe('Types', () => {
  it('ships illustrative SPEND_CONFIG sample defaults', async () => {
    const { SPEND_CONFIG } = await import('../src/types.js');
    const { resolveSpendConfig } = await import('../src/spendConfig.js');

    expect(SPEND_CONFIG.softThresholdUSD).toBeLessThan(SPEND_CONFIG.dailyCapUSD);
    expect(resolveSpendConfig({})).toEqual({
      configError: false,
      dailyCapUSD: SPEND_CONFIG.dailyCapUSD,
      softThresholdUSD: SPEND_CONFIG.softThresholdUSD,
    });
  });

  it('lets env vars override the sample spend config', async () => {
    const { resolveSpendConfig } = await import('../src/spendConfig.js');

    expect(resolveSpendConfig({ DAILY_CAP_USD: '4', SOFT_THRESHOLD_USD: '3' })).toEqual({
      configError: false,
      dailyCapUSD: 4,
      softThresholdUSD: 3,
    });
    expect(resolveSpendConfig({ DAILY_CAP_USD: '4', SOFT_THRESHOLD_USD: '9' })).toEqual({
      configError: false,
      dailyCapUSD: 4,
      softThresholdUSD: 4,
    });
    expect(resolveSpendConfig({ DAILY_CAP_USD: 'abc' })).toEqual({ configError: true });
  });
});
