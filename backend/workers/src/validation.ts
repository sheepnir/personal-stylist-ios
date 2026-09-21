/**
 * Request validation and abuse controls for content endpoints.
 *
 * Addresses:
 * - #170: schema/size validation and rate limiting (previously absent).
 * - #171: fail-closed rejection of image/thumbnail payloads (VF-03). The
 *   backend holds no user image content, so any image-bearing field is
 *   rejected before the engine runs.
 */

import type { Env, ProblemDetail } from './types.js';
import { hashToken } from './usage.js';

/** Maximum accepted request body size for content endpoints. */
export const MAX_BODY_BYTES = 512 * 1024; // 512 KiB

/** Rate limit: max authenticated content requests per period. */
export const RATE_LIMIT_MAX = 60;
export const RATE_LIMIT_WINDOW_SECONDS = 60;

/** Field names that indicate an image/thumbnail payload (case-insensitive). */
const IMAGE_KEY_PATTERN =
  /(^|[^a-z])(image|imagedata|imagebase64|thumbnail|thumb|photo|masterimage|processedimage|pixeldata|bitmap)([^a-z]|$)/i;

/** Detects data: URLs and common raw image encodings inside string values. */
const IMAGE_VALUE_PATTERN = /^data:image\/|^\/9j\/|^iVBORw0KGgo/i;

function problem(status: number, title: string, code: string, detail: string, extra: Record<string, unknown> = {}): Response {
  const body: ProblemDetail = {
    type: 'about:blank',
    title,
    status,
    detail,
    code,
    dataPreserved: true,
    ...extra,
  };
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/problem+json' },
  });
}

/**
 * Read and parse a JSON body, enforcing a maximum size (#170).
 * Returns the parsed value or a Response (413 / 400) to return to the client.
 */
export async function readJsonWithLimit(
  request: Request,
  maxBytes = MAX_BODY_BYTES
): Promise<unknown | Response> {
  const declared = request.headers.get('Content-Length');
  if (declared && Number(declared) > maxBytes) {
    return payloadTooLarge(maxBytes);
  }

  const reader = request.body?.getReader();
  if (!reader) return problem(400, 'Bad Request', 'INVALID_REQUEST', 'Request body is empty.');
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maxBytes) {
        await reader.cancel();
        return payloadTooLarge(maxBytes);
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  const raw = new TextDecoder().decode(bytes);

  if (!raw) {
    return problem(400, 'Bad Request', 'INVALID_REQUEST', 'Request body is empty.');
  }

  try {
    const parsed: unknown = JSON.parse(raw);
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return problem(400, 'Bad Request', 'INVALID_REQUEST', 'Request body must be a JSON object.');
    }
    return parsed;
  } catch {
    return problem(400, 'Bad Request', 'INVALID_REQUEST', 'Request body must be valid JSON.');
  }
}

function payloadTooLarge(maxBytes: number): Response {
  return problem(
    413,
    'Payload Too Large',
    'PAYLOAD_TOO_LARGE',
    `Request body exceeds the ${maxBytes}-byte limit.`
  );
}

/**
 * Fail-closed image rejection (#171 / VF-03). Recursively scans the parsed body
 * for image-bearing keys or data-URL/base64 image values. Returns a 415
 * Response when an image payload is detected, otherwise null.
 */
export function rejectImagePayload(body: unknown): Response | null {
  if (containsImage(body)) {
    return problem(
      415,
      'Unsupported Media Type',
      'IMAGE_NOT_ALLOWED',
      'Image and thumbnail payloads are not accepted by this endpoint (VF-03 fail-closed).'
    );
  }
  return null;
}

function containsImage(value: unknown): boolean {
  // Iterative traversal: no depth-based fail-open or call-stack exhaustion.
  const pending: unknown[] = [value];
  while (pending.length) {
    const item = pending.pop();
    if (typeof item === 'string' && IMAGE_VALUE_PATTERN.test(item.trimStart())) return true;
    if (Array.isArray(item)) {
      for (const child of item) pending.push(child);
    } else if (item !== null && typeof item === 'object') {
      for (const [key, child] of Object.entries(item)) {
        if (IMAGE_KEY_PATTERN.test(key.replace(/([a-z])([A-Z])/g, '$1_$2'))) return true;
        pending.push(child);
      }
    }
  }
  return false;
}

/** Platform abuse throttle (per location, approximate; never a spend ledger). */
export async function enforceRateLimit(deviceToken: string, env: Env): Promise<Response | null> {
  try {
    if (!env.REQUEST_RATE_LIMITER) throw new Error('Missing limiter');
    const { success } = await env.REQUEST_RATE_LIMITER.limit({ key: await hashToken(deviceToken) });
    if (success) return null;
    const response = problem(429, 'Too Many Requests', 'RATE_LIMITED',
      'Request rate limit exceeded. Retry in one minute.',
      { resetsAt: new Date(Date.now() + RATE_LIMIT_WINDOW_SECONDS * 1000).toISOString() });
    response.headers.set('Retry-After', String(RATE_LIMIT_WINDOW_SECONDS));
    return response;
  } catch {
    return problem(503, 'Service Unavailable', 'RATE_LIMIT_UNAVAILABLE',
      'Request protection is temporarily unavailable. Please retry later.');
  }
}
