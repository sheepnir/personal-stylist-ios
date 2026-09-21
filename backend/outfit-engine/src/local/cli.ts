/**
 * CLI for local deterministic generate / serve.
 *
 *   tsx src/local/cli.ts generate --in req.json --out out.json
 *   tsx src/local/cli.ts generate   # stdin → stdout
 *   tsx src/local/cli.ts serve
 */

import { readFileSync, writeFileSync } from "node:fs";
import { generateLocal, isLocalProblem } from "../pipeline/generateLocal.js";
import { startLocalServer } from "./server.js";

function usage(): never {
  console.error(`Usage:
  tsx src/local/cli.ts generate [--in req.json] [--out out.json]
  tsx src/local/cli.ts serve

  generate: reads JSON GenerateRequest-ish from --in or stdin; writes response to --out or stdout.
  serve:    starts HTTP server on 127.0.0.1 (PORT env or 8787).`);
  process.exit(2);
}

function parseArgs(argv: string[]): {
  cmd: string;
  inPath?: string;
  outPath?: string;
} {
  const [cmd, ...rest] = argv;
  if (!cmd) usage();
  let inPath: string | undefined;
  let outPath: string | undefined;
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (a === "--in") {
      inPath = rest[++i];
    } else if (a === "--out") {
      outPath = rest[++i];
    } else if (a === "--help" || a === "-h") {
      usage();
    } else {
      console.error(`Unknown argument: ${a}`);
      usage();
    }
  }
  return { cmd, inPath, outPath };
}

async function readStdin(): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString("utf8");
}

async function cmdGenerate(inPath?: string, outPath?: string): Promise<void> {
  const raw = inPath
    ? readFileSync(inPath, "utf8")
    : await readStdin();
  const request = JSON.parse(raw) as Parameters<typeof generateLocal>[0];
  const result = generateLocal(request);
  const text = JSON.stringify(result, null, 2) + "\n";
  if (outPath) {
    writeFileSync(outPath, text, "utf8");
  } else {
    process.stdout.write(text);
  }
  if (isLocalProblem(result)) {
    process.exitCode = 1;
  }
}

function main(): void {
  const { cmd, inPath, outPath } = parseArgs(process.argv.slice(2));
  if (cmd === "generate") {
    void cmdGenerate(inPath, outPath);
  } else if (cmd === "serve") {
    startLocalServer();
  } else {
    console.error(`Unknown command: ${cmd}`);
    usage();
  }
}

main();
