/**
 * Request validation and abuse controls for content endpoints.
 *
 * Addresses:
 * - #170: schema/size validation and rate limiting (previously absent).
 * - #171: fail-closed rejection of image/thumbnail payloads (VF-03). The
 *   backend holds no user image content, so any image-bearing field is
 *   rejected before the engine runs.
 * - #36: normalize keys (lowercase, strip `_` / `-`) and match forbidden tokens
 *   anywhere in the segment, not only at non-letter boundaries.
 */

import type { Env, ProblemDetail } from './types.js';
import { hashToken } from './usage.js';

/** Maximum accepted request body size for content endpoints. */
export const MAX_BODY_BYTES = 512 * 1024; // 512 KiB

/** Rate limit: max authenticated content requests per period. */
export const RATE_LIMIT_MAX = 60;
export const RATE_LIMIT_WINDOW_SECONDS = 60;

/**
 * Sole named exception: docs/openapi.yaml → PrivacyConsent.wardrobeImagesAcceptedAt.
 * Matched on the full dotted path from the request body root only. The value must parse
 * as an ISO-8601 date-time and be at most 64 characters (openapi maxLength is tracked separately).
 * Additional exceptions require Architect approval and an openapi.yaml reference.
 */
export const IMAGE_GUARD_CONSENT_FIELD_PATH = 'privacyConsent.wardrobeImagesAcceptedAt';

const WARDROBE_IMAGES_ACCEPTED_AT_MAX_LENGTH = 64;

/** Substrings matched against {@link normalizeImageGuardKey} on each object key segment. */
export const FORBIDDEN_IMAGE_KEY_TOKENS = [
  'image',
  'imagedata',
  'imagebase64',
  'thumbnail',
  'thumb',
  'photo',
  'masterimage',
  'processedimage',
  'pixeldata',
  'bitmap',
  'imagery',
  'photography',
  'thumbsup',
] as const;

/** Detects data: URLs and common raw image encodings inside string values. */
const IMAGE_VALUE_PATTERN = /^data:image\/|^\/9j\/|^iVBORw0KGgo/i;

/** Lowercase ASCII A–Z; strip `_` and `-` so every casing/spelling variant matches. */
export function normalizeImageGuardKey(key: string): string {
  let normalized = '';
  for (let i = 0; i < key.length; i++) {
    const code = key.charCodeAt(i);
    if (code >= 65 && code <= 90) normalized += String.fromCharCode(code + 32);
    else if (key[i] !== '_' && key[i] !== '-') normalized += key[i];
  }
  return normalized;
}

export function normalizedKeyContainsForbiddenImageToken(key: string): boolean {
  const normalized = normalizeImageGuardKey(key);
  return FORBIDDEN_IMAGE_KEY_TOKENS.some((token) => normalized.includes(token));
}

export function isAllowedWardrobeImagesAcceptedAtValue(value: unknown): boolean {
  if (typeof value !== 'string') return false;
  if (value.length === 0 || value.length > WARDROBE_IMAGES_ACCEPTED_AT_MAX_LENGTH) return false;
  // OpenAPI `format: date-time` — require a time component, not a date-only string.
  if (!value.includes('T')) return false;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed);
}

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

function joinKeyPath(parentPath: string, key: string): string {
  return parentPath ? `${parentPath}.${key}` : key;
}

function containsImage(value: unknown): boolean {
  // Iterative traversal: no depth-based fail-open or call-stack exhaustion.
  const pending: Array<{ item: unknown; path: string }> = [{ item: value, path: '' }];
  while (pending.length) {
    const { item, path } = pending.pop()!;
    if (typeof item === 'string' && IMAGE_VALUE_PATTERN.test(item.trimStart())) return true;
    if (Array.isArray(item)) {
      for (const child of item) pending.push({ item: child, path });
    } else if (item !== null && typeof item === 'object') {
      for (const [key, child] of Object.entries(item)) {
        const keyPath = joinKeyPath(path, key);
        if (keyPath === IMAGE_GUARD_CONSENT_FIELD_PATH) {
          if (!isAllowedWardrobeImagesAcceptedAtValue(child)) return true;
          continue;
        }
        if (normalizedKeyContainsForbiddenImageToken(key)) return true;
        pending.push({ item: child, path: keyPath });
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
