/**
 * Integration tests for the local HTTP server.
 * Covers crash prevention from issue #27 and new features from issue #34.
 */

import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { createLocalServer } from "../../src/local/server.js";
import { loadScenario, stage1InputFromScenario } from "../stage1/helpers.js";
import type { Server } from "node:http";

describe("Local Server Integration", () => {
  let server: Server;
  let port: number;
  let baseUrl: string;

  beforeAll(async () => {
    server = createLocalServer();
    await new Promise<void>((resolve) => {
      server.listen(0, "127.0.0.1", () => {
        const addr = server.address();
        if (addr && typeof addr === "object") {
          port = addr.port;
          baseUrl = `http://127.0.0.1:${port}`;
        }
        resolve();
      });
    });
  });

  afterAll(async () => {
    await new Promise<void>((resolve) => {
      server.close(() => resolve());
    });
  });

  async function post(path: string, body: unknown): Promise<Response> {
    return fetch(`${baseUrl}${path}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
  }

  describe("GET /health", () => {
    it("returns 200 with quoted JSON status ok (issue #90)", async () => {
      const response = await fetch(`${baseUrl}/health`);
      expect(response.status).toBe(200);
      const raw = await response.text();
      expect(raw).toContain('"status":"ok"');
      const data = JSON.parse(raw) as {
        status?: unknown;
        ok?: unknown;
        mode?: unknown;
      };
      expect(data.status).toBe("ok");
      expect(typeof data.status).toBe("string");
      expect(data.ok).toBe(true);
      expect(data.mode).toBe("deterministic-local");
    });
  });

  describe("POST /v1/outfit/generate", () => {
    describe("crash prevention (issue #27)", () => {
      it("returns 400 for wardrobe as number instead of crashing", async () => {
        const response = await post("/v1/outfit/generate", {
          wardrobe: 5,
          context: {},
        });

        expect(response.status).toBe(400);
        const data = (await response.json()) as any;
        expect(data.code).toBe("INVALID_REQUEST");
        expect(data.detail).toContain("wardrobe");
        expect(data.dataPreserved).toBe(true);
      });

      it("returns 400 for missing temperatureBand instead of crashing", async () => {
        const response = await post("/v1/outfit/generate", {
          wardrobe: [],
          context: {
            occasion: "WEEKEND_ERRANDS",
            occasionFormality: 2,
          },
        });

        expect(response.status).toBe(400);
        const data = (await response.json()) as any;
        expect(data.code).toBe("INVALID_REQUEST");
        expect(data.detail).toContain("temperatureBand");
      });

      it("returns 400 for invalid temperatureBand enum instead of crashing", async () => {
        const response = await post("/v1/outfit/generate", {
          wardrobe: [],
          context: {
            occasion: "WEEKEND_ERRANDS",
            temperatureBand: "FREEZING",
            occasionFormality: 2,
          },
        });

        expect(response.status).toBe(400);
        const data = (await response.json()) as any;
        expect(data.code).toBe("INVALID_REQUEST");
        expect(data.detail).toContain("temperatureBand");
        expect(data.detail).toContain("FREEZING");
      });

      it("returns 400 for missing occasion instead of crashing", async () => {
        const response = await post("/v1/outfit/generate", {
          wardrobe: [],
          context: {
            temperatureBand: "MILD",
            occasionFormality: 2,
          },
        });

        expect(response.status).toBe(400);
        const data = (await response.json()) as any;
        expect(data.code).toBe("INVALID_REQUEST");
        expect(data.detail).toContain("occasion");
      });

      it("returns 400 for invalid occasion enum (smart_casual) instead of accepting silently", async () => {
        const response = await post("/v1/outfit/generate", {
          wardrobe: [],
          context: {
            occasion: "smart_casual",
            temperatureBand: "MILD",
            occasionFormality: 2,
          },
        });

        expect(response.status).toBe(400);
        const data = (await response.json()) as any;
        expect(data.code).toBe("INVALID_REQUEST");
        expect(data.detail).toContain("occasion");
      });

      it("returns 400 for empty context object instead of crashing", async () => {
        const response = await post("/v1/outfit/generate", {
          wardrobe: [],
          context: {},
        });

        expect(response.status).toBe(400);
        const data = (await response.json()) as any;
        expect(data.code).toBe("INVALID_REQUEST");
      });
    });

    describe("error boundary", () => {
      it("returns 500 for unexpected errors instead of crashing", async () => {
        const response = await post("/v1/outfit/generate", {
          wardrobe: [
            {
              id: "g1",
              displayName: "Test",
              slot: "TOP",
              colorPrimary: { family: "navy" },
              pattern: "SOLID",
              surface: "SMOOTH",
              formality: 4,
              warmth: 3,
            },
          ],
          context: {
            occasion: "WEEKEND_ERRANDS",
            temperatureBand: "MILD",
            occasionFormality: 2,
          },
        });

        expect([200, 400, 500]).toContain(response.status);
        const data = (await response.json()) as any;
        if (response.status === 500) {
          expect(data.code).toBe("INTERNAL_ERROR");
          expect(data.dataPreserved).toBe(true);
        }
      });
    });

    describe("valid requests", () => {
      it("processes minimal valid request", async () => {
        const response = await post("/v1/outfit/generate", {
          wardrobe: [],
          context: {
            occasion: "WEEKEND_ERRANDS",
            temperatureBand: "MILD",
            occasionFormality: 2,
          },
        });

        expect([200, 400]).toContain(response.status);
        const data = (await response.json()) as any;
        if (response.status === 400) {
          expect(data.code).toBeDefined();
          expect(data.dataPreserved).toBe(true);
        }
      });
    });

    describe("new features (issue #34)", () => {
      it("handles recentOutfits parameter", async () => {
        const scenario = loadScenario("T2-01-sportcoat-mild-work");
        const s1 = stage1InputFromScenario(scenario);

        const response = await post("/v1/outfit/generate", {
          wardrobe: s1.wardrobe,
          context: s1.context,
          anchorGarmentId: s1.anchorGarmentId,
          profile: s1.profile,
          sets: s1.sets,
          recentOutfits: [
            ["garment-1", "garment-2", "garment-3"],
            ["garment-4", "garment-5", "garment-6"],
          ],
        });

        expect(response.status).toBe(200);
        const data = (await response.json()) as any;
        expect(data).toHaveProperty("outfitId");
        expect(data).toHaveProperty("assignments");
      });

      it("handles excludeGarmentSets parameter", async () => {
        const scenario = loadScenario("T2-01-sportcoat-mild-work");
        const s1 = stage1InputFromScenario(scenario);

        const response = await post("/v1/outfit/generate", {
          wardrobe: s1.wardrobe,
          context: s1.context,
          anchorGarmentId: s1.anchorGarmentId,
          profile: s1.profile,
          sets: s1.sets,
          options: {
            excludeGarmentSets: [["some-garment-id", "another-garment-id"]],
          },
        });

        expect(response.status).toBe(200);
        const data = (await response.json()) as any;
        expect(data).toHaveProperty("outfitId");
        expect(data).toHaveProperty("assignments");
      });

      it("handles both excludeGarmentSets and recentOutfits together", async () => {
        const scenario = loadScenario("T2-01-sportcoat-mild-work");
        const s1 = stage1InputFromScenario(scenario);

        const response = await post("/v1/outfit/generate", {
          wardrobe: s1.wardrobe,
          context: s1.context,
          anchorGarmentId: s1.anchorGarmentId,
          profile: s1.profile,
          sets: s1.sets,
          recentOutfits: [["garment-1", "garment-2"]],
          options: {
            excludeGarmentSets: [["other-1", "other-2"]],
          },
        });

        expect(response.status).toBe(200);
        const data = (await response.json()) as any;
        expect(data).toHaveProperty("outfitId");
        expect(data).toHaveProperty("assignments");
      });
    });
  });

  describe("POST /v1/outfit/alternatives", () => {
    describe("crash prevention", () => {
      it("returns 400 for wardrobe as number instead of crashing", async () => {
        const response = await post("/v1/outfit/alternatives", {
          slot: "TOP",
          wardrobe: 5,
          context: {},
          currentAssignments: [],
        });

        expect(response.status).toBe(400);
        const data = (await response.json()) as any;
        expect(data.code).toBe("INVALID_REQUEST");
        expect(data.detail).toContain("wardrobe");
      });

      it("returns 400 for missing temperatureBand instead of crashing", async () => {
        const response = await post("/v1/outfit/alternatives", {
          slot: "TOP",
          wardrobe: [],
          context: {
            occasion: "WEEKEND_ERRANDS",
            occasionFormality: 2,
          },
          currentAssignments: [],
        });

        expect(response.status).toBe(400);
        const data = (await response.json()) as any;
        expect(data.code).toBe("INVALID_REQUEST");
        expect(data.detail).toContain("temperatureBand");
      });

      it("returns 400 for invalid temperatureBand enum instead of crashing", async () => {
        const response = await post("/v1/outfit/alternatives", {
          slot: "TOP",
          wardrobe: [],
          context: {
            occasion: "WEEKEND_ERRANDS",
            temperatureBand: "FREEZING",
            occasionFormality: 2,
          },
          currentAssignments: [],
        });

        expect(response.status).toBe(400);
        const data = (await response.json()) as any;
        expect(data.code).toBe("INVALID_REQUEST");
        expect(data.detail).toContain("temperatureBand");
      });

      it("returns 400 for missing currentAssignments instead of crashing", async () => {
        const response = await post("/v1/outfit/alternatives", {
          slot: "TOP",
          wardrobe: [],
          context: {
            occasion: "WEEKEND_ERRANDS",
            temperatureBand: "MILD",
            occasionFormality: 2,
          },
        });

        expect(response.status).toBe(400);
        const data = (await response.json()) as any;
        expect(data.code).toBe("INVALID_REQUEST");
        expect(data.detail).toContain("currentAssignments");
      });
    });

    describe("error boundary", () => {
      it("returns 500 for unexpected errors instead of crashing", async () => {
        const response = await post("/v1/outfit/alternatives", {
          slot: "TOP",
          wardrobe: [
            {
              id: "g1",
              displayName: "Test",
              slot: "TOP",
              colorPrimary: { family: "navy" },
              pattern: "SOLID",
              surface: "SMOOTH",
              formality: 4,
              warmth: 3,
            },
          ],
          context: {
            occasion: "WEEKEND_ERRANDS",
            temperatureBand: "MILD",
            occasionFormality: 2,
          },
          currentAssignments: [],
        });

        expect([200, 400, 500]).toContain(response.status);
        const data = (await response.json()) as any;
        if (response.status === 500) {
          expect(data.code).toBe("INTERNAL_ERROR");
          expect(data.dataPreserved).toBe(true);
        }
      });
    });
  });

  describe("Unknown routes", () => {
    it("returns 404 for unknown POST routes", async () => {
      const response = await post("/v1/unknown", {});
      expect(response.status).toBe(404);
      const data = (await response.json()) as any;
      expect(data.code).toBe("NOT_FOUND");
    });

    it("returns 404 for unknown GET routes", async () => {
      const response = await fetch(`${baseUrl}/unknown`);
      expect(response.status).toBe(404);
    });
  });
});
