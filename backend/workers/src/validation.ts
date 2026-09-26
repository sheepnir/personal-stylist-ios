/**
 * Request validation and abuse controls for content endpoints.
 *
 * Addresses:
 * - #170: schema/size validation and rate limiting (previously absent).
 * - #171: fail-closed rejection of image/thumbnail payloads (VF-03). The
 *   backend holds no user image content, so any image-bearing field is
 *   rejected before the engine runs.
 * - #36: printable-ASCII object keys only; normalize allowed keys (lowercase,
 *   strip `_` / `-` / `.` / ECMAScript whitespace) and match forbidden tokens
 *   anywhere in the segment. Consent matching keeps at most a two-segment path
 *   (`privacyConsent` → `wardrobeImagesAcceptedAt`); deeper objects reuse that
 *   prefix without copying unbounded path vectors. Request size is capped separately
 *   by {@link MAX_BODY_BYTES} (#170), not by nesting depth.
 */

import type { Env, ProblemDetail } from './types.js';
import { hashToken } from './usage.js';
import {
  isAllowedWardrobeImagesAcceptedAtValue,
} from './imageGuardConsent.js';
import {
  FORBIDDEN_IMAGE_KEY_TOKENS,
  normalizeImageGuardKey,
  normalizedKeyContainsForbiddenImageToken,
} from './imageGuardKey.js';

export {
  FORBIDDEN_IMAGE_KEY_TOKENS,
  ECMA_SCRIPT_WHITESPACE_CODE_POINTS,
  IMAGE_GUARD_KEY_SEPARATOR_CODE_POINTS,
  IMAGE_GUARD_PRINTABLE_ASCII_MAX,
  IMAGE_GUARD_PRINTABLE_ASCII_MIN,
  normalizeImageGuardKey,
  normalizedKeyContainsForbiddenImageToken,
  objectKeyFailsPrintableAsciiRule,
} from './imageGuardKey.js';

/** Prefixes matched on string values after `trimStart()` (case-insensitive on ASCII). */
export const IMAGE_VALUE_PREFIXES = ['data:image/', '/9j/', 'iVBORw0KGgo'] as const;

/** Detects data: URLs and common raw image encodings inside string values. */
const IMAGE_VALUE_PATTERN = /^data:image\/|^\/9j\/|^iVBORw0KGgo/i;

/** Rate limit: max authenticated content requests per period. */
export const RATE_LIMIT_MAX = 60;
export const RATE_LIMIT_WINDOW_SECONDS = 60;

/**
 * Sole named exception: docs/openapi.yaml → PrivacyConsent.wardrobeImagesAcceptedAt.
 * Matched as path segments `['privacyConsent','wardrobeImagesAcceptedAt']` from the body
 * root through objects only (never inside arrays). Value must match
 * {@link WARDROBE_IMAGES_ACCEPTED_AT_RFC3339} with calendar round-trip and be at most
 * 64 characters (openapi maxLength is tracked separately).
 * Additional exceptions require Architect approval and an openapi.yaml reference.
 */
export const IMAGE_GUARD_CONSENT_FIELD_SEGMENTS = ['privacyConsent', 'wardrobeImagesAcceptedAt'] as const;

/** Maximum accepted request body size for content endpoints. */
export const MAX_BODY_BYTES = 512 * 1024; // 512 KiB

export { isAllowedWardrobeImagesAcceptedAtValue } from './imageGuardConsent.js';

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

function consentPathMatches(path: readonly string[], pathLen: number): boolean {
  return (
    pathLen === IMAGE_GUARD_CONSENT_FIELD_SEGMENTS.length &&
    IMAGE_GUARD_CONSENT_FIELD_SEGMENTS.every((segment, index) => path[index] === segment)
  );
}

const CONSENT_PATH_DEPTH = IMAGE_GUARD_CONSENT_FIELD_SEGMENTS.length;

function containsImage(value: unknown): boolean {
  // Iterative traversal: consent path is two segments only; no unbounded path copying.
  type Frame = {
    item: unknown;
    path: string[];
    pathLen: number;
    pastConsentDepth: boolean;
    underArrayAncestor: boolean;
  };
  const pathBuf: string[] = [];
  const pending: Frame[] = [
    { item: value, path: pathBuf, pathLen: 0, pastConsentDepth: false, underArrayAncestor: false },
  ];
  while (pending.length) {
    const { item, path, pathLen, pastConsentDepth, underArrayAncestor } = pending.pop()!;
    if (typeof item === 'string' && IMAGE_VALUE_PATTERN.test(item.trimStart())) return true;
    if (Array.isArray(item)) {
      for (const child of item) {
        pending.push({ item: child, path, pathLen, pastConsentDepth, underArrayAncestor: true });
      }
    } else if (item !== null && typeof item === 'object') {
      for (const [key, child] of Object.entries(item)) {
        let childPath = path;
        let childPathLen = pathLen;
        let childPastConsentDepth = pastConsentDepth;
        if (!underArrayAncestor && !pastConsentDepth && pathLen < CONSENT_PATH_DEPTH) {
          childPath = pathLen === 0 ? [key] : [path[0], key];
          childPathLen = childPath.length;
          childPastConsentDepth = childPathLen >= CONSENT_PATH_DEPTH;
          if (consentPathMatches(childPath, childPathLen)) {
            if (!isAllowedWardrobeImagesAcceptedAtValue(child)) return true;
            continue;
          }
        }
        if (normalizedKeyContainsForbiddenImageToken(key)) return true;
        if (Array.isArray(child)) {
          for (const element of child) {
            pending.push({
              item: element,
              path: childPath,
              pathLen: childPathLen,
              pastConsentDepth: childPastConsentDepth,
              underArrayAncestor: true,
            });
          }
        } else {
          pending.push({
            item: child,
            path: childPath,
            pathLen: childPathLen,
            pastConsentDepth: childPastConsentDepth,
            underArrayAncestor,
          });
        }
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
