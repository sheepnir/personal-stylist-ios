import { createHash } from "node:crypto";

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

/** SHA-256 of system text plus serialized output schema (ADR-0001 §8). */
export function hashPromptContent(system: string, outputSchema: unknown): string {
  const material = `${system}\n${stableStringify(outputSchema)}`;
  return createHash("sha256").update(material, "utf8").digest("hex");
}
