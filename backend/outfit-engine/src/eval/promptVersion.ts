import { CURRENT_STYLIST_PROMPT_VERSION } from "../provider/index.js";

/** ADR-0001 §8: eval records promptVersion per model arm. */
export function promptVersionForEvalArm(model: string): string {
  return model === "deterministic" ? "none" : CURRENT_STYLIST_PROMPT_VERSION;
}
