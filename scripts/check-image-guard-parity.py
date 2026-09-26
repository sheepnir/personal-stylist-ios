#!/usr/bin/env python3
"""Fail when the iOS client's image-payload guard drifts from the Worker's.

Compares forbidden-token lists, consent path segments, and the RFC 3339 consent
regex extracted from backend/workers and App/OutfitEngineClient.swift, then runs
fixtures/image-guard/corpus.json through the Worker's vitest harness.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "fixtures/image-guard/corpus.json"
WORKER_KEY = ROOT / "backend/workers/src/imageGuardKey.ts"
WORKER = ROOT / "backend/workers/src/validation.ts"
WORKER_CONSENT = ROOT / "backend/workers/src/imageGuardConsent.ts"
CLIENT = ROOT / "App/OutfitEngineClient.swift"
WORKERS_DIR = ROOT / "backend/workers"

WORKER_TOKENS = re.compile(
    r"export const FORBIDDEN_IMAGE_KEY_TOKENS = \[([\s\S]*?)\] as const;",
    re.MULTILINE,
)
CLIENT_TOKENS = re.compile(
    r"private static let forbiddenImageKeyTokens = \[([\s\S]*?)\]",
    re.MULTILINE,
)
WORKER_CONSENT_SEGMENTS = re.compile(
    r"export const IMAGE_GUARD_CONSENT_FIELD_SEGMENTS = \[([\s\S]*?)\] as const;"
)
CLIENT_CONSENT_SEGMENTS = re.compile(
    r"private static let imageGuardConsentFieldSegments = \[([\s\S]*?)\]"
)
WORKER_RFC3339 = re.compile(
    r"export const WARDROBE_IMAGES_ACCEPTED_AT_RFC3339\s*=\s*\n?\s*/([^/]+)/;"
)
CLIENT_RFC3339 = re.compile(
    r'wardrobeImagesAcceptedAtRfc3339 = try! NSRegularExpression\(\s*pattern: #"([^"]+)"#'
)


def extract_tokens(path: Path, pattern: re.Pattern[str]) -> list[str]:
    match = pattern.search(path.read_text(encoding="utf-8"))
    if not match:
        sys.exit(f"{path.relative_to(ROOT)}: could not extract forbidden token list")
    raw = match.group(1)
    return [m.group(1).lower() for m in re.finditer(r"""['"]([^'"]+)['"]""", raw)]


def extract_segments(path: Path, pattern: re.Pattern[str]) -> list[str]:
    match = pattern.search(path.read_text(encoding="utf-8"))
    if not match:
        sys.exit(f"{path.relative_to(ROOT)}: could not extract consent path segments")
    raw = match.group(1)
    return [m.group(1) for m in re.finditer(r"""['"]([^'"]+)['"]""", raw)]


def extract_rfc3339(path: Path, pattern: re.Pattern[str]) -> str:
    match = pattern.search(path.read_text(encoding="utf-8"))
    if not match:
        sys.exit(f"{path.relative_to(ROOT)}: could not extract RFC 3339 consent regex")
    return match.group(1)


def load_corpus() -> dict:
    corpus = json.loads(CORPUS.read_text(encoding="utf-8"))
    for key in ("keySegments", "rejectBodies", "allowBodies"):
        if key not in corpus or not isinstance(corpus[key], list):
            sys.exit(f"{CORPUS.relative_to(ROOT)}: missing or invalid {key!r} list")
    return corpus


def run_worker_vitest_corpus() -> None:
    result = subprocess.run(
        ["npm", "test", "--", "image-guard-corpus"],
        cwd=WORKERS_DIR,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stdout)
        print(result.stderr, file=sys.stderr)
        sys.exit("Worker vitest corpus check failed")


def main() -> int:
    worker_tokens = extract_tokens(WORKER_KEY, WORKER_TOKENS)
    client_tokens = extract_tokens(CLIENT, CLIENT_TOKENS)
    worker_segments = extract_segments(WORKER, WORKER_CONSENT_SEGMENTS)
    client_segments = extract_segments(CLIENT, CLIENT_CONSENT_SEGMENTS)
    worker_rfc = extract_rfc3339(WORKER_CONSENT, WORKER_RFC3339)
    client_rfc = extract_rfc3339(CLIENT, CLIENT_RFC3339)

    if worker_tokens != client_tokens:
        print(f"MISMATCH forbidden tokens:\n  worker: {worker_tokens}\n  client: {client_tokens}")
        return 1
    print(f"OK forbidden tokens: {len(worker_tokens)} entries match")

    if worker_segments != client_segments:
        print(f"MISMATCH consent segments:\n  worker: {worker_segments}\n  client: {client_segments}")
        return 1
    print(f"OK consent segments: {worker_segments}")

    if worker_rfc != client_rfc:
        print(f"MISMATCH RFC 3339 regex:\n  worker: {worker_rfc}\n  client: {client_rfc}")
        return 1
    print("OK RFC 3339 consent regex")

    corpus = load_corpus()
    print(
        f"OK corpus loaded: {len(corpus['keySegments'])} key segments, "
        f"{len(corpus.get('allowGuardedEndpointKeys', []))} guarded-endpoint keys, "
        f"{len(corpus['rejectBodies'])} reject bodies, "
        f"{len(corpus['allowBodies'])} allow bodies"
    )

    run_worker_vitest_corpus()
    print("OK worker vitest image-guard-corpus")
    return 0


if __name__ == "__main__":
    sys.exit(main())
