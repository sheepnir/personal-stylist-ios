/**
 * Per-device opaque token registry (D-46 / #169).
 *
 * D-47: strongly consistent per-device Durable Objects hold only SHA-256 hashes.
 */

import type { Env } from './types.js';

export type TokenStatus = 'active' | 'revoked';

export interface TokenRecord {
  status: TokenStatus;
  issuedAt: string;
  revokedAt?: string;
}

const TOKEN_BYTES = 32;

export async function hashToken(deviceToken: string): Promise<string> {
  const data = new TextEncoder().encode(deviceToken);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

// Locator is random and public; the full token (locator + secret) is hashed for auth.
function deviceId(token: string): string | null {
  const match = /^([0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\.[A-Za-z0-9_-]{43}$/.exec(token);
  return match?.[1] ?? null;
}
function registry(id: string, env: Env) {
  if (!env.DEVICE_TOKENS) throw new Error('Token registry unavailable');
  return env.DEVICE_TOKENS.getByName(id);
}

/** Generate a URL-safe opaque device token. */
export function generateDeviceToken(id = crypto.randomUUID()): string {
  const bytes = new Uint8Array(TOKEN_BYTES);
  crypto.getRandomValues(bytes);
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  // base64url without padding
  return id + '.' + btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

export async function lookupToken(
  deviceToken: string,
  env: Env
): Promise<TokenRecord | null> {
  const id = deviceId(deviceToken);
  return id ? registry(id, env).lookup(await hashToken(deviceToken)) : null;
}

export async function isActiveDeviceToken(
  deviceToken: string,
  env: Env
): Promise<boolean> {
  const record = await lookupToken(deviceToken, env);
  return record?.status === 'active';
}

export async function issueDeviceToken(env: Env): Promise<{
  deviceToken: string;
  tokenHash: string;
  issuedAt: string;
}> {
  const deviceToken = generateDeviceToken();
  const tokenHash = await hashToken(deviceToken);
  const issuedAt = new Date().toISOString();
  if (!await registry(deviceId(deviceToken)!, env).issue(tokenHash, issuedAt)) {
    throw new Error('Device identifier collision');
  }
  return { deviceToken, tokenHash, issuedAt };
}

export async function revokeDeviceToken(
  deviceToken: string,
  env: Env
): Promise<boolean> {
  const id = deviceId(deviceToken);
  return id ? registry(id, env).revoke(await hashToken(deviceToken)) : false;
}

/**
 * Rotate: revoke the current token and issue a new one.
 * Returns null when the current token is not an active registry entry
 * (e.g. legacy shared DEVICE_TOKEN — caller should issue fresh instead).
 */
export async function rotateDeviceToken(
  currentToken: string,
  env: Env
): Promise<{ deviceToken: string; issuedAt: string } | null> {
  const id = deviceId(currentToken);
  if (!id) return null;
  const deviceToken = generateDeviceToken(id);
  const issuedAt = new Date().toISOString();
  const [oldHash, newHash] = await Promise.all([hashToken(currentToken), hashToken(deviceToken)]);
  const rotated = await registry(id, env).rotate(oldHash, newHash, issuedAt);
  return rotated ? { deviceToken, issuedAt } : null;
}
