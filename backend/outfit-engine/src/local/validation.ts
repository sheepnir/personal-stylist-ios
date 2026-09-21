/**
 * Request validation for the local HTTP server.
 * Returns a Problem object if validation fails, null otherwise.
 */

import type {
  LocalGenerateRequest,
  LocalProblemBody,
} from "../pipeline/generateLocal.js";
import type { AlternativesRequest } from "../alternatives/rankAlternatives.js";

const VALID_OCCASIONS = new Set([
  "WORK_STANDARD",
  "WORK_IMPORTANT",
  "CLIENT_EXEC",
  "CASUAL_DAY",
  "EVENING_OUT",
  "TRAVEL_DAY",
  "WEEKEND_ERRANDS",
  "SPECIAL_EVENT",
]);

const VALID_TEMPERATURE_BANDS = new Set([
  "COLD",
  "COOL",
  "MILD",
  "WARM",
  "HOT",
]);

function createProblem(
  title: string,
  detail: string,
  code = "INVALID_REQUEST",
): LocalProblemBody {
  return {
    type: "about:blank",
    title,
    status: 400,
    detail,
    code,
    dataPreserved: true,
  };
}

/**
 * Validate a LocalGenerateRequest shape before passing to the pipeline.
 * Checks:
 * - wardrobe is an array
 * - context exists and has required fields (occasion, temperatureBand, occasionFormality)
 * - occasion and temperatureBand are valid enum values
 */
export function validateGenerateRequest(
  body: unknown,
): LocalProblemBody | null {
  if (typeof body !== "object" || body === null) {
    return createProblem(
      "Invalid request",
      "Request body must be a JSON object.",
    );
  }

  const req = body as Record<string, unknown>;

  // Validate wardrobe
  if (!Array.isArray(req.wardrobe)) {
    return createProblem(
      "Invalid request",
      "Request must include a 'wardrobe' array.",
    );
  }

  // Validate context exists
  if (typeof req.context !== "object" || req.context === null) {
    return createProblem(
      "Invalid request",
      "Request must include a 'context' object.",
    );
  }

  const context = req.context as Record<string, unknown>;

  // Validate required context fields
  if (typeof context.occasion !== "string") {
    return createProblem(
      "Invalid request",
      "context.occasion is required and must be a string.",
    );
  }

  if (typeof context.temperatureBand !== "string") {
    return createProblem(
      "Invalid request",
      "context.temperatureBand is required and must be a string.",
    );
  }

  if (typeof context.occasionFormality !== "number") {
    return createProblem(
      "Invalid request",
      "context.occasionFormality is required and must be a number.",
    );
  }

  // Validate occasion enum
  if (!VALID_OCCASIONS.has(context.occasion)) {
    return createProblem(
      "Invalid request",
      `context.occasion must be one of: ${[...VALID_OCCASIONS].join(", ")}. Got: "${context.occasion}"`,
    );
  }

  // Validate temperatureBand enum
  if (!VALID_TEMPERATURE_BANDS.has(context.temperatureBand)) {
    return createProblem(
      "Invalid request",
      `context.temperatureBand must be one of: ${[...VALID_TEMPERATURE_BANDS].join(", ")}. Got: "${context.temperatureBand}"`,
    );
  }

  return null;
}

/**
 * Validate an AlternativesRequest shape before passing to rankAlternatives.
 * Checks:
 * - wardrobe is an array
 * - context exists and has required fields
 * - currentAssignments is an array
 */
export function validateAlternativesRequest(
  body: unknown,
): LocalProblemBody | null {
  if (typeof body !== "object" || body === null) {
    return createProblem(
      "Invalid request",
      "Request body must be a JSON object.",
    );
  }

  const req = body as Record<string, unknown>;

  // Validate wardrobe
  if (!Array.isArray(req.wardrobe)) {
    return createProblem(
      "Invalid request",
      "Request must include a 'wardrobe' array.",
    );
  }

  // Validate context exists
  if (typeof req.context !== "object" || req.context === null) {
    return createProblem(
      "Invalid request",
      "Request must include a 'context' object.",
    );
  }

  const context = req.context as Record<string, unknown>;

  // Validate required context fields
  if (typeof context.occasion !== "string") {
    return createProblem(
      "Invalid request",
      "context.occasion is required and must be a string.",
    );
  }

  if (typeof context.temperatureBand !== "string") {
    return createProblem(
      "Invalid request",
      "context.temperatureBand is required and must be a string.",
    );
  }

  if (typeof context.occasionFormality !== "number") {
    return createProblem(
      "Invalid request",
      "context.occasionFormality is required and must be a number.",
    );
  }

  // Validate occasion enum
  if (!VALID_OCCASIONS.has(context.occasion)) {
    return createProblem(
      "Invalid request",
      `context.occasion must be one of: ${[...VALID_OCCASIONS].join(", ")}. Got: "${context.occasion}"`,
    );
  }

  // Validate temperatureBand enum
  if (!VALID_TEMPERATURE_BANDS.has(context.temperatureBand)) {
    return createProblem(
      "Invalid request",
      `context.temperatureBand must be one of: ${[...VALID_TEMPERATURE_BANDS].join(", ")}. Got: "${context.temperatureBand}"`,
    );
  }

  // Validate currentAssignments
  if (!Array.isArray(req.currentAssignments)) {
    return createProblem(
      "Invalid request",
      "Request must include a 'currentAssignments' array.",
    );
  }

  return null;
}
