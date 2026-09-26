import { describe, expect, it } from 'vitest';
import {
  buildProviderSuccessGeneration,
  CURRENT_STYLIST_PROMPT_VERSION,
  getStylistPromptByVersion,
} from '@personal-stylist/outfit-engine';
import { handleGenerate } from '../src/routes.js';
import type { Env } from '../src/types.js';
import { emptyLedger } from './helpers.js';

describe('generation.promptVersion', () => {
  it('deterministic Worker generate keeps promptVersion none', async () => {
    const env: Env = {
      DEVICE_TOKEN: 'test-token-123',
      OPENROUTER_API_KEY: 'test-key',
      USAGE_LEDGER: emptyLedger(),
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

    const response = await handleGenerate(request, env, {
      deviceToken: 'test-token-123',
    });
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      generation?: { promptVersion?: string; candidateSetHash?: string | null };
    };
    expect(body.generation?.promptVersion).toBe('none');
    expect(body.generation?.candidateSetHash).toBeTruthy();
  });

  it('provider-path generation metadata references a repo prompt module', () => {
    const meta = buildProviderSuccessGeneration({
      candidateSetHash: 'deadbeef',
      latencyMs: 12,
    });
    expect(meta.promptVersion).toBe(CURRENT_STYLIST_PROMPT_VERSION);
    expect(getStylistPromptByVersion(meta.promptVersion)).toBeDefined();
    expect(meta.candidateSetHash).toBe('deadbeef');
  });
});
