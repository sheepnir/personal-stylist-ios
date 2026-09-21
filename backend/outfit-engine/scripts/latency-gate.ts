/**
 * CI gate: generateLocal latency vs wardrobe size (#166).
 * Run via: npm run latency:gate  (tsx)
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { generateLocal, isLocalProblem } from "../src/pipeline/generateLocal.js";
import type { GarmentSummary } from "../src/types.js";
import { loadScenario, stage1InputFromScenario } from "../tests/stage1/helpers.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(__dirname, "../../../fixtures");

function loadJson<T>(rel: string): T {
  return JSON.parse(readFileSync(join(FIXTURES, rel), "utf8")) as T;
}

function scaleWardrobe(base: GarmentSummary[], size: number): GarmentSummary[] {
  const ready = base.filter((g) => (g.readiness ?? "READY") === "READY");
  const pool = ready.length ? ready : base;
  const out: GarmentSummary[] = [];
  let i = 0;
  while (out.length < size) {
    const src = pool[i % pool.length]!;
    const n = Math.floor(i / pool.length);
    if (n === 0) {
      out.push({ ...src, setId: null, keepTogether: false });
    } else {
      // Keep UUID shape valid for engine parsers.
      const hex = (i + 1).toString(16).padStart(12, "0");
      out.push({
        ...src,
        id: `${src.id.slice(0, 24)}${hex}`,
        displayName: `${src.displayName} #${n}`,
        setId: null,
        keepTogether: false,
      });
    }
    i += 1;
  }
  if (new Set(out.map((g) => g.id)).size !== size) {
    throw new Error("Benchmark wardrobe must contain distinct IDs");
  }
  return out;
}

function percentile(sorted: number[], p: number): number {
  if (!sorted.length) return 0;
  const idx = Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1);
  return sorted[idx]!;
}

const catalog = loadJson<GarmentSummary[]>("wardrobe/garments.json");
const scenario = loadScenario("T2-01-sportcoat-mild-work");
const s1 = stage1InputFromScenario(scenario);

const budgets = [
  { size: 28, p95Ms: 120 },
  { size: 100, p95Ms: 400 },
  { size: 200, p95Ms: 900 },
] as const;

const repeats = Number(process.env.LATENCY_REPEATS ?? 5);
let failed = false;

for (const budget of budgets) {
  const wardrobe = scaleWardrobe(catalog, budget.size);
  // Prefer the scenario anchor when present; otherwise a TOP from the scaled set.
  const anchor =
    (s1.anchorGarmentId && wardrobe.some((g) => g.id === s1.anchorGarmentId)
      ? s1.anchorGarmentId
      : wardrobe.find((g) => g.slot === "TOP")?.id) ?? wardrobe[0]!.id;

  const samples: number[] = [];
  for (let r = 0; r < repeats; r++) {
    const t0 = performance.now();
    const result = generateLocal({
      wardrobe,
      context: s1.context,
      profile: s1.profile,
      anchorGarmentId: anchor,
      lockedAssignments: [],
      options: s1.options,
      sets: [],
    });
    const ms = performance.now() - t0;
    if (isLocalProblem(result)) {
      console.error(
        `size=${budget.size} produced problem:`,
        (result as { code?: string }).code,
        (result as { detail?: string }).detail,
      );
      failed = true;
      break;
    }
    samples.push(ms);
  }

  if (!samples.length) {
    console.error(`FAIL: no successful samples at size ${budget.size}`);
    failed = true;
    continue;
  }

  samples.sort((a, b) => a - b);
  const p50 = percentile(samples, 50);
  const p95 = percentile(samples, 95);
  console.log(
    `wardrobe=${budget.size} repeats=${samples.length} p50=${p50.toFixed(1)}ms p95=${p95.toFixed(1)}ms budget_p95=${budget.p95Ms}ms`,
  );
  if (p95 > budget.p95Ms) {
    console.error(
      `FAIL: p95 ${p95.toFixed(1)}ms exceeds ${budget.p95Ms}ms at size ${budget.size}`,
    );
    failed = true;
  }
}

if (failed) {
  process.exit(1);
}
console.log("latency-vs-wardrobe gate passed");
