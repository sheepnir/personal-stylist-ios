/**
 * Eval harness CLI — M0-17 / PRD §10.4.
 *
 *   npx tsx src/eval/cli.ts run --models deterministic --scenarios all --repeats 1
 *   npm run eval -- run --models deterministic --scenarios T2-01,T2-02 --repeats 1
 */

import { writeFileSync } from "node:fs";
import { formatJsonSummary, formatTable } from "./report.js";
import { runEval } from "./run.js";

function usage(): never {
  console.error(`Usage:
  eval run --models <csv|deterministic|none> --scenarios <all|T2-01,...|glob> [--repeats N] [--out report.json]

Examples:
  npx tsx src/eval/cli.ts run --models deterministic --scenarios all --repeats 1
  npm run eval -- run --models deterministic --scenarios T2-01,T2-02 --repeats 1
  npm run eval -- run --models deterministic --scenarios M1-F05-07 --repeats 1

Notes:
  - deterministic: T2 via generateLocal; M1-F05-07 via rankAlternatives two-step (zero network)
  - other model ids: stubbed with "model arm deferred until M0-09" (no OpenRouter)
  - exit non-zero if any scenario fails
  - examples: --scenarios M1-F05-07 | T2-01,T2-02 | all | T2-0*
`);
  process.exit(2);
}

function parseArgs(argv: string[]): {
  cmd: string;
  models?: string;
  scenarios?: string;
  repeats: number;
  outPath?: string;
} {
  const [cmd, ...rest] = argv;
  if (!cmd || cmd === "--help" || cmd === "-h") usage();
  let models: string | undefined;
  let scenarios: string | undefined;
  let repeats = 1;
  let outPath: string | undefined;
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (a === "--models") models = rest[++i];
    else if (a === "--scenarios") scenarios = rest[++i];
    else if (a === "--repeats") repeats = Math.max(1, Number(rest[++i]) || 1);
    else if (a === "--out") outPath = rest[++i];
    else if (a === "--help" || a === "-h") usage();
    else {
      console.error(`Unknown argument: ${a}`);
      usage();
    }
  }
  return { cmd, models, scenarios, repeats, outPath };
}

function main(): void {
  const { cmd, models, scenarios, repeats, outPath } = parseArgs(
    process.argv.slice(2),
  );
  if (cmd !== "run") {
    console.error(`Unknown command: ${cmd}`);
    usage();
  }
  if (!models) {
    console.error("--models is required");
    usage();
  }
  if (!scenarios) {
    console.error("--scenarios is required");
    usage();
  }

  const report = runEval({
    models: models.split(",").map((s) => s.trim()).filter(Boolean),
    scenarios,
    repeats,
  });

  const table = formatTable(report);
  const json = formatJsonSummary(report);
  process.stdout.write(table + "\n\n");
  process.stdout.write(json + "\n");

  if (outPath) writeFileSync(outPath, json + "\n", "utf8");
  if (report.failed > 0) process.exitCode = 1;
}

main();
