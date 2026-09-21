import type { PreferenceRule } from "../types.js";
import { scopesForOccasion } from "../stage1/filters.js";

export function ruleInScope(rule: PreferenceRule, occasion: string): boolean {
  if (rule.active === false) return false;
  const scope = (rule.scope ?? "ALWAYS").toUpperCase();
  const scopes = scopesForOccasion(occasion);
  return scopes.has(scope);
}

export function isComboNegative(rule: PreferenceRule): boolean {
  const kind = String(rule.kind).toUpperCase();
  if (kind !== "COMBINATION") return false;
  const pol = String(rule.polarity).toUpperCase();
  return pol === "DISLIKE" || pol === "AVOID_HARD";
}

export function garmentPair(subject: Record<string, unknown>): [string, string] | null {
  const pair = subject.pair;
  if (Array.isArray(pair) && pair.length === 2) {
    return [String(pair[0]), String(pair[1])];
  }
  return null;
}

export function colorFamilyPair(
  subject: Record<string, unknown>,
): [string, string] | null {
  const cf = subject.colorFamilies;
  if (Array.isArray(cf) && cf.length === 2) {
    return [String(cf[0]).toLowerCase(), String(cf[1]).toLowerCase()];
  }
  return null;
}
