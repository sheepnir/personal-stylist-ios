/**
 * Pretty table + JSON summary for eval CLI stdout.
 */

import type { EvalReport, ScenarioEvalResult } from "./types.js";

function pad(s: string | undefined | null, n: number): string {
  const str = s ?? "";
  if (str.length >= n) return str.slice(0, n);
  return str + " ".repeat(n - str.length);
}

export function formatTable(report: EvalReport): string {
  const header =
    pad("scenario", 36) +
    " " +
    pad("status", 6) +
    " " +
    pad("class", 18) +
    " " +
    pad("exact", 5) +
    " " +
    pad("det", 5) +
    " " +
    pad("failures", 48);

  const sep = "-".repeat(header.length);
  const lines = [header, sep];

  for (const r of report.results) {
    const status = r.passed ? "PASS" : "FAIL";
    const klass = `${r.expectedClassification}→${r.actualClassification}`;
    const exact =
      r.exactOutfitMatch === null
        ? "n/a"
        : r.exactOutfitMatch
          ? "yes"
          : "no";
    const det =
      r.deterministic === null || r.deterministic === undefined
        ? "n/a"
        : r.deterministic
          ? "yes"
          : "no";
    const fail = r.failures.join("; ") || "";
    lines.push(
      pad(r.scenarioId, 36) +
        " " +
        pad(status, 6) +
        " " +
        pad(klass, 18) +
        " " +
        pad(exact, 5) +
        " " +
        pad(det, 5) +
        " " +
        pad(fail, 48),
    );
  }

  lines.push(sep);
  lines.push(
    `passed=${report.passed}  failed=${report.failed}  total=${report.results.length}  repeats=${report.repeats}`,
  );
  if (report.deferredMessages.length) {
    lines.push("deferred:");
    for (const m of report.deferredMessages) lines.push(`  - ${m}`);
  }
  return lines.join("\n");
}

export function formatJsonSummary(report: EvalReport): string {
  return JSON.stringify(report, null, 2);
}
