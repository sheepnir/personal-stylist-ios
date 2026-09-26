import { createHash } from "node:crypto";
import type { StylistPromptModule } from "./promptVersionTypes.js";

/** Deterministic JSON for registry hashing (sorted object keys). */
export function stableStringify(value: unknown): string {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((entry) => stableStringify(entry)).join(",")}]`;
  }
  const record = value as Record<string, unknown>;
  const keys = Object.keys(record).sort();
  return `{${keys
    .map((key) => `${JSON.stringify(key)}:${stableStringify(record[key])}`)
    .join(",")}}`;
}

/** SHA-256 of instruction text, input sections, and answer types (ADR-0001 §8). */
export function hashStylistPromptVersionContent(
  instructionText: string,
  inputSections: StylistPromptModule["inputSections"],
  answerTypes: unknown,
): string {
  const material = stableStringify({
    instructionText,
    inputSections,
    answerTypes,
  });
  return createHash("sha256").update(material, "utf8").digest("hex");
}

export function hashStylistPromptModule(module: StylistPromptModule): string {
  return hashStylistPromptVersionContent(
    module.instructionText,
    module.inputSections,
    module.answerTypes,
  );
}
