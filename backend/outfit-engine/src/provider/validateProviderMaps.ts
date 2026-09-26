import { ownGetString, ownHas, isOwnStringToStringMap } from "./safeOwn.js";
import type { ProviderSetToken } from "./types.js";

export function validateTokenToGarmentId(
  tokenToGarmentId: Record<string, unknown>,
): boolean {
  return isOwnStringToStringMap(tokenToGarmentId);
}

export function validateSetTokens(setTokens: ProviderSetToken[]): boolean {
  for (const s of setTokens) {
    if (typeof s.token !== "string" || !s.token.startsWith("s_")) {
      return false;
    }
    if (s.memberGarmentIds.some((id) => typeof id !== "string" || !id)) {
      return false;
    }
    if (s.memberSlots.length !== s.memberGarmentIds.length) {
      return false;
    }
  }
  return true;
}

export function resolveGarmentIdFromToken(
  tokenToGarmentId: Record<string, string>,
  token: string,
): string | undefined {
  return ownGetString(tokenToGarmentId, token);
}

export function resolveSetToken(
  setTokens: ProviderSetToken[],
  token: string,
): ProviderSetToken | undefined {
  for (const s of setTokens) {
    if (s.token === token) return s;
  }
  return undefined;
}

export function optionKeyIsOffered(
  options: Record<string, unknown>,
  key: string,
): boolean {
  return ownHas(options, key);
}
