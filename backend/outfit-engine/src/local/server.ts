/**
 * Local HTTP bridge for iOS / simulator → deterministic outfit generate + alternatives.
 * Binds 127.0.0.1 only. Zero outbound network / OpenRouter.
 */

import http from "node:http";
import {
  generateLocal,
  isLocalProblem,
  type LocalGenerateRequest,
  type LocalProblemBody,
} from "../pipeline/generateLocal.js";
import {
  rankAlternatives,
  isAlternativesProblem,
  type AlternativesRequest,
} from "../alternatives/rankAlternatives.js";
import {
  validateGenerateRequest,
  validateAlternativesRequest,
} from "./validation.js";

const HOST = "127.0.0.1";
const DEFAULT_PORT = 8787;

function json(
  res: http.ServerResponse,
  status: number,
  body: unknown,
): void {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(payload),
  });
  res.end(payload);
}

function readBody(req: http.IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on("data", (c: Buffer) => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function invalidJson(res: http.ServerResponse): void {
  json(res, 400, {
    title: "Invalid JSON",
    status: 400,
    detail: "Request body must be application/json.",
    code: "INVALID_REQUEST",
    dataPreserved: true,
  });
}

function badBody(res: http.ServerResponse): void {
  json(res, 400, {
    title: "Bad request",
    status: 400,
    detail: "Failed to read request body.",
    code: "INVALID_REQUEST",
    dataPreserved: true,
  });
}

function internalError(res: http.ServerResponse, error: unknown): void {
  const message =
    error instanceof Error ? error.message : String(error);
  // eslint-disable-next-line no-console
  console.error("[outfit-engine local] Internal error:", error);
  json(res, 500, {
    title: "Internal server error",
    status: 500,
    detail: message,
    code: "INTERNAL_ERROR",
    dataPreserved: true,
  });
}

export function createLocalServer(): http.Server {
  return http.createServer(async (req, res) => {
    const method = req.method ?? "GET";
    const url = new URL(req.url ?? "/", `http://${HOST}`);

    if (method === "GET" && url.pathname === "/health") {
      // status is a JSON string ("ok"), not a bare identifier — issue #90.
      json(res, 200, { status: "ok", ok: true, mode: "deterministic-local" });
      return;
    }

    if (method === "POST" && url.pathname === "/v1/outfit/generate") {
      let raw: string;
      try {
        raw = await readBody(req);
      } catch {
        badBody(res);
        return;
      }

      let body: LocalGenerateRequest;
      try {
        body = raw
          ? (JSON.parse(raw) as LocalGenerateRequest)
          : ({} as LocalGenerateRequest);
      } catch {
        invalidJson(res);
        return;
      }

      const validationError = validateGenerateRequest(body);
      if (validationError) {
        json(res, 400, validationError);
        return;
      }

      try {
        const result = generateLocal(body);
        if (isLocalProblem(result)) {
          json(res, 400, result);
          return;
        }
        json(res, 200, result);
      } catch (error) {
        internalError(res, error);
      }
      return;
    }

    if (method === "POST" && url.pathname === "/v1/outfit/alternatives") {
      let raw: string;
      try {
        raw = await readBody(req);
      } catch {
        badBody(res);
        return;
      }

      let body: AlternativesRequest;
      try {
        body = raw
          ? (JSON.parse(raw) as AlternativesRequest)
          : ({} as AlternativesRequest);
      } catch {
        invalidJson(res);
        return;
      }

      const validationError = validateAlternativesRequest(body);
      if (validationError) {
        json(res, 400, validationError);
        return;
      }

      try {
        const result = rankAlternatives(body);
        if (isAlternativesProblem(result)) {
          json(res, 400, result);
          return;
        }
        json(res, 200, result);
      } catch (error) {
        internalError(res, error);
      }
      return;
    }

    json(res, 404, {
      title: "Not found",
      status: 404,
      detail: `No route for ${method} ${url.pathname}`,
      code: "NOT_FOUND",
      dataPreserved: true,
    });
  });
}

export function startLocalServer(
  port = Number(process.env.PORT) || DEFAULT_PORT,
): http.Server {
  const server = createLocalServer();
  server.listen(port, HOST, () => {
    // eslint-disable-next-line no-console
    console.log(
      `[outfit-engine local] listening on http://${HOST}:${port} (deterministic, no network outbound)`,
    );
  });
  return server;
}

/** Entrypoint when run via `tsx src/local/server.ts` / serve:local */
import { pathToFileURL } from "node:url";
const isMain =
  import.meta.url === pathToFileURL(process.argv[1] ?? "").href;

if (isMain) {
  startLocalServer();
}
