/**
 * OpenRouter client wrapper with VF-03 fail-closed data collection policy.
 * M0-09: Stubs model calls but ensures provider.data_collection: deny.
 */

import type { Env } from './types.js';

export interface OpenRouterRequest {
  model: string;
  messages: Array<{
    role: 'system' | 'user' | 'assistant';
    content: string;
  }>;
  temperature?: number;
  max_tokens?: number;
  provider?: {
    data_collection?: 'deny' | 'allow';
  };
}

export interface OpenRouterResponse {
  id: string;
  model: string;
  choices: Array<{
    message: {
      role: string;
      content: string;
    };
    finish_reason: string;
  }>;
  usage?: {
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  };
}

/**
 * Call OpenRouter API with VF-03 fail-closed data collection policy.
 * EVERY request MUST include provider.data_collection: deny.
 */
export async function callOpenRouter(
  request: OpenRouterRequest,
  env: Env
): Promise<OpenRouterResponse> {
  // VF-03 FAIL-CLOSED: Enforce data_collection: deny on every request
  const safeRequest: OpenRouterRequest = {
    ...request,
    provider: {
      ...request.provider,
      data_collection: 'deny', // MUST be present per M0-09 constraints
    },
  };
  
  const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${env.OPENROUTER_API_KEY}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': env.ATTRIBUTION_URL ?? 'https://example.invalid', // reserved example; set ATTRIBUTION_URL
      'X-Title': 'Personal Stylist',
    },
    body: JSON.stringify(safeRequest),
  });
  
  if (!response.ok) {
    const error = await response.text();
    throw new Error(`OpenRouter API error: ${response.status} ${error}`);
  }
  
  return await response.json();
}

/**
 * M0-09 STUB: Model calls are reserved for later phases.
 * This function exists to demonstrate the VF-03 fail-closed pattern.
 * The deterministic path (generateLocal) is used for M0-09.
 */
export async function callOpenRouterStub(
  _request: OpenRouterRequest,
  _env: Env
): Promise<never> {
  throw new Error(
    'OpenRouter model calls not yet implemented. ' +
    'M0-09 uses deterministic path only. ' +
    'When model path is enabled, use callOpenRouter with provider.data_collection: deny.'
  );
}
