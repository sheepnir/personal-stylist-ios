/**
 * Route handlers for Personal Stylist backend (M0-09).
 */

import { 
  generateLocal, 
  isLocalProblem,
  rankAlternatives,
  isAlternativesProblem,
} from '@personal-stylist/outfit-engine';
import type { Env, ProblemDetail } from './types.js';
import type { AuthContext } from './auth.js';
import { getUsageSummary } from './usage.js';
import { readJsonWithLimit, rejectImagePayload } from './validation.js';

/**
 * GET /health - Health check endpoint (no auth required).
 */
export async function handleHealth(_request: Request, _env: Env): Promise<Response> {
  return new Response(
    JSON.stringify({
      status: 'ok',
      service: 'stylist-backend',
      version: '0.0.0-sample',
      timestamp: new Date().toISOString(),
    }),
    {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }
  );
}

/**
 * GET /v1/usage - Get usage summary (auth required).
 */
export async function handleUsage(
  _request: Request,
  env: Env,
  auth: AuthContext
): Promise<Response> {
  try {
    const usage = await getUsageSummary(auth.deviceToken, env);
    
    return new Response(JSON.stringify(usage), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Usage endpoint error:', error);
    return internalError('Failed to retrieve usage data');
  }
}

/**
 * POST /v1/outfit/alternatives - Rank swap alternatives (auth required, deterministic).
 */
export async function handleAlternatives(
  request: Request,
  _env: Env,
  _auth: AuthContext
): Promise<Response> {
  try {
    const parsed = await readJsonWithLimit(request);
    if (parsed instanceof Response) return parsed;
    const imageReject = rejectImagePayload(parsed);
    if (imageReject) return imageReject;
    const body = parsed as any;

    if (!body.slot || typeof body.slot !== 'string') {
      return badRequest('Missing or invalid slot');
    }
    
    if (!body.currentAssignments || !Array.isArray(body.currentAssignments)) {
      return badRequest('Missing or invalid currentAssignments array');
    }
    
    if (!body.wardrobe || !Array.isArray(body.wardrobe)) {
      return badRequest('Missing or invalid wardrobe array');
    }
    
    if (!body.context || typeof body.context !== 'object') {
      return badRequest('Missing or invalid context object');
    }
    
    const result = rankAlternatives({
      slot: body.slot,
      currentAssignments: body.currentAssignments,
      wardrobe: body.wardrobe,
      profile: body.profile ?? null,
      context: body.context,
      recentOutfits: body.recentOutfits ?? [],
      limit: body.limit ?? 8,
      sets: body.sets ?? [],
      requestId: body.requestId ?? null,
    });
    
    if (isAlternativesProblem(result)) {
      return new Response(JSON.stringify(result), {
        status: result.status,
        headers: { 'Content-Type': 'application/problem+json' },
      });
    }
    
    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Alternatives endpoint error:', error);
    return internalError('Failed to rank alternatives');
  }
}

/**
 * POST /v1/outfit/generate - Generate outfit (auth required).
 * M0-09: Uses deterministic path only (hard cap enforced, no model calls).
 */
export async function handleGenerate(
  request: Request,
  _env: Env,
  _auth: AuthContext
): Promise<Response> {
  try {
    // Parse request body with a size limit (#170)
    const parsed = await readJsonWithLimit(request);
    if (parsed instanceof Response) return parsed;
    // Fail-closed: reject any image/thumbnail payload (#171 / VF-03)
    const imageReject = rejectImagePayload(parsed);
    if (imageReject) return imageReject;
    const body = parsed as any;

    // Validate required fields
    if (!body.wardrobe || !Array.isArray(body.wardrobe)) {
      return badRequest('Missing or invalid wardrobe array');
    }
    
    if (!body.context || typeof body.context !== 'object') {
      return badRequest('Missing or invalid context object');
    }
    
    // M0-09: Always deterministic — no model call, so no hard-cap KV read (#165).
    // Live OpenRouter (#92) must reintroduce isHardCapReached before paid attempts.
    const result = generateLocal({
      wardrobe: body.wardrobe,
      context: body.context,
      profile: body.profile ?? null,
      anchorGarmentId: body.anchorGarmentId ?? null,
      lockedAssignments: body.lockedAssignments ?? [],
      options: body.options ?? {},
      sets: body.sets ?? [],
      boldness: body.boldness ?? 'FAMILIAR',
      recentOutfits: body.recentOutfits ?? [],
      requestId: body.requestId ?? null,
    });
    
    // Handle Stage 1 problem (400)
    if (isLocalProblem(result)) {
      return new Response(JSON.stringify(result), {
        status: result.status,
        headers: { 'Content-Type': 'application/problem+json' },
      });
    }
    
    // Success: deterministic outfit (200)
    // Note: generation.spendState is HARD_CAP_DETERMINISTIC
    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Generate endpoint error:', error);
    return internalError('Failed to generate outfit');
  }
}

/**
 * Return 400 Bad Request with RFC 9457 problem detail.
 */
function badRequest(detail: string): Response {
  const problem: ProblemDetail = {
    type: 'about:blank',
    title: 'Bad Request',
    status: 400,
    detail,
    code: 'BAD_REQUEST',
    dataPreserved: true,
  };
  
  return new Response(JSON.stringify(problem), {
    status: 400,
    headers: { 'Content-Type': 'application/problem+json' },
  });
}

/**
 * Return 500 Internal Server Error with RFC 9457 problem detail.
 */
function internalError(detail: string): Response {
  const problem: ProblemDetail = {
    type: 'about:blank',
    title: 'Internal Server Error',
    status: 500,
    detail,
    code: 'INTERNAL_ERROR',
    dataPreserved: true,
  };
  
  return new Response(JSON.stringify(problem), {
    status: 500,
    headers: { 'Content-Type': 'application/problem+json' },
  });
}

/**
 * Return 404 Not Found with RFC 9457 problem detail.
 */
export function notFound(): Response {
  const problem: ProblemDetail = {
    type: 'about:blank',
    title: 'Not Found',
    status: 404,
    detail: 'The requested resource was not found',
    code: 'NOT_FOUND',
    dataPreserved: true,
  };
  
  return new Response(JSON.stringify(problem), {
    status: 404,
    headers: { 'Content-Type': 'application/problem+json' },
  });
}

/**
 * Return 405 Method Not Allowed with RFC 9457 problem detail.
 */
export function methodNotAllowed(allowed: string[]): Response {
  const problem: ProblemDetail = {
    type: 'about:blank',
    title: 'Method Not Allowed',
    status: 405,
    detail: `Method not allowed. Allowed methods: ${allowed.join(', ')}`,
    code: 'METHOD_NOT_ALLOWED',
    dataPreserved: true,
  };
  
  return new Response(JSON.stringify(problem), {
    status: 405,
    headers: {
      'Content-Type': 'application/problem+json',
      'Allow': allowed.join(', '),
    },
  });
}
