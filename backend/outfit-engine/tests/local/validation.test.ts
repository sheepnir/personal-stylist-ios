/**
 * Tests for local server request validation and error handling.
 * Covers crash scenarios from issue #27.
 */

import { describe, it, expect } from "vitest";
import {
  validateGenerateRequest,
  validateAlternativesRequest,
} from "../../src/local/validation.js";

describe("validateGenerateRequest", () => {
  const validContext = {
    occasion: "WEEKEND_ERRANDS",
    occasionFormality: 2,
    temperatureBand: "MILD",
    capturedAt: "2026-09-19T12:00:00Z",
  };

  const validRequest = {
    wardrobe: [
      {
        id: "g1",
        displayName: "Navy Blazer",
        slot: "JACKET",
        colorPrimary: { family: "navy" },
        pattern: "SOLID",
        surface: "SMOOTH",
        formality: 4,
        warmth: 3,
      },
    ],
    context: validContext,
  };

  it("accepts a valid request", () => {
    const result = validateGenerateRequest(validRequest);
    expect(result).toBeNull();
  });

  it("rejects non-object body", () => {
    const result = validateGenerateRequest("not an object");
    expect(result).not.toBeNull();
    expect(result?.status).toBe(400);
    expect(result?.code).toBe("INVALID_REQUEST");
    expect(result?.detail).toContain("must be a JSON object");
  });

  it("rejects null body", () => {
    const result = validateGenerateRequest(null);
    expect(result).not.toBeNull();
    expect(result?.status).toBe(400);
  });

  describe("wardrobe validation", () => {
    it("rejects missing wardrobe", () => {
      const request = { context: validContext };
      const result = validateGenerateRequest(request);
      expect(result).not.toBeNull();
      expect(result?.detail).toContain("'wardrobe' array");
    });

    it("rejects wardrobe as number (issue #27 crash scenario)", () => {
      const request = { wardrobe: 5, context: validContext };
      const result = validateGenerateRequest(request);
      expect(result).not.toBeNull();
      expect(result?.status).toBe(400);
      expect(result?.detail).toContain("'wardrobe' array");
    });

    it("rejects wardrobe as string", () => {
      const request = { wardrobe: "invalid", context: validContext };
      const result = validateGenerateRequest(request);
      expect(result).not.toBeNull();
      expect(result?.detail).toContain("'wardrobe' array");
    });

    it("rejects wardrobe as null", () => {
      const request = { wardrobe: null, context: validContext };
      const result = validateGenerateRequest(request);
      expect(result).not.toBeNull();
      expect(result?.detail).toContain("'wardrobe' array");
    });

    it("accepts empty wardrobe array", () => {
      const request = { wardrobe: [], context: validContext };
      const result = validateGenerateRequest(request);
      expect(result).toBeNull();
    });
  });

  describe("context validation", () => {
    it("rejects missing context", () => {
      const request = { wardrobe: [] };
      const result = validateGenerateRequest(request);
      expect(result).not.toBeNull();
      expect(result?.detail).toContain("'context' object");
    });

    it("rejects context as empty object (missing required fields)", () => {
      const request = { wardrobe: [], context: {} };
      const result = validateGenerateRequest(request);
      expect(result).not.toBeNull();
      expect(result?.status).toBe(400);
    });

    it("rejects context with null", () => {
      const request = { wardrobe: [], context: null };
      const result = validateGenerateRequest(request);
      expect(result).not.toBeNull();
      expect(result?.detail).toContain("'context' object");
    });

    describe("occasion field", () => {
      it("rejects missing occasion (issue #27 crash scenario)", () => {
        const request = {
          wardrobe: [],
          context: {
            temperatureBand: "MILD",
            occasionFormality: 2,
          },
        };
        const result = validateGenerateRequest(request);
        expect(result).not.toBeNull();
        expect(result?.detail).toContain("context.occasion");
      });

      it("rejects null occasion", () => {
        const request = {
          wardrobe: [],
          context: {
            occasion: null,
            temperatureBand: "MILD",
            occasionFormality: 2,
          },
        };
        const result = validateGenerateRequest(request);
        expect(result).not.toBeNull();
        expect(result?.detail).toContain("context.occasion");
      });

      it("rejects invalid occasion enum (issue #27 - silent wrong scope)", () => {
        const request = {
          wardrobe: [],
          context: {
            occasion: "smart_casual",
            temperatureBand: "MILD",
            occasionFormality: 2,
          },
        };
        const result = validateGenerateRequest(request);
        expect(result).not.toBeNull();
        expect(result?.status).toBe(400);
        expect(result?.detail).toContain("WORK_STANDARD");
        expect(result?.detail).toContain("smart_casual");
      });

      it("accepts all valid occasion enums", () => {
        const validOccasions = [
          "WORK_STANDARD",
          "WORK_IMPORTANT",
          "CLIENT_EXEC",
          "CASUAL_DAY",
          "EVENING_OUT",
          "TRAVEL_DAY",
          "WEEKEND_ERRANDS",
          "SPECIAL_EVENT",
        ];

        for (const occasion of validOccasions) {
          const request = {
            wardrobe: [],
            context: {
              occasion,
              temperatureBand: "MILD",
              occasionFormality: 2,
            },
          };
          const result = validateGenerateRequest(request);
          expect(result).toBeNull();
        }
      });
    });

    describe("temperatureBand field", () => {
      it("rejects missing temperatureBand (issue #27 crash scenario)", () => {
        const request = {
          wardrobe: [],
          context: {
            occasion: "WEEKEND_ERRANDS",
            occasionFormality: 2,
          },
        };
        const result = validateGenerateRequest(request);
        expect(result).not.toBeNull();
        expect(result?.detail).toContain("context.temperatureBand");
      });

      it("rejects null temperatureBand", () => {
        const request = {
          wardrobe: [],
          context: {
            occasion: "WEEKEND_ERRANDS",
            temperatureBand: null,
            occasionFormality: 2,
          },
        };
        const result = validateGenerateRequest(request);
        expect(result).not.toBeNull();
        expect(result?.detail).toContain("context.temperatureBand");
      });

      it("rejects invalid temperatureBand enum (issue #27 crash scenario)", () => {
        const request = {
          wardrobe: [],
          context: {
            occasion: "WEEKEND_ERRANDS",
            temperatureBand: "FREEZING",
            occasionFormality: 2,
          },
        };
        const result = validateGenerateRequest(request);
        expect(result).not.toBeNull();
        expect(result?.status).toBe(400);
        expect(result?.detail).toContain("COLD");
        expect(result?.detail).toContain("FREEZING");
      });

      it("accepts all valid temperatureBand enums", () => {
        const validBands = ["COLD", "COOL", "MILD", "WARM", "HOT"];

        for (const temperatureBand of validBands) {
          const request = {
            wardrobe: [],
            context: {
              occasion: "WEEKEND_ERRANDS",
              temperatureBand,
              occasionFormality: 2,
            },
          };
          const result = validateGenerateRequest(request);
          expect(result).toBeNull();
        }
      });
    });

    describe("occasionFormality field", () => {
      it("rejects missing occasionFormality", () => {
        const request = {
          wardrobe: [],
          context: {
            occasion: "WEEKEND_ERRANDS",
            temperatureBand: "MILD",
          },
        };
        const result = validateGenerateRequest(request);
        expect(result).not.toBeNull();
        expect(result?.detail).toContain("context.occasionFormality");
      });

      it("rejects null occasionFormality", () => {
        const request = {
          wardrobe: [],
          context: {
            occasion: "WEEKEND_ERRANDS",
            temperatureBand: "MILD",
            occasionFormality: null,
          },
        };
        const result = validateGenerateRequest(request);
        expect(result).not.toBeNull();
        expect(result?.detail).toContain("context.occasionFormality");
      });

      it("rejects string occasionFormality", () => {
        const request = {
          wardrobe: [],
          context: {
            occasion: "WEEKEND_ERRANDS",
            temperatureBand: "MILD",
            occasionFormality: "3",
          },
        };
        const result = validateGenerateRequest(request);
        expect(result).not.toBeNull();
        expect(result?.detail).toContain("context.occasionFormality");
      });

      it("accepts numeric occasionFormality", () => {
        const request = {
          wardrobe: [],
          context: {
            occasion: "WEEKEND_ERRANDS",
            temperatureBand: "MILD",
            occasionFormality: 3,
          },
        };
        const result = validateGenerateRequest(request);
        expect(result).toBeNull();
      });
    });
  });
});

