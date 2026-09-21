/**
 * Device-token lifecycle routes (D-46 / #169).
 */

import type { Env, ProblemDetail } from './types.js';
import type { AuthContext } from './auth.js';
import { authenticateEnrollment } from './auth.js';
import { enforceRateLimit } from './validation.js';
import {
  issueDeviceToken,
  revokeDeviceToken,
  rotateDeviceToken,
} from './tokens.js';

/**
 * POST /v1/auth/device — issue a new per-device opaque token.
 * Auth: Bearer ENROLLMENT_SECRET.
 */
export async function handleIssueDevice(
  request: Request,
  env: Env
): Promise<Response> {
  const enrolled = await authenticateEnrollment(request, env);
  if (enrolled instanceof Response) return enrolled;
  const limited = await enforceRateLimit(env.ENROLLMENT_SECRET!, env);
  if (limited) return limited;

  try {
    const issued = await issueDeviceToken(env);
    return new Response(
      JSON.stringify({
        deviceToken: issued.deviceToken,
        issuedAt: issued.issuedAt,
      }),
      {
        status: 201,
        headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
      }
    );
  } catch (error) {
    console.error('Issue device token error:', error);
    return internalError('Failed to issue device token');
  }
}

/**
 * POST /v1/auth/device/rotate — revoke current, issue replacement.
 * Auth: current device Bearer (registry or legacy shared).
 */
export async function handleRotateDevice(
  _request: Request,
  env: Env,
  auth: AuthContext
): Promise<Response> {
  try {
    if (auth.legacyShared) {
      // Legacy shared secret is not in the registry — issue a fresh
      // per-device token without a revoke target.
      const issued = await issueDeviceToken(env);
      return new Response(
        JSON.stringify({
          deviceToken: issued.deviceToken,
          issuedAt: issued.issuedAt,
          migratedFromLegacy: true,
        }),
        {
          status: 200,
          headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
        }
      );
    }

    const rotated = await rotateDeviceToken(auth.deviceToken, env);
    if (!rotated) {
      return problem(
        400,
        'Bad Request',
        'TOKEN_NOT_ROTATABLE',
        'Current token is not an active registry entry.'
      );
    }
    return new Response(JSON.stringify(rotated), {
      status: 200,
      headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    });
  } catch (error) {
    console.error('Rotate device token error:', error);
    return internalError('Failed to rotate device token');
  }
}

/**
 * POST /v1/auth/device/revoke — revoke the current device token.
 * Auth: current device Bearer.
 */
export async function handleRevokeDevice(
  _request: Request,
  env: Env,
  auth: AuthContext
): Promise<Response> {
  try {
    if (auth.legacyShared) {
      return problem(
        400,
        'Bad Request',
        'LEGACY_TOKEN_NOT_REVOCABLE',
        'The legacy shared DEVICE_TOKEN cannot be revoked via this endpoint. Remove the Wrangler secret instead.'
      );
    }
    const ok = await revokeDeviceToken(auth.deviceToken, env);
    if (!ok) {
      return problem(
        400,
        'Bad Request',
        'TOKEN_ALREADY_REVOKED',
        'Token is not an active registry entry.'
      );
    }
    return new Response(null, { status: 204 });
  } catch (error) {
    console.error('Revoke device token error:', error);
    return internalError('Failed to revoke device token');
  }
}

function problem(
  status: number,
  title: string,
  code: string,
  detail: string
): Response {
  const body: ProblemDetail = {
    type: 'about:blank',
    title,
    status,
    detail,
    code,
    dataPreserved: true,
  };
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/problem+json' },
  });
}

function internalError(detail: string): Response {
  return problem(500, 'Internal Server Error', 'INTERNAL_ERROR', detail);
}
