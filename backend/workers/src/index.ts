export { DeviceTokenRegistry } from './tokenRegistry.js';
export { DeviceSpendLedger } from './spendLedger.js';
/**
 * Personal Stylist Cloudflare Workers backend - M0-09.
 * 
 * Provides:
 * - Device token authentication (Bearer)
 * - OpenRouter client with VF-03 fail-closed data collection
 * - Hard spend cap enforcement (configurable; sample defaults in types.ts)
 * - POST /v1/outfit/generate (deterministic path only for M0-09)
 * - GET /v1/usage (auth required)
 * - GET /health (no auth)
 */

import type { Env } from './types.js';
import { authenticate } from './auth.js';
import { enforceRateLimit } from './validation.js';
import {
  handleIssueDevice,
  handleRotateDevice,
  handleRevokeDevice,
} from './authRoutes.js';
import {
  handleHealth,
  handleUsage,
  handleGenerate,
  handleAlternatives,
  handleModels,
  notFound,
  methodNotAllowed,
} from './routes.js';

export default {
  async fetch(request: Request, env: Env, _ctx: ExecutionContext): Promise<Response> {
    // CORS headers. The native iOS client does not send an Origin and does not
    // rely on CORS, so we never respond with a wildcard Access-Control-Allow-Origin
    // (#178). Browser origins are only reflected when explicitly allowlisted via
    // the ALLOWED_ORIGINS env var (comma-separated).
    const corsHeaders = buildCorsHeaders(request, env);
    
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: corsHeaders,
      });
    }
    
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;
    
    // Health endpoint (no auth required)
    if (path === '/health' || path === '/v1/health') {
      if (method !== 'GET') {
        return methodNotAllowed(['GET']);
      }
      const response = await handleHealth(request, env);
      return addCorsHeaders(response, corsHeaders);
    }

    // Issuance uses ENROLLMENT_SECRET, not a device token (D-46 / #169)
    if (path === '/v1/auth/device') {
      if (method !== 'POST') {
        return addCorsHeaders(methodNotAllowed(['POST']), corsHeaders);
      }
      const response = await handleIssueDevice(request, env);
      return addCorsHeaders(response, corsHeaders);
    }
    
    // Auth required for all other endpoints
    const authResult = await authenticate(request, env);
    
    // Authentication failed
    if (authResult instanceof Response) {
      return addCorsHeaders(authResult, corsHeaders);
    }

    // Per-device rate limit for authenticated endpoints (#170)
    const rateLimited = await enforceRateLimit(authResult.deviceToken, env);
    if (rateLimited) {
      return addCorsHeaders(rateLimited, corsHeaders);
    }
    
    // Route authenticated requests
    try {
      let response: Response;
      
      // GET /v1/usage
      if (path === '/v1/usage') {
        if (method !== 'GET') {
          response = methodNotAllowed(['GET']);
        } else {
          response = await handleUsage(request, env, authResult);
        }
      }
      // GET /v1/models
      else if (path === '/v1/models') {
        if (method !== 'GET') {
          response = methodNotAllowed(['GET']);
        } else {
          response = await handleModels(request, env, authResult);
        }
      }
      // POST /v1/outfit/generate
      else if (path === '/v1/outfit/generate') {
        if (method !== 'POST') {
          response = methodNotAllowed(['POST']);
        } else {
          response = await handleGenerate(request, env, authResult);
        }
      }
      // POST /v1/outfit/alternatives
      else if (path === '/v1/outfit/alternatives') {
        if (method !== 'POST') {
          response = methodNotAllowed(['POST']);
        } else {
          response = await handleAlternatives(request, env, authResult);
        }
      }
      // POST /v1/auth/device/rotate
      else if (path === '/v1/auth/device/rotate') {
        if (method !== 'POST') {
          response = methodNotAllowed(['POST']);
        } else {
          response = await handleRotateDevice(request, env, authResult);
        }
      }
      // POST /v1/auth/device/revoke
      else if (path === '/v1/auth/device/revoke') {
        if (method !== 'POST') {
          response = methodNotAllowed(['POST']);
        } else {
          response = await handleRevokeDevice(request, env, authResult);
        }
      }
      // Not found
      else {
        response = notFound();
      }
      
      return addCorsHeaders(response, corsHeaders);
    } catch (error) {
      console.error('Request handler error:', error);
      
      const errorResponse = new Response(
        JSON.stringify({
          type: 'about:blank',
          title: 'Internal Server Error',
          status: 500,
          detail: 'An unexpected error occurred',
          code: 'INTERNAL_ERROR',
          dataPreserved: true,
        }),
        {
          status: 500,
          headers: { 'Content-Type': 'application/problem+json' },
        }
      );
      
      return addCorsHeaders(errorResponse, corsHeaders);
    }
  },
};

/**
 * Build CORS headers for a request.
 *
 * Access-Control-Allow-Origin is emitted only when the request's Origin is in
 * the configured allowlist (ALLOWED_ORIGINS, comma-separated). It is never `*`.
 */
function buildCorsHeaders(request: Request, env: Env): Record<string, string> {
  const headers: Record<string, string> = {
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };

  const origin = request.headers.get('Origin');
  const allowlist = (env.ALLOWED_ORIGINS ?? '')
    .split(',')
    .map((o) => o.trim())
    .filter((o) => o.length > 0);

  if (origin && allowlist.includes(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
  }

  return headers;
}

/**
 * Add CORS headers to response.
 */
function addCorsHeaders(response: Response, corsHeaders: Record<string, string>): Response {
  const newHeaders = new Headers(response.headers);
  for (const [key, value] of Object.entries(corsHeaders)) {
    newHeaders.set(key, value);
  }
  
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: newHeaders,
  });
}
