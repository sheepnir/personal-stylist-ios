import { describe, expect, it } from "vitest";
import { evaluateScenario, runEval } from "../../src/eval/index.js";

describe("eval harness (M0-17)", () => {
  it("classifies complete scenarios T2-01 / T2-03 as complete and passing", () => {
    const r01 = evaluateScenario("T2-01");
    const r03 = evaluateScenario("T2-03");

    expect(r01.expectedClassification).toBe("complete");
    expect(r01.actualClassification).toBe("complete");
    expect(r01.passed).toBe(true);

    expect(r03.expectedClassification).toBe("complete");
    expect(r03.actualClassification).toBe("complete");
    expect(r03.passed).toBe(true);
  });

  it("classifies problem scenarios T2-04 / T2-10 as problem and passing", () => {
    const r04 = evaluateScenario("T2-04");
    const r10 = evaluateScenario("T2-10");

    expect(r04.expectedClassification).toBe("problem");
    expect(r04.actualClassification).toBe("problem");
    expect(r04.passed).toBe(true);
    expect(r04.actualSummary.problemCode).toBe("SET_CONFLICT");

    expect(r10.expectedClassification).toBe("problem");
    expect(r10.actualClassification).toBe("problem");
    expect(r10.passed).toBe(true);
    expect(r10.actualSummary.problemCode).toBe("LOCK_CONFLICT");
  });

  it("runEval deterministic all: pass/fail counts and known fixtures pass", () => {
    const report = runEval({
      models: ["deterministic"],
      scenarios: "all",
      repeats: 1,
    });

    expect(report.results.length).toBeGreaterThanOrEqual(12);
    expect(report.passed + report.failed).toBe(report.results.length);
    expect(report.deferredModels).toEqual([]);

    const byId = Object.fromEntries(
      report.results.map((r) => [r.scenarioId, r]),
    );
    expect(byId["T2-01-sportcoat-mild-work"]?.passed).toBe(true);
    expect(byId["T2-03-suit-anchor-atomic"]?.passed).toBe(true);
    expect(byId["T2-04-set-conflict-partner-laundry"]?.passed).toBe(true);
    expect(byId["T2-10-lock-conflict"]?.passed).toBe(true);
  });

  it("defers non-deterministic model arms (no OpenRouter)", () => {
    const report = runEval({
      models: ["gpt-4o"],
      scenarios: "T2-01",
      repeats: 1,
    });
    expect(report.results).toHaveLength(0);
    expect(report.deferredModels).toContain("gpt-4o");
    expect(
      report.deferredMessages.some((m) =>
        m.includes("model arm deferred until M0-09"),
      ),
    ).toBe(true);
  });

  it("T2-20 is byte-identical to T2-01 on the deterministic arm", () => {
    const a = evaluateScenario("T2-01");
    const b = evaluateScenario("T2-20");
    expect(a.passed).toBe(true);
    expect(b.passed).toBe(true);
    expect(JSON.stringify(a.actualSummary.outfit)).toBe(
      JSON.stringify(b.actualSummary.outfit),
    );
  });

  it("M0-13 new T2 ids soft-pass on deterministic", () => {
    const report = runEval({
      models: ["deterministic"],
      scenarios:
        "T2-13,T2-14,T2-15,T2-16,T2-17,T2-18,T2-19,T2-20,T2-21,T2-22,T2-24,T2-28",
      repeats: 1,
    });
    expect(report.failed).toBe(0);
    expect(report.passed).toBe(report.results.length);
    expect(report.results.length).toBe(14);
  });

  it("repeats assert determinism for deterministic arm", () => {
    const report = runEval({
      models: ["deterministic"],
      scenarios: "T2-01,T2-10",
      repeats: 3,
    });
    expect(report.results).toHaveLength(2);
    for (const r of report.results) {
      expect(r.deterministic).toBe(true);
      expect(r.passed).toBe(true);
    }
  });

  it("M1-F05-07 alternatives_swap_rerank soft-passes (D-33 A-STALE)", () => {
    const r = evaluateScenario("M1-F05-07");
    expect(r.expectedClassification).toBe("alternatives");
    expect(r.actualClassification).toBe("alternatives");
    expect(r.passed).toBe(true);
    expect(r.failures).toEqual([]);
    expect(r.actualSummary.step1RankedIds).toEqual([
      "a1000006-0006-4000-8000-000000000004",
    ]);
    expect(r.actualSummary.step2RankedIds).toEqual([
      "a1000001-0001-4000-8000-000000000004",
      "a1000001-0001-4000-8000-000000000003",
      "a1000001-0001-4000-8000-000000000006",
    ]);
    expect(r.actualSummary.aStaleOrderDiffers).toBe(true);
  });

  it("runEval can select M1-F05-07 by id", () => {
    const report = runEval({
      models: ["deterministic"],
      scenarios: "M1-F05-07",
      repeats: 1,
    });
    expect(report.results).toHaveLength(1);
    expect(report.results[0]?.scenarioId).toBe("M1-F05-07-swap-rerank");
    expect(report.passed).toBe(1);
    expect(report.failed).toBe(0);
  });
});
