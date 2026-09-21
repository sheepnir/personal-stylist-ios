import { timingSafeEqual } from 'node:crypto';
/**
 * Authentication middleware for Personal Stylist backend (D-46).
 *
 * Content endpoints accept:
 *   1. An active per-device opaque token (SHA-256 lookup in a per-device Durable Object), or
 *   2. (migration) the legacy shared DEVICE_TOKEN secret, if still configured.
 *
 * Enrollment uses ENROLLMENT_SECRET and never authenticates content routes.
 */

import type { Env, ProblemDetail } from './types.js';
import { hashToken, isActiveDeviceToken } from './tokens.js';

export interface AuthContext {
  deviceToken: string;
  /** True when authenticated via the legacy shared DEVICE_TOKEN secret. */
  legacyShared: boolean;
}

/**
 * Extract and validate Bearer token from request for content endpoints.
 */
export async function authenticate(
  request: Request,
  env: Env
): Promise<AuthContext | Response> {
  const token = extractBearer(request);
  if (token instanceof Response) return token;

  try {
    if (await isActiveDeviceToken(token, env)) {
      return { deviceToken: token, legacyShared: false };
    }
  } catch {
    return new Response(JSON.stringify({ status: 503, code: 'AUTH_UNAVAILABLE',
      title: 'Service Unavailable', detail: 'Authentication is temporarily unavailable.', dataPreserved: true }),
      { status: 503, headers: { 'Content-Type': 'application/problem+json' } });
  }

  // Legacy shared DEVICE_TOKEN is accepted only when that secret is configured;
  // remove the secret to disable this path.
  const legacy = env.DEVICE_TOKEN;
  if (legacy && (await constantTimeEqual(token, legacy))) {
    return { deviceToken: token, legacyShared: true };
  }

  return unauthorized('Invalid device token');
}

/**
 * Validate the enrollment secret for issuance-only routes.
 */
export async function authenticateEnrollment(
  request: Request,
  env: Env
): Promise<true | Response> {
  const token = extractBearer(request);
  if (token instanceof Response) return token;

  const expected = env.ENROLLMENT_SECRET;
  if (!expected) {
    return unauthorized('Enrollment is not configured');
  }
  if (!(await constantTimeEqual(token, expected))) {
    return unauthorized('Invalid enrollment secret');
  }
  return true;
}

export function extractBearer(request: Request): string | Response {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader) {
    return unauthorized('Missing Authorization header');
  }
  const parts = authHeader.split(' ');
  if (parts.length !== 2 || parts[0] !== 'Bearer') {
    return unauthorized('Invalid Authorization header format');
  }
  const token = parts[1];
  if (!token) {
    return unauthorized('Invalid device token');
  }
  return token;
}

function unauthorized(detail: string): Response {
  const problem: ProblemDetail = {
    type: 'about:blank',
    title: 'Unauthorized',
    status: 401,
    detail,
    code: 'UNAUTHORIZED',
    dataPreserved: true,
  };
  return new Response(JSON.stringify(problem), {
    status: 401,
    headers: { 'Content-Type': 'application/problem+json' },
  });
}

/**
 * Length-independent constant-time comparison via fixed-size digests (#177).
 * Uses the runtime primitive; JavaScript loops do not guarantee constant-time execution.
 */
export async function constantTimeEqual(a: string, b: string): Promise<boolean> {
  const [da, db] = await Promise.all([sha256Bytes(a), sha256Bytes(b)]);
  return timingSafeEqual(da, db);
}

async function sha256Bytes(value: string): Promise<Uint8Array> {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return new Uint8Array(digest);
}

/** Re-export for tests / ledger that already import hash helpers. */
export { hashToken };
