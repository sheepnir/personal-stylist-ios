/**
 * Input-validation / abuse-control tests (#170, #171).
 */

import { describe, it, expect } from 'vitest';
import worker from '../src/index.js';
import {
  readJsonWithLimit,
  rejectImagePayload,
  enforceRateLimit,
  MAX_BODY_BYTES,
  RATE_LIMIT_MAX,
} from '../src/validation.js';
import type { Env } from '../src/types.js';

const ctx = {} as ExecutionContext;
const TOKEN = 'test-token-123';

class MemoryKV {
  store = new Map<string, string>();
  async get(key: string, type?: 'json'): Promise<unknown> {
    const raw = this.store.get(key);
    if (raw === undefined) return null;
    return type === 'json' ? JSON.parse(raw) : raw;
  }
  async put(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
}

function env(kv = new MemoryKV()): Env {
  let requests = 0;
  return {
    REQUEST_RATE_LIMITER: { limit: async () => ({ success: ++requests <= RATE_LIMIT_MAX }) },
    DEVICE_TOKEN: TOKEN,
    OPENROUTER_API_KEY: 'k',
    USAGE_LEDGER: kv as unknown as KVNamespace,
  };
}

function post(body: string): Request {
  return new Request('http://test.com/v1/outfit/generate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${TOKEN}` },
    body,
  });
}

describe('readJsonWithLimit — size cap (#170)', () => {
  it('rejects a body larger than MAX_BODY_BYTES with 413', async () => {
    const big = JSON.stringify({ blob: 'x'.repeat(MAX_BODY_BYTES + 10) });
    const req = new Request('http://test.com/', { method: 'POST', body: big });
    const result = await readJsonWithLimit(req);
    expect(result).toBeInstanceOf(Response);
    if (result instanceof Response) expect(result.status).toBe(413);
  });

  it('rejects invalid JSON with 400', async () => {
    const req = new Request('http://test.com/', { method: 'POST', body: '{not json' });
    const result = await readJsonWithLimit(req);
    expect(result).toBeInstanceOf(Response);
    if (result instanceof Response) expect(result.status).toBe(400);
  });

  it('parses a small valid body', async () => {
    const req = new Request('http://test.com/', { method: 'POST', body: '{"a":1}' });
    const result = await readJsonWithLimit(req);
    expect(result).toEqual({ a: 1 });
  });
});

describe('rejectImagePayload — VF-03 fail-closed (#171)', () => {
  it('rejects an image-bearing key', () => {
    const res = rejectImagePayload({ wardrobe: [{ id: '1', imageData: 'abc' }] });
    expect(res).toBeInstanceOf(Response);
    expect(res?.status).toBe(415);
  });

  it('rejects all-lowercase compound keys (#36)', () => {
    expect(rejectImagePayload({ imagepath: 'x' })?.status).toBe(415);
    expect(rejectImagePayload({ imageblob: 'x' })?.status).toBe(415);
    expect(rejectImagePayload({ wardrobe: [{ garmentimages: [] }] })?.status).toBe(415);
    expect(rejectImagePayload({ pixelData: 'x' })?.status).toBe(415);
    expect(rejectImagePayload({ image_blob: 'x' })?.status).toBe(415);
    expect(rejectImagePayload({ 'image-blob': 'x' })?.status).toBe(415);
  });

  it('rejects imagery, photography, and thumbs_up spellings (#36)', () => {
    expect(rejectImagePayload({ imagery: 'x' })?.status).toBe(415);
    expect(rejectImagePayload({ photography: true })?.status).toBe(415);
    expect(rejectImagePayload({ thumbs_up: 1 })?.status).toBe(415);
  });

  it('rejects a nested thumbnail key', () => {
    const res = rejectImagePayload({ context: { garment: { thumbnail: 'x' } } });
    expect(res?.status).toBe(415);
  });

  it('rejects a data: image URL value', () => {
    const res = rejectImagePayload({ note: 'data:image/png;base64,iVBORw0KGgo=' });
    expect(res?.status).toBe(415);
  });

  it('rejects consent timestamp at the wrong path or with bad values (#36)', () => {
    expect(rejectImagePayload({ wardrobeImagesAcceptedAt: '2026-09-20T12:00:00Z' })?.status).toBe(415);
    expect(
      rejectImagePayload({
        privacyConsent: { wardrobeImagesAcceptedAt: 'not-a-date', policyVersion: '1' },
      })?.status
    ).toBe(415);
    expect(
      rejectImagePayload({
        privacyConsent: {
          wardrobeImagesAcceptedAt: `${'2026-09-20T12:00:00Z'}${'0'.repeat(40)}`,
          policyVersion: '1',
        },
      })?.status
    ).toBe(415);
  });

  it('allows the named consent exception on the full path (#36)', () => {
    const res = rejectImagePayload({
      privacyConsent: {
        wardrobeImagesAcceptedAt: '2026-09-20T12:00:00Z',
        policyVersion: '2026-09-01',
      },
      wardrobe: [{ garmentId: '1', slot: 'TOP', color: 'navy' }],
    });
    expect(res).toBeNull();
  });

  it('allows a clean wardrobe payload', () => {
    const res = rejectImagePayload({
      wardrobe: [{ garmentId: '1', slot: 'TOP', color: 'navy' }],
      context: { occasion: 'WORK_STANDARD' },
    });
    expect(res).toBeNull();
  });
});