describe("validateAlternativesRequest", () => {
  const validContext = {
    occasion: "WEEKEND_ERRANDS",
    occasionFormality: 2,
    temperatureBand: "MILD",
    capturedAt: "2026-09-19T12:00:00Z",
  };

  const validRequest = {
    slot: "TOP",
    wardrobe: [
      {
        id: "g1",
        displayName: "Navy Blazer",
        slot: "JACKET",
        colorPrimary: { family: "navy" },
        pattern: "SOLID",
        surface: "SMOOTH",
        formality: 4,
        warmth: 3,
      },
    ],
    context: validContext,
    currentAssignments: [{ slot: "BOTTOM", garmentId: "g2" }],
  };

  it("accepts a valid request", () => {
    const result = validateAlternativesRequest(validRequest);
    expect(result).toBeNull();
  });

  it("rejects non-object body", () => {
    const result = validateAlternativesRequest("not an object");
    expect(result).not.toBeNull();
    expect(result?.status).toBe(400);
  });

  describe("wardrobe validation", () => {
    it("rejects missing wardrobe", () => {
      const request = {
        context: validContext,
        currentAssignments: [],
      };
      const result = validateAlternativesRequest(request);
      expect(result).not.toBeNull();
      expect(result?.detail).toContain("'wardrobe' array");
    });

    it("rejects wardrobe as number", () => {
      const request = {
        wardrobe: 5,
        context: validContext,
        currentAssignments: [],
      };
      const result = validateAlternativesRequest(request);
      expect(result).not.toBeNull();
      expect(result?.detail).toContain("'wardrobe' array");
    });
  });

  describe("context validation", () => {
    it("validates context fields like generate", () => {
      const request = {
        wardrobe: [],
        context: {},
        currentAssignments: [],
      };
      const result = validateAlternativesRequest(request);
      expect(result).not.toBeNull();
      expect(result?.status).toBe(400);
    });

    it("rejects invalid occasion enum", () => {
      const request = {
        wardrobe: [],
        context: {
          occasion: "invalid_occasion",
          temperatureBand: "MILD",
          occasionFormality: 2,
        },
        currentAssignments: [],
      };
      const result = validateAlternativesRequest(request);
      expect(result).not.toBeNull();
      expect(result?.detail).toContain("context.occasion");
    });

    it("rejects invalid temperatureBand enum", () => {
      const request = {
        wardrobe: [],
        context: {
          occasion: "WEEKEND_ERRANDS",
          temperatureBand: "FREEZING",
          occasionFormality: 2,
        },
        currentAssignments: [],
      };
      const result = validateAlternativesRequest(request);
      expect(result).not.toBeNull();
      expect(result?.detail).toContain("temperatureBand");
    });
  });

  describe("currentAssignments validation", () => {
    it("rejects missing currentAssignments", () => {
      const request = {
        wardrobe: [],
        context: validContext,
      };
      const result = validateAlternativesRequest(request);
      expect(result).not.toBeNull();
      expect(result?.detail).toContain("'currentAssignments' array");
    });

    it("rejects currentAssignments as null", () => {
      const request = {
        wardrobe: [],
        context: validContext,
        currentAssignments: null,
      };
      const result = validateAlternativesRequest(request);
      expect(result).not.toBeNull();
      expect(result?.detail).toContain("'currentAssignments' array");
    });

    it("accepts empty currentAssignments array", () => {
      const request = {
        wardrobe: [],
        context: validContext,
        currentAssignments: [],
      };
      const result = validateAlternativesRequest(request);
      expect(result).toBeNull();
    });
  });
});