describe('enforceRateLimit (#170)', () => {
  it('allows up to the limit then returns 429 with resetsAt', async () => {
    const e = env();
    let last: Response | null = null;
    for (let i = 0; i < RATE_LIMIT_MAX; i++) {
      last = await enforceRateLimit(TOKEN, e);
      expect(last).toBeNull();
    }
    const blocked = await enforceRateLimit(TOKEN, e);
    expect(blocked).toBeInstanceOf(Response);
    expect(blocked?.status).toBe(429);
    if (blocked) {
      const body = (await blocked.json()) as { resetsAt?: string };
      expect(typeof body.resetsAt).toBe('string');
    }
  });
});

describe('worker end-to-end validation', () => {
  it('rejects a generate request carrying an image payload (#171)', async () => {
    const req = post(JSON.stringify({ wardrobe: [{ garmentId: '1', imageData: 'x' }], context: {} }));
    const res = await worker.fetch(req, env(), ctx);
    expect(res.status).toBe(415);
    const body = (await res.json()) as { code?: string };
    expect(body.code).toBe('IMAGE_NOT_ALLOWED');
  });
});


describe('review regressions', () => {
  it('cancels an oversized stream without reading the entire body', async () => {
    let cancelled = false;
    let pulls = 0;
    const stream = new ReadableStream({
      pull(controller) { pulls++; controller.enqueue(new Uint8Array(32)); },
      cancel() { cancelled = true; },
    });
    const request = new Request('http://test/', { method: 'POST', body: stream, duplex: 'half' } as RequestInit);
    const result = await readJsonWithLimit(request, 64);
    expect((result as Response).status).toBe(413);
    expect(cancelled).toBe(true);
    expect(pulls).toBeLessThanOrEqual(4);
  });
  it.each(['null', '[]', '123', '"hello"'])('rejects non-object root %s', async (body) => {
    expect((await readJsonWithLimit(post(body)) as Response).status).toBe(400);
  });
  it('rejects deep image payloads and camel-case image keys', () => {
    let body: unknown = { imageUrl: 'https://example.test/x.png' };
    for (let i = 0; i < 100; i++) body = { nested: body };
    expect(rejectImagePayload(body)?.status).toBe(415);
    expect(rejectImagePayload({ originalImage: 'x' })?.status).toBe(415);
    expect(rejectImagePayload({ value: '  DATA:IMAGE/png;base64,x' })?.status).toBe(415);
  });
  it('fails closed when the limiter is unavailable', async () => {
    const e = env();
    delete e.REQUEST_RATE_LIMITER;
    expect((await enforceRateLimit(TOKEN, e))?.status).toBe(503);
    e.REQUEST_RATE_LIMITER = { limit: async () => { throw new Error('offline'); } };
    expect((await enforceRateLimit(TOKEN, e))?.status).toBe(503);
  });
});
